"""운영자 전용 경품 지급 처리 — kakao_channel 쿠폰의 발급 목록 + 지급완료 + 추첨 기록.

사용자가 카카오톡 채널로 쿠폰 화면을 캡처해 보내면 운영자가 코드로 찾아 '지급완료'를 누른다.
지급완료는 used_at을 채우는 것이라 앱 쿠폰함도 사용완료로 바뀐다. 조건부 UPDATE 한 문장이라
둘이 동시에 눌러도 한 번만 기록된다.
"""

import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import String, cast, func, or_, select, update
from sqlalchemy.orm import Session

from app import coupon_rules
from app.admin.coupons import _effective_status
from app.db import get_db
from app.models import Coupon, CouponDraw, User, UserCoupon
from app.schemas import CouponDrawListOut, RewardFulfillmentListOut, RewardFulfillmentOut

router = APIRouter(tags=["rewards"])


def _users_named(needle: str):
    """닉네임에 needle이 들어간 회원 id(문자열) 서브쿼리. user_coupons.user_id가 문자열이라 캐스트."""
    return select(cast(User.id, String)).where(User.nickname.ilike(f"%{needle}%"))


def _nicknames(db: Session, user_ids: list[str]) -> dict[str, str | None]:
    if not user_ids:
        return {}
    ids = [uuid.UUID(uid) for uid in set(user_ids)]
    return {
        str(uid): nick
        for uid, nick in db.execute(select(User.id, User.nickname).where(User.id.in_(ids))).all()
    }


def _fulfillment_out(uc: UserCoupon, coupon: Coupon, nickname: str | None, now: datetime) -> dict:
    return {
        "id": uc.id,
        "code": uc.code,
        "user_id": uuid.UUID(uc.user_id),
        "nickname": nickname,
        "coupon_id": coupon.id,
        "coupon_name": coupon.name,
        "benefit": coupon.benefit,
        "lines": coupon_rules.lines_of(coupon),
        "issued_at": uc.issued_at,
        "used_at": uc.used_at,
        "valid_until": coupon.valid_until,
        "status": _effective_status(uc.used_at, coupon.valid_until, now, uc.expired_at),
    }


@router.get("/rewards/fulfillments", response_model=RewardFulfillmentListOut)
def list_fulfillments(
    pending_only: bool = Query(default=True),
    q: str | None = Query(default=None, max_length=100),
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
    db: Session = Depends(get_db),
):
    """경품(kakao_channel) 쿠폰 발급 목록. 기본은 미지급만, q는 쿠폰 코드 또는 닉네임 검색."""
    stmt = (
        select(UserCoupon, Coupon)
        .join(Coupon, Coupon.id == UserCoupon.coupon_id)
        .where(Coupon.redeem_type == coupon_rules.REDEEM_KAKAO_CHANNEL)
    )
    if pending_only:
        stmt = stmt.where(UserCoupon.used_at.is_(None))
    if q:
        needle = q.strip()
        if needle:
            code = coupon_rules.normalize_code(needle)
            by_name = UserCoupon.user_id.in_(_users_named(needle))
            stmt = stmt.where(or_(UserCoupon.code == code, by_name) if code else by_name)
    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    rows = db.execute(
        stmt.order_by(UserCoupon.issued_at.desc(), UserCoupon.id.desc()).limit(limit).offset(offset)
    ).all()
    nickname = _nicknames(db, [uc.user_id for uc, _ in rows])
    now = datetime.now(timezone.utc)
    return {
        "total": total,
        "items": [_fulfillment_out(uc, c, nickname.get(uc.user_id), now) for uc, c in rows],
    }


@router.post("/rewards/fulfillments/{user_coupon_id}/complete", response_model=RewardFulfillmentOut)
def complete_fulfillment(user_coupon_id: uuid.UUID, db: Session = Depends(get_db)):
    """지급완료 처리. used_at이 비어 있고 만료되지 않은 경품 쿠폰만. 둘이 동시에 눌러도 한 번."""
    row = db.execute(
        select(UserCoupon, Coupon)
        .join(Coupon, Coupon.id == UserCoupon.coupon_id)
        .where(UserCoupon.id == user_coupon_id)
    ).first()
    if row is None:
        raise HTTPException(status_code=404, detail="쿠폰을 찾을 수 없어요.")
    uc, coupon = row
    if coupon.redeem_type != coupon_rules.REDEEM_KAKAO_CHANNEL:
        raise HTTPException(status_code=400, detail="경품 쿠폰이 아니에요.")
    now = datetime.now(timezone.utc)
    if uc.expired_at is not None or (coupon.valid_until is not None and coupon.valid_until < now):
        raise HTTPException(status_code=410, detail="수령 기한이 지난 쿠폰이에요. 기한을 먼저 늘려 주세요.")

    result = db.execute(
        update(UserCoupon)
        .where(
            UserCoupon.id == user_coupon_id,
            UserCoupon.used_at.is_(None),
            UserCoupon.expired_at.is_(None),
        )
        .values(used_at=now)
    )
    if result.rowcount == 0:
        raise HTTPException(status_code=409, detail="이미 지급완료 처리된 쿠폰이에요.")
    db.commit()
    db.refresh(uc)
    nickname = _nicknames(db, [uc.user_id]).get(uc.user_id)
    return _fulfillment_out(uc, coupon, nickname, now)


@router.get("/rewards/draws", response_model=CouponDrawListOut)
def list_draws(
    coupon_id: uuid.UUID | None = Query(default=None),
    q: str | None = Query(default=None, max_length=100),
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
    db: Session = Depends(get_db),
):
    """추첨 기록(최신순). 쿠폰별·닉네임으로 좁힐 수 있다. 문의가 오면 왜 못 받았는지 여기서 본다."""
    stmt = (
        select(CouponDraw, Coupon.name, UserCoupon.code)
        .join(Coupon, Coupon.id == CouponDraw.coupon_id)
        .outerjoin(UserCoupon, UserCoupon.id == CouponDraw.user_coupon_id)
    )
    if coupon_id is not None:
        stmt = stmt.where(CouponDraw.coupon_id == coupon_id)
    if q and q.strip():
        stmt = stmt.where(CouponDraw.user_id.in_(_users_named(q.strip())))
    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    rows = db.execute(
        stmt.order_by(CouponDraw.drawn_at.desc(), CouponDraw.id.desc()).limit(limit).offset(offset)
    ).all()
    nickname = _nicknames(db, [d.user_id for d, _, _ in rows])
    return {
        "total": total,
        "items": [
            {
                "id": d.id,
                "coupon_id": d.coupon_id,
                "coupon_name": name,
                "user_id": uuid.UUID(d.user_id),
                "nickname": nickname.get(d.user_id),
                "grant_key": d.grant_key,
                "result": d.result,
                "code": code,
                "drawn_at": d.drawn_at,
            }
            for d, name, code in rows
        ],
    }
