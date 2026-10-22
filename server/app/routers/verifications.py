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


def _earned_stamp_id(db: Session, user_id: str, course_id: uuid.UUID) -> uuid.UUID | None:
    """이 코스 완주로 받는 스탬프 중 사용자가 가진 것. 여러 개면 처음 것."""
    definition_ids = [d.id for d in stamp_rules.course_stamp_definitions(db, course_id)]
    if not definition_ids:
        return None

    return db.execute(
        select(Stamp.id)
        .where(Stamp.user_id == user_id, Stamp.stamp_definition_id.in_(definition_ids))
        .order_by(Stamp.acquired_at)
        .limit(1)
    ).scalar_one_or_none()


def _earned_coupon_id(db: Session, user_id: str, course_id: uuid.UUID) -> uuid.UUID | None:
    """이 코스 완주로 받은 코스완료 쿠폰. 여러 템플릿이면 처음 것."""
    return db.execute(
        select(UserCoupon.id)
        .where(
            UserCoupon.user_id == user_id,
            UserCoupon.grant_key == coupon_rules.course_grant_key(course_id),
        )
        .order_by(UserCoupon.issued_at)
        .limit(1)
    ).scalar_one_or_none()


def _bingo_stamp_ids(db: Session, run_id: uuid.UUID) -> list[uuid.UUID]:
    """이 러닝으로 받은 빙고 스탬프. 줄 수 순."""
    rows = db.execute(
        select(Stamp.id, StampDefinition.condition_params)
        .join(StampDefinition, Stamp.stamp_definition_id == StampDefinition.id)
        .where(Stamp.run_id == run_id, StampDefinition.condition_type == stamp_rules.BINGO_LINES)
    ).all()
    return [stamp_id for stamp_id, params in sorted(rows, key=lambda r: int(r[1]["lines"]))]


def _bingo_coupon_id(db: Session, run_id: uuid.UUID) -> uuid.UUID | None:
    """이 러닝으로 받은 스페셜 쿠폰."""
    return db.execute(
        select(UserCoupon.id)
        .join(Coupon, UserCoupon.coupon_id == Coupon.id)
        .where(
            UserCoupon.run_id == run_id, Coupon.trigger_type == coupon_rules.BINGO_COMPLETE
        )
        .limit(1)
    ).scalar_one_or_none()


def _to_out(db: Session, verification: Verification, user_id: str) -> dict:
    matched = verification.status == "matched"
    stamp_id = _earned_stamp_id(db, user_id, verification.course_id) if matched else None
    coupon_id = _earned_coupon_id(db, user_id, verification.course_id) if matched else None
    bingo_stamp_ids = _bingo_stamp_ids(db, verification.run_id) if matched else []
    bingo_coupon_id = _bingo_coupon_id(db, verification.run_id) if matched else None

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
        "earned_bingo_stamp_ids": bingo_stamp_ids,
        "earned_bingo_coupon_id": bingo_coupon_id,
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
        return _to_out(db, existing, user_id)

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

    return _to_out(db, record, user_id)


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

    return _to_out(db, record, user_id)
