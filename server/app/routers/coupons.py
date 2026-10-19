"""앱(공개) 쿠폰 API — 내 쿠폰 목록/한 장 + 사용(이용완료).

유저가 발급받은 쿠폰을 보고, 업체 직원이 업체 고유 4자리 번호(Partner.coupon_pin)를
입력하면 이용완료 처리한다. 번호로 업체를 찾아 어느 업체에서 썼는지 남긴다(이용률). 혜택·유효기간은
템플릿(coupons)을 라이브 참조한다. 운영자 쪽 수정/지급/현황은 app/admin/coupons.py.

만료: 유효기간이 지난 쿠폰은 목록에서 빼고 expired_at을 남긴다. 사용하려 하면 410으로
알리고 역시 expired_at을 남긴다 — 앱은 410을 받으면 그 쿠폰을 목록에서 치운다.
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
    used_at: datetime | None,
    valid_until: datetime | None,
    now: datetime,
    expired_at: datetime | None = None,
) -> str:
    """발급 쿠폰의 유효 상태. 사용이 만료보다 우선(이미 썼으니)."""
    if used_at is not None:
        return "used"
    if expired_at is not None or (valid_until is not None and valid_until < now):
        return "expired"
    return "available"


def _mark_expired(db: Session, user_id: str, now: datetime) -> None:
    """유효기간이 지난 내 미사용 쿠폰에 expired_at을 남긴다. 커밋은 호출한 쪽이 한다."""
    stale = (
        select(UserCoupon.id)
        .join(Coupon, Coupon.id == UserCoupon.coupon_id)
        .where(
            UserCoupon.user_id == user_id,
            UserCoupon.used_at.is_(None),
            UserCoupon.expired_at.is_(None),
            Coupon.valid_until.isnot(None),
            Coupon.valid_until < now,
        )
    )
    db.execute(
        update(UserCoupon).where(UserCoupon.id.in_(stale)).values(expired_at=now)
    )


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
            "status": _effective_status(
                uc.used_at, coupon.valid_until, now, uc.expired_at
            ),
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
    """내 쿠폰 목록(최신순). 만료된 쿠폰은 expired_at을 남기고 목록에서 뺀다.
    혜택·유효기간은 템플릿을 단일 조인으로 라이브 참조한다."""
    now = datetime.now(timezone.utc)
    _mark_expired(db, user_id, now)
    db.commit()

    rows = db.execute(
        select(UserCoupon, Coupon)
        .join(Coupon, Coupon.id == UserCoupon.coupon_id)
        .where(UserCoupon.user_id == user_id, UserCoupon.expired_at.is_(None))
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
    """내 쿠폰 한 장을 입력한 번호의 업체에서 사용(이용완료) 처리한다.

    번호에 맞는 업체가 없으면 400. 쿠폰에 업체 제한이 있으면 그 안의 업체만 받는다. 동시에 두 번 눌러도 한 번만
    처리되도록, used_at이 아직 비어 있을 때만 채우는 조건부 UPDATE로 원자 처리한다
    (영향 행 0 → 이미 사용 → 409). 유효기간이 지났으면 expired_at을 남기고 410.
    """
    uc, coupon = _mine_or_404(db, user_coupon_id, user_id)
    if uc.used_at is not None:
        raise HTTPException(status_code=409, detail="이미 사용한 쿠폰이에요.")

    now = datetime.now(timezone.utc)
    if uc.expired_at is not None or (
        coupon.valid_until is not None and coupon.valid_until < now
    ):
        if uc.expired_at is None:
            db.execute(
                update(UserCoupon)
                .where(UserCoupon.id == user_coupon_id, UserCoupon.used_at.is_(None))
                .values(expired_at=now)
            )
            db.commit()
        raise HTTPException(status_code=410, detail="유효기간이 지난 쿠폰이에요.")

    partner = db.execute(
        select(Partner).where(Partner.coupon_pin == payload.pin)
    ).scalar_one_or_none()
    if partner is None:
        raise HTTPException(status_code=400, detail="번호가 맞지 않아요. 다시 확인해 주세요.")
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
