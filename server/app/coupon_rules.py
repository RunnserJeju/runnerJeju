"""쿠폰 자동 지급 판정. 지급 조건 종류마다 판정을 여기에 한 번만 쓴다.

쿠폰 템플릿(Coupon)은 trigger_type으로 지급 조건을 갖는다. 행은 마이그레이션이 심고
운영툴은 수정만 하므로, 새 조건이 생기면 여기 판정 함수와 행을 심는 마이그레이션을
같이 더한다(stamp_rules와 같은 방식).

발급은 (쿠폰, 사용자, grant_key) 유일 제약에 기대어 멱등이다.
"""

import uuid

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import Coupon, UserCoupon

MANUAL = "manual"
COURSE_COMPLETE = "course_complete"

TRIGGER_TYPES: tuple[str, ...] = (MANUAL, COURSE_COMPLETE)


def course_grant_key(course_id: uuid.UUID) -> str:
    """코스완료 쿠폰의 중복 방지 키. 코스마다 한 장, 같은 코스 재완주는 중복 없음."""
    return f"course:{course_id}"


def active_coupon(db: Session, trigger_type: str) -> Coupon | None:
    """이 조건으로 지급 중인 쿠폰. 심은 행이 하나뿐이라 첫 것을 쓴다."""
    return db.execute(
        select(Coupon)
        .where(Coupon.trigger_type == trigger_type, Coupon.is_active.is_(True))
        .order_by(Coupon.created_at)
        .limit(1)
    ).scalar_one_or_none()


def on_course_completed(db: Session, user_id: str, course_id: uuid.UUID) -> None:
    """완주 인증이 통과했을 때. 코스완료 쿠폰이 켜져 있으면 한 장 준다."""
    coupon = active_coupon(db, COURSE_COMPLETE)
    if coupon is None:
        return
    _grant(db, user_id, coupon, grant_key=course_grant_key(course_id))


def _grant(db: Session, user_id: str, coupon: Coupon, *, grant_key: str) -> None:
    existing = db.execute(
        select(UserCoupon.id).where(
            UserCoupon.coupon_id == coupon.id,
            UserCoupon.user_id == user_id,
            UserCoupon.grant_key == grant_key,
        )
    ).scalar_one_or_none()
    if existing is not None:
        return
    db.add(UserCoupon(coupon_id=coupon.id, user_id=user_id, grant_key=grant_key))
