"""운영자 전용 쿠폰 API — 제작/목록/상세/수정/삭제 + 지급 + 발급 현황.

쿠폰 템플릿(coupons)을 만들고 유저에게 발급(user_coupons)한다. 삭제는 발급분까지
FK ON DELETE CASCADE로 함께 지운다(운영 웹이 "진짜 삭제?"를 확인). 발급 현황은
누구에게 발급됐고 사용했는지를 회원 닉네임까지 붙여 보여준다.

이용완료(사용)는 유저 앱(app/routers/coupons.py의 /me/coupons)에서 처리한다 —
여기(운영자)는 제작·지급·현황 조회까지다.
"""

import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.db import get_db
from app.models import Coupon, User, UserCoupon
from app.schemas import (
    CouponCreate,
    CouponOut,
    CouponUpdate,
    IssuedCouponOut,
    IssuedListOut,
    IssueRequest,
    IssueResult,
)

router = APIRouter(tags=["coupons"])


def _load_coupon_or_404(db: Session, coupon_id: uuid.UUID) -> Coupon:
    coupon = db.get(Coupon, coupon_id)
    if coupon is None:
        raise HTTPException(status_code=404, detail="쿠폰을 찾을 수 없어요.")
    return coupon


def _effective_status(
    used_at: datetime | None, valid_until: datetime | None, now: datetime
) -> str:
    """발급 쿠폰의 유효 상태. used_at·valid_until에서 계산한다(저장하지 않음)."""
    if used_at is not None:
        return "used"
    if valid_until is not None and valid_until < now:
        return "expired"
    return "available"


def _issued_used_counts(
    db: Session, coupon_ids: list[uuid.UUID]
) -> tuple[dict[uuid.UUID, int], dict[uuid.UUID, int]]:
    """쿠폰별 발급 수/사용 수를 한 번에 조회한다(목록에서 N+1을 피하려고)."""
    if not coupon_ids:
        return {}, {}

    issued_rows = db.execute(
        select(UserCoupon.coupon_id, func.count(UserCoupon.id))
        .where(UserCoupon.coupon_id.in_(coupon_ids))
        .group_by(UserCoupon.coupon_id)
    ).all()
    used_rows = db.execute(
        select(UserCoupon.coupon_id, func.count(UserCoupon.id))
        .where(
            UserCoupon.coupon_id.in_(coupon_ids),
            UserCoupon.used_at.isnot(None),
        )
        .group_by(UserCoupon.coupon_id)
    ).all()

    return (
        {cid: c for cid, c in issued_rows},
        {cid: c for cid, c in used_rows},
    )


def _to_out(coupon: Coupon, issued_count: int, used_count: int) -> dict:
    return {
        "id": coupon.id,
        "name": coupon.name,
        "description": coupon.description,
        "benefit": coupon.benefit,
        "valid_until": coupon.valid_until,
        "created_at": coupon.created_at,
        "issued_count": issued_count,
        "used_count": used_count,
    }


@router.post("/coupons", response_model=CouponOut, status_code=201)
def create_coupon(payload: CouponCreate, db: Session = Depends(get_db)):
    """쿠폰을 제작한다. (관리자 전용 — 라우터 레벨에서 강제)"""
    coupon = Coupon(
        name=payload.name,
        benefit=payload.benefit,
        description=payload.description,
        valid_until=payload.valid_until,
    )
    db.add(coupon)
    db.commit()
    db.refresh(coupon)
    return _to_out(coupon, 0, 0)


@router.get("/coupons", response_model=list[CouponOut])
def list_coupons(db: Session = Depends(get_db)):
    """쿠폰 전체 목록(최신순) + 발급/사용 수."""
    coupons = list(
        db.execute(select(Coupon).order_by(Coupon.created_at.desc())).scalars()
    )
    issued, used = _issued_used_counts(db, [c.id for c in coupons])
    return [_to_out(c, issued.get(c.id, 0), used.get(c.id, 0)) for c in coupons]


@router.get("/coupons/{coupon_id}", response_model=CouponOut)
def get_coupon(coupon_id: uuid.UUID, db: Session = Depends(get_db)):
    """쿠폰 상세 + 발급/사용 수."""
    coupon = _load_coupon_or_404(db, coupon_id)
    issued, used = _issued_used_counts(db, [coupon.id])
    return _to_out(coupon, issued.get(coupon.id, 0), used.get(coupon.id, 0))


