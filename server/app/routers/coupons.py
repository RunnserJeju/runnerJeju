"""앱(공개) 쿠폰 API — 내 쿠폰 목록 + 사용(이용완료).

유저가 발급받은 쿠폰을 보고, "사용" 버튼으로 이용완료 처리한다. 혜택·유효기간은
템플릿(coupons)을 라이브 참조한다. 운영자 쪽 제작/지급/현황은 app/admin/coupons.py.
"""

import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select, update
from sqlalchemy.orm import Session

from app.db import get_db
from app.deps import current_user_id
from app.models import Coupon, UserCoupon
from app.schemas import MyCouponOut

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


@router.get("/me/coupons", response_model=list[MyCouponOut])
def my_coupons(
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
):
    """내 쿠폰 목록(최신순). 혜택·유효기간은 템플릿을 단일 조인으로 라이브 참조한다
    (스탬프 도안처럼, N+1 없음)."""
    rows = db.execute(
        select(
            UserCoupon.id,
            UserCoupon.issued_at,
            UserCoupon.used_at,
            Coupon.name,
            Coupon.description,
            Coupon.benefit,
            Coupon.valid_until,
        )
        .join(Coupon, Coupon.id == UserCoupon.coupon_id)
        .where(UserCoupon.user_id == user_id)
        .order_by(UserCoupon.issued_at.desc())
    ).all()

    now = datetime.now(timezone.utc)
    return [
        {
            "id": r.id,
            "name": r.name,
            "description": r.description,
            "benefit": r.benefit,
            "issued_at": r.issued_at,
            "used_at": r.used_at,
            "valid_until": r.valid_until,
            "status": _effective_status(r.used_at, r.valid_until, now),
        }
        for r in rows
    ]


@router.post("/me/coupons/{user_coupon_id}/use", response_model=MyCouponOut)
def use_coupon(
    user_coupon_id: uuid.UUID,
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
):
    """내 쿠폰 한 장을 사용(이용완료) 처리한다.

    동시에 두 번 눌러도 한 번만 처리되도록, used_at이 아직 비어 있을 때만 채우는
    조건부 UPDATE로 원자 처리한다(영향 행 0 → 이미 사용/남의 것 → 409).
    """
    uc = db.get(UserCoupon, user_coupon_id)
    if uc is None or uc.user_id != user_id:
        raise HTTPException(status_code=404, detail="쿠폰을 찾을 수 없어요.")
    if uc.used_at is not None:
        raise HTTPException(status_code=409, detail="이미 사용한 쿠폰이에요.")

    coupon = db.get(Coupon, uc.coupon_id)
    if coupon is None:
        # 사용 직전 운영자가 템플릿을 삭제(cascade)한 경우 — 쿠폰이 사라진 것으로 본다.
        raise HTTPException(status_code=404, detail="쿠폰을 찾을 수 없어요.")
    now = datetime.now(timezone.utc)
    if coupon.valid_until is not None and coupon.valid_until < now:
        raise HTTPException(status_code=409, detail="유효기간이 지난 쿠폰이에요.")

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
    }

    # 중복 사용 방지(동시성): used_at이 아직 비어 있을 때만 채운다.
    result = db.execute(
        update(UserCoupon)
        .where(UserCoupon.id == user_coupon_id, UserCoupon.used_at.is_(None))
        .values(used_at=now)
    )
    if result.rowcount == 0:
        raise HTTPException(status_code=409, detail="이미 사용한 쿠폰이에요.")
    db.commit()

    return response
