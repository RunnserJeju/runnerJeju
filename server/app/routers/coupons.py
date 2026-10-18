"""앱(공개) 쿠폰 API — 내 쿠폰 목록/한 장 + 사용(이용완료).

유저가 발급받은 쿠폰을 보고, 업체 이름을 검색해 고른 뒤 "사용하기"로 이용완료 처리한다.
업체 코드는 따로 없다 — 어느 업체에서 썼는지만 남겨 이용률에 쓴다. 혜택·유효기간은
템플릿(coupons)을 라이브 참조한다. 운영자 쪽 수정/지급/현황은 app/admin/coupons.py.
"""

import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select, update
from sqlalchemy.orm import Session

from app.db import get_db
from app.deps import current_user_id
from app.models import Coupon, CouponPartner, Partner, UserCoupon
from app.schemas import CouponUseRequest, MyCouponOut

router = APIRouter(tags=["coupons"])


def _effective_status(
    used_at: datetime | None, valid_until: datetime | None, now: datetime
) -> str:
    """발급 쿠폰의 유효 상태. used_at·valid_until에서 계산한다(저장하지 않음)."""
    if used_at is not None:
        return "used"
    if valid_until is not None and valid_until < now:
        return "expired"
    return "available"


def _allowed_partner_ids(
    db: Session, coupon_ids: set[uuid.UUID]
) -> dict[uuid.UUID, list[uuid.UUID]]:
    """쿠폰별 사용 가능 업체. 제한이 없는 쿠폰은 키가 없다."""
    if not coupon_ids:
        return {}
    allowed: dict[uuid.UUID, list[uuid.UUID]] = {}
    for coupon_id, partner_id in db.execute(
        select(CouponPartner.coupon_id, CouponPartner.partner_id).where(
            CouponPartner.coupon_id.in_(coupon_ids)
        )
    ).all():
        allowed.setdefault(coupon_id, []).append(partner_id)
    return allowed


def _partner_names(db: Session, partner_ids: set[uuid.UUID]) -> dict[uuid.UUID, str]:
    if not partner_ids:
        return {}
    return {
        pid: name
        for pid, name in db.execute(
            select(Partner.id, Partner.name).where(Partner.id.in_(partner_ids))
        ).all()
    }


def _rows_to_out(db: Session, rows: list) -> list[dict]:
    """(UserCoupon, Coupon) 행들을 응답으로. 업체 제한·사용 업체 이름은 배치로 붙인다."""
    allowed = _allowed_partner_ids(db, {coupon.id for _, coupon in rows})
    names = _partner_names(
        db, {uc.used_partner_id for uc, _ in rows if uc.used_partner_id is not None}
    )
    now = datetime.now(timezone.utc)
    return [
        {
            "id": uc.id,
            "name": coupon.name,
            "description": coupon.description,
            "benefit": coupon.benefit,
            "issued_at": uc.issued_at,
            "used_at": uc.used_at,
            "valid_until": coupon.valid_until,
            "status": _effective_status(uc.used_at, coupon.valid_until, now),
            "partner_ids": allowed.get(coupon.id),
            "used_partner_name": names.get(uc.used_partner_id),
        }
        for uc, coupon in rows
    ]


def _mine_or_404(db: Session, user_coupon_id: uuid.UUID, user_id: str) -> tuple:
    row = db.execute(
        select(UserCoupon, Coupon)
        .join(Coupon, Coupon.id == UserCoupon.coupon_id)
        .where(UserCoupon.id == user_coupon_id, UserCoupon.user_id == user_id)
    ).first()
    if row is None:
        raise HTTPException(status_code=404, detail="쿠폰을 찾을 수 없어요.")
    return row


@router.get("/me/coupons", response_model=list[MyCouponOut])
def my_coupons(
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
):
    """내 쿠폰 목록(최신순). 혜택·유효기간은 템플릿을 단일 조인으로 라이브 참조한다."""
    rows = db.execute(
        select(UserCoupon, Coupon)
        .join(Coupon, Coupon.id == UserCoupon.coupon_id)
        .where(UserCoupon.user_id == user_id)
        .order_by(UserCoupon.issued_at.desc())
    ).all()
    return _rows_to_out(db, list(rows))


@router.get("/me/coupons/{user_coupon_id}", response_model=MyCouponOut)
def my_coupon(
    user_coupon_id: uuid.UUID,
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
):
    """내 쿠폰 한 장. 완주 직후 획득 연출이 이 값으로 그린다."""
    row = _mine_or_404(db, user_coupon_id, user_id)
    return _rows_to_out(db, [row])[0]


@router.post("/me/coupons/{user_coupon_id}/use", response_model=MyCouponOut)
def use_coupon(
    user_coupon_id: uuid.UUID,
    payload: CouponUseRequest,
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
):
    """내 쿠폰 한 장을 고른 업체에서 사용(이용완료) 처리한다.

    쿠폰에 업체 제한이 있으면 그 안의 업체만 받는다. 동시에 두 번 눌러도 한 번만
    처리되도록, used_at이 아직 비어 있을 때만 채우는 조건부 UPDATE로 원자 처리한다
    (영향 행 0 → 이미 사용 → 409).
    """
    uc, coupon = _mine_or_404(db, user_coupon_id, user_id)
    if uc.used_at is not None:
        raise HTTPException(status_code=409, detail="이미 사용한 쿠폰이에요.")

    now = datetime.now(timezone.utc)
    if coupon.valid_until is not None and coupon.valid_until < now:
        raise HTTPException(status_code=409, detail="유효기간이 지난 쿠폰이에요.")

    partner = db.get(Partner, payload.partner_id)
    if partner is None:
        raise HTTPException(status_code=404, detail="협력업체를 찾을 수 없어요.")
    allowed = _allowed_partner_ids(db, {coupon.id}).get(coupon.id)
    if allowed is not None and partner.id not in allowed:
        raise HTTPException(status_code=400, detail="이 쿠폰을 쓸 수 없는 업체예요.")

    # 응답에 쓸 값을 커밋(=세션 expire) 전에 확보한다.
    response = {
        "id": uc.id,
        "name": coupon.name,
        "description": coupon.description,
        "benefit": coupon.benefit,
        "issued_at": uc.issued_at,
        "used_at": now,
        "valid_until": coupon.valid_until,
        "status": "used",
        "partner_ids": allowed,
        "used_partner_name": partner.name,
    }

    # 중복 사용 방지(동시성): used_at이 아직 비어 있을 때만 채운다.
    result = db.execute(
        update(UserCoupon)
        .where(UserCoupon.id == user_coupon_id, UserCoupon.used_at.is_(None))
        .values(used_at=now, used_partner_id=partner.id)
    )
    if result.rowcount == 0:
        raise HTTPException(status_code=409, detail="이미 사용한 쿠폰이에요.")
    db.commit()

    return response
