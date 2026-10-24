"""쿠폰 자동 지급 판정. 지급 조건 종류마다 판정을 여기에 한 번만 쓴다.

쿠폰 템플릿(Coupon)은 trigger_type으로 지급 조건을 갖는다. 행은 마이그레이션이 심고
운영툴은 수정만 하므로, 새 조건이 생기면 여기 판정 함수와 행을 심는 마이그레이션을
같이 더한다(stamp_rules와 같은 방식).

발급은 (쿠폰, 사용자, grant_key) 유일 제약에 기대어 멱등이다. 러닝위크 기간인지는 모른다 —
자동 지급은 app.running_week 진입점을 거쳐서만 불린다.
"""

import uuid
from datetime import datetime, timezone

from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from app.models import Coupon, UserCoupon

MANUAL = "manual"
COURSE_COMPLETE = "course_complete"
# 러닝위크 빙고판 25칸을 다 채움(=25개 코스 완주). '스페셜 쿠폰'.
BINGO_COMPLETE = "bingo_complete"

TRIGGER_TYPES: tuple[str, ...] = (MANUAL, COURSE_COMPLETE, BINGO_COMPLETE)


def course_grant_key(course_id: uuid.UUID) -> str:
    """코스완료 쿠폰의 중복 방지 키. 코스마다 한 장, 같은 코스 재완주는 중복 없음."""
    return f"course:{course_id}"


def bingo_grant_key(week_id: uuid.UUID) -> str:
    """빙고판 완성 쿠폰의 중복 방지 키. 회차마다 한 장."""
    return f"bingo:{week_id}"


def active_coupon(db: Session, trigger_type: str) -> Coupon | None:
    """이 조건으로 지급 중인 쿠폰. 꺼졌거나 유효기간이 지났으면 None. 심은 행이 하나뿐이라
    첫 것을 쓴다."""
    now = datetime.now(timezone.utc)
    return db.execute(
        select(Coupon)
        .where(
            Coupon.trigger_type == trigger_type,
            Coupon.is_active.is_(True),
            or_(Coupon.valid_until.is_(None), Coupon.valid_until > now),
        )
        .order_by(Coupon.created_at)
        .limit(1)
    ).scalar_one_or_none()


def on_course_completed(
    db: Session, user_id: str, course_id: uuid.UUID, run_id: uuid.UUID | None = None
) -> None:
    """완주 인증이 통과했을 때. 코스완료 쿠폰이 켜져 있으면 한 장 준다."""
    coupon = active_coupon(db, COURSE_COMPLETE)
    if coupon is None:
        return
    _grant(db, user_id, coupon, grant_key=course_grant_key(course_id), run_id=run_id)


def on_bingo_completed(
    db: Session, user_id: str, week_id: uuid.UUID, run_id: uuid.UUID | None
) -> None:
    """러닝위크 빙고판을 다 채웠을 때. 스페셜 쿠폰이 켜져 있으면 한 장 준다."""
    coupon = active_coupon(db, BINGO_COMPLETE)
    if coupon is None:
        return
    _grant(db, user_id, coupon, grant_key=bingo_grant_key(week_id), run_id=run_id)


def _grant(
    db: Session, user_id: str, coupon: Coupon, *, grant_key: str, run_id: uuid.UUID | None
) -> None:
    existing = db.execute(
        select(UserCoupon.id).where(
            UserCoupon.coupon_id == coupon.id,
            UserCoupon.user_id == user_id,
            UserCoupon.grant_key == grant_key,
        )
    ).scalar_one_or_none()
    if existing is not None:
        return
    db.add(
        UserCoupon(coupon_id=coupon.id, user_id=user_id, grant_key=grant_key, run_id=run_id)
    )