@router.patch("/coupons/{coupon_id}", response_model=CouponOut)
def update_coupon(
    coupon_id: uuid.UUID, payload: CouponUpdate, db: Session = Depends(get_db)
):
    """쿠폰 수정(전체 교체). 발급분은 라이브 참조라 즉시 반영된다."""
    coupon = _load_coupon_or_404(db, coupon_id)
    coupon.name = payload.name
    coupon.benefit = payload.benefit
    coupon.description = payload.description
    coupon.valid_until = payload.valid_until
    db.commit()
    db.refresh(coupon)
    issued, used = _issued_used_counts(db, [coupon.id])
    return _to_out(coupon, issued.get(coupon.id, 0), used.get(coupon.id, 0))


@router.delete("/coupons/{coupon_id}", status_code=204)
def delete_coupon(coupon_id: uuid.UUID, db: Session = Depends(get_db)):
    """쿠폰을 삭제한다. 발급분·사용기록은 FK ON DELETE CASCADE로 함께 지워진다
    ("이미 발급된 쿠폰인데 진짜 삭제?" 확인은 운영 웹이 맡는다)."""
    coupon = _load_coupon_or_404(db, coupon_id)
    db.delete(coupon)
    db.commit()


@router.post("/coupons/{coupon_id}/issue", response_model=IssueResult, status_code=201)
def issue_coupon(
    coupon_id: uuid.UUID, payload: IssueRequest, db: Session = Depends(get_db)
):
    """지정한 회원들에게 쿠폰을 대량 발급한다.

    존재하는 비탈퇴 회원에게만 발급하고, 실제 발급된 수를 돌려준다. 입력 중복은 무시.
    같은 쿠폰을 같은 사람에게 여러 번(다른 호출로) 발급하는 건 허용한다(각각 한 장).
    """
    _load_coupon_or_404(db, coupon_id)

    unique_ids = set(payload.user_ids)
    valid_ids = set(
        db.execute(
            select(User.id).where(
                User.id.in_(unique_ids), User.deleted_at.is_(None)
            )
        ).scalars()
    )
    for uid in valid_ids:
        db.add(UserCoupon(coupon_id=coupon_id, user_id=str(uid)))
    db.commit()
    return {"issued": len(valid_ids)}


@router.get("/coupons/{coupon_id}/issued", response_model=IssuedListOut)
def list_issued(
    coupon_id: uuid.UUID,
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    db: Session = Depends(get_db),
):
    """이 쿠폰이 누구에게 발급됐는지 + 사용 여부. 회원 닉네임까지 붙인다.

    닉네임은 이 페이지 발급분의 user_id들만 배치로 조회해 붙인다(N+1 없음). 탈퇴/닉네임
    미설정이면 null. 발급이 많아질 수 있어 offset 페이지네이션.
    """
    coupon = _load_coupon_or_404(db, coupon_id)

    total = db.scalar(
        select(func.count())
        .select_from(UserCoupon)
        .where(UserCoupon.coupon_id == coupon_id)
    )
    rows = list(
        db.execute(
            select(UserCoupon)
            .where(UserCoupon.coupon_id == coupon_id)
            .order_by(UserCoupon.issued_at.desc(), UserCoupon.id.desc())
            .limit(limit)
            .offset(offset)
        ).scalars()
    )

    # user_id(문자열)는 str(users.id)라 UUID로 되돌려 users를 배치 조회한다(캐스트 불필요).
    user_ids = [uuid.UUID(uc.user_id) for uc in rows]
    nickname = {}
    if user_ids:
        nickname = {
            uid: nick
            for uid, nick in db.execute(
                select(User.id, User.nickname).where(User.id.in_(user_ids))
            ).all()
        }

    now = datetime.now(timezone.utc)
    items = [
        {
            "id": uc.id,
            "user_id": uuid.UUID(uc.user_id),
            "nickname": nickname.get(uuid.UUID(uc.user_id)),
            "issued_at": uc.issued_at,
            "used_at": uc.used_at,
            "status": _effective_status(uc.used_at, coupon.valid_until, now),
        }
        for uc in rows
    ]
    return {"total": total, "items": items}
