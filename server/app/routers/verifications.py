import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app import coupon_rules, running_week, stamp_rules
from app import verification as verification_logic
from app.db import get_db
from app.deps import current_user_id
from app.models import Coupon, Course, Run, Stamp, StampDefinition, UserCoupon, Verification
from app.schemas import VerificationCreate, VerificationOut

router = APIRouter(tags=["verifications"])


# 팝업은 이번 러닝으로 새로 받은 것만 띄운다 — 같은 코스를 다시 완주해도 다시 뜨지 않게
# 발급 기록의 run_id로 찾는다.


def _earned_stamp_id(db: Session, run_id: uuid.UUID, course_id: uuid.UUID) -> uuid.UUID | None:
    """이 러닝으로 받은 코스 스탬프. 여러 개면 처음 것."""
    definition_ids = [d.id for d in stamp_rules.course_stamp_definitions(db, course_id)]
    if not definition_ids:
        return None

    return db.execute(
        select(Stamp.id)
        .where(Stamp.run_id == run_id, Stamp.stamp_definition_id.in_(definition_ids))
        .order_by(Stamp.acquired_at)
        .limit(1)
    ).scalar_one_or_none()


def _earned_coupon_id(db: Session, run_id: uuid.UUID, course_id: uuid.UUID) -> uuid.UUID | None:
    """이 러닝으로 받은 코스완료 쿠폰."""
    return db.execute(
        select(UserCoupon.id)
        .where(
            UserCoupon.run_id == run_id,
            UserCoupon.grant_key == coupon_rules.course_grant_key(course_id),
        )
        .order_by(UserCoupon.issued_at)
        .limit(1)
    ).scalar_one_or_none()


def _running_week_stamp_ids(db: Session, run_id: uuid.UUID) -> list[uuid.UUID]:
    """이 러닝으로 받은 러닝위크 스탬프. 코스 전용 스탬프 먼저, 빙고 스탬프는 줄 수 순."""
    rows = db.execute(
        select(Stamp.id, StampDefinition.condition_type, StampDefinition.condition_params)
        .join(StampDefinition, Stamp.stamp_definition_id == StampDefinition.id)
        .where(
            Stamp.run_id == run_id,
            StampDefinition.condition_type.in_(
                (stamp_rules.RUNNING_WEEK_COURSE, stamp_rules.BINGO_LINES)
            ),
        )
    ).all()

    def order(row) -> int:
        _, condition_type, params = row
        return 0 if condition_type == stamp_rules.RUNNING_WEEK_COURSE else int(params["lines"])

    return [row[0] for row in sorted(rows, key=order)]


def _running_week_coupon_ids(db: Session, run_id: uuid.UUID) -> list[uuid.UUID]:
    """이 러닝으로 받은 러닝위크 쿠폰. 줄 리워드는 줄 수 순, 스페셜 쿠폰이 마지막."""
    rows = db.execute(
        select(UserCoupon.id, Coupon.trigger_type, Coupon.trigger_params)
        .join(Coupon, UserCoupon.coupon_id == Coupon.id)
        .where(
            UserCoupon.run_id == run_id,
            Coupon.trigger_type.in_((coupon_rules.BINGO_LINES, coupon_rules.BINGO_COMPLETE)),
        )
    ).all()

    def order(row) -> int:
        _, trigger_type, params = row
        if trigger_type == coupon_rules.BINGO_LINES:
            return int((params or {}).get("lines", 0))
        return 10_000

    return [row[0] for row in sorted(rows, key=order)]


def _to_out(db: Session, verification: Verification) -> dict:
    matched = verification.status == "matched"
    run_id = verification.run_id
    stamp_id = _earned_stamp_id(db, run_id, verification.course_id) if matched else None
    coupon_id = _earned_coupon_id(db, run_id, verification.course_id) if matched else None
    week_stamp_ids = _running_week_stamp_ids(db, verification.run_id) if matched else []
    week_coupon_ids = _running_week_coupon_ids(db, verification.run_id) if matched else []

    return {
        "id": verification.id,
        "run_id": verification.run_id,
        "course_id": verification.course_id,
        "status": verification.status,
        "match_rate": verification.match_rate,
        "detail": verification.detail,
        "completed_at": verification.completed_at,
        "earned_stamp_id": stamp_id,
        "earned_coupon_id": coupon_id,
        "earned_running_week_stamp_ids": week_stamp_ids,
        "earned_running_week_coupon_ids": week_coupon_ids,
        "earned_bingo_coupon_id": week_coupon_ids[0] if week_coupon_ids else None,
    }


@router.post("/runs/{run_id}/verification", response_model=VerificationOut, status_code=201)
def request_verification(
    run_id: uuid.UUID,
    payload: VerificationCreate,
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
):
    """경로 검증 요청.

    지금은 FastAPI가 검증까지 동기로 계산해 결과를 바로 돌려준다.
    검증 서버를 분리하면 여기서 요청만 넘기고 status='pending'으로 응답하게 되며,
    클라이언트는 GET /verifications/{id}로 폴링한다(앱은 이미 그 흐름을 지원한다).
    """
    run = db.get(Run, run_id)
    if run is None or run.user_id != user_id:
        raise HTTPException(status_code=404, detail="러닝 기록을 찾을 수 없어요.")

    course = db.get(Course, payload.course_id)
    if course is None:
        raise HTTPException(status_code=404, detail="코스를 찾을 수 없어요.")

    # 같은 (러닝, 코스) 조합은 한 번만 계산한다. 앱이 재시도로 다시 호출해도
    # CPU를 또 쓰지 않고 기존 결과를 그대로 돌려준다.
    existing = db.execute(
        select(Verification).where(
            Verification.run_id == run_id, Verification.course_id == course.id
        )
    ).scalar_one_or_none()

    if existing is not None:
        return _to_out(db, existing)

    # 러닝 경로만 구간으로 나눈다. 일시정지 동안 이동한 구간을 달린 것으로 세지
    # 않으려는 것이고(to_segments), 코스 경로는 끊기는 자리가 없다.
    outcome = verification_logic.verify_segments(
        course_path=verification_logic.to_points(course.path or []),
        run_segments=verification_logic.to_segments(run.path or []),
    )

    record = Verification(
        run_id=run.id,
        course_id=course.id,
        status=outcome.status,
        match_rate=outcome.match_rate,
        detail=outcome.detail,
        completed_at=datetime.now(timezone.utc),
    )
    db.add(record)

    if outcome.status == "matched":
        # 코스 스탬프는 상시, 쿠폰·빙고는 러닝위크일 때만(running_week가 판단).
        stamp_rules.on_course_completed(db, user_id, run, course.id)
        running_week.on_course_completed(db, user_id, course.id, run.id)

    db.commit()
    db.refresh(record)

    return _to_out(db, record)


@router.get("/verifications/{verification_id}", response_model=VerificationOut)
def get_verification(
    verification_id: uuid.UUID,
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
):
    """검증 진행 상태 조회(폴링용)."""
    record = db.get(Verification, verification_id)
    if record is None:
        raise HTTPException(status_code=404, detail="검증 정보를 찾을 수 없어요.")

    if record.run.user_id != user_id:
        raise HTTPException(status_code=404, detail="검증 정보를 찾을 수 없어요.")

    return _to_out(db, record)
