"""가민·순토 활동 링크로 코스 완주 인증 — POST /courses/{course_id}/external-completions.

러닝 기록(runs)은 만들지 않는다. 링크에서 받은 경로를 앱 러닝과 같은 기준으로 판정하고,
통과하면 완주 뒤 보상 흐름(스탬프 → 러닝위크 스탬프 → 쿠폰 추첨 → 빙고)만 태운다.
시도는 성공·실패 모두 external_completions에 한 줄씩 남는다.
"""

import logging
import uuid

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app import completions, external_run, running_week, stamp_rules
from app import verification as verification_logic
from app.db import get_db
from app.deps import current_user_id
from app.models import CouponDraw, Course, ExternalCompletion, Stamp, UserCoupon
from app.routers.verifications import NO_REWARDS, rewards_out
from app.schemas import ExternalCompletionCreate, ExternalCompletionOut

logger = logging.getLogger(__name__)

router = APIRouter(tags=["external-completions"])

# 앱이 결과 화면을 고르는 코드. detail은 {code, message}로 내려간다.
ALREADY_COMPLETED = "already_completed"
ACTIVITY_USED = "activity_used"


def _conflict(code: str, message: str) -> HTTPException:
    return HTTPException(status_code=409, detail={"code": code, "message": message})


@router.post(
    "/courses/{course_id}/external-completions",
    response_model=ExternalCompletionOut,
    status_code=201,
)
def create_external_completion(
    course_id: uuid.UUID,
    payload: ExternalCompletionCreate,
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
):
    course = db.get(Course, course_id)
    if course is None:
        raise HTTPException(status_code=404, detail="코스를 찾을 수 없어요.")
    ref = external_run.parse_url(payload.url)
    if ref is None:
        raise HTTPException(status_code=422, detail="가민 또는 순토의 활동 링크를 넣어 주세요.")
    if completions.is_completed(db, user_id, course.id):
        raise _conflict(ALREADY_COMPLETED, "이미 완주한 코스예요.")
    if _activity_used(db, ref):
        raise _conflict(ACTIVITY_USED, "이미 사용된 링크예요.")

    record = ExternalCompletion(
        user_id=user_id,
        course_id=course.id,
        source=ref.source,
        activity_id=ref.activity_id,
        url=payload.url.strip()[:500],
    )
    try:
        run = external_run.fetch(ref)
    except external_run.ExternalRunError as e:
        # 가민·순토가 막히거나 형식을 바꾸면 여기로 온다. 운영에서 보이게 남긴다.
        logger.warning("외부 기록 추출 실패 %s %s: %s", ref.source, ref.activity_id, e.message)
        record.status = "failed"
        record.detail = e.message[:500]
        db.add(record)
        db.commit()
        return _to_out(record, NO_REWARDS)

    outcome = verification_logic.verify(
        course_path=verification_logic.to_points(course.path or []), run_path=run.points
    )
    record.status = outcome.status
    record.match_rate = outcome.match_rate
    record.detail = outcome.detail
    record.started_at = run.started_at
    record.distance_meters = run.distance_meters
    record.point_count = len(run.points)
    db.add(record)

    if outcome.status != "matched":
        db.commit()
        return _to_out(record, NO_REWARDS)

    # 러닝이 없어 "이번에 받은 것"을 run_id로 못 찾는다. 지급 전후 차이로 가린다.
    before = _owned(db, user_id)
    stamp_rules.on_course_completed(db, user_id, course.id, None)
    running_week.on_course_completed(db, user_id, course.id, None)
    try:
        db.commit()
    except IntegrityError:
        # 같은 활동이 동시에 두 번 들어왔다(uq_external_completion_activity).
        db.rollback()
        raise _conflict(ACTIVITY_USED, "이미 사용된 링크예요.")
    db.refresh(record)

    stamps, coupons, draws = (now - old for now, old in zip(_owned(db, user_id), before))
    rewards = rewards_out(
        db,
        course.id,
        stamps=Stamp.id.in_(stamps),
        coupons=UserCoupon.id.in_(coupons),
        draws=CouponDraw.id.in_(draws),
    )
    return _to_out(record, rewards)


def _activity_used(db: Session, ref: external_run.ActivityRef) -> bool:
    return (
        db.execute(
            select(ExternalCompletion.id)
            .where(
                ExternalCompletion.source == ref.source,
                ExternalCompletion.activity_id == ref.activity_id,
                ExternalCompletion.status == completions.MATCHED,
            )
            .limit(1)
        ).first()
        is not None
    )


def _owned(db: Session, user_id: str) -> tuple[set[uuid.UUID], set[uuid.UUID], set[uuid.UUID]]:
    """이 사람의 스탬프·쿠폰·추첨 id."""
    return tuple(  # type: ignore[return-value]
        set(db.execute(select(model.id).where(model.user_id == user_id)).scalars())
        for model in (Stamp, UserCoupon, CouponDraw)
    )


def _to_out(record: ExternalCompletion, rewards: dict) -> dict:
    return {
        "id": record.id,
        "course_id": record.course_id,
        "source": record.source,
        "status": record.status,
        "match_rate": record.match_rate,
        "detail": record.detail,
        "started_at": record.started_at,
        "distance_meters": record.distance_meters,
        **rewards,
    }
