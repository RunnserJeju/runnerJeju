"""운영자 전용 쿠폰 API — 목록/상세/수정 + 지급 + 발급 현황.

쿠폰 템플릿(coupons)은 코드가 심는다(app/coupon_rules.py). 운영툴에서 만들어 봤자
지급 조건을 붙일 수 없어 제작·삭제는 없고, 이름·혜택·설명·유효기간·사용 업체·켜고
끄기만 고친다. 발급 현황은 누구에게 발급됐고 어느 업체에서 썼는지를 보여준다.

이용완료(사용)는 유저 앱(app/routers/coupons.py의 /me/coupons)에서 처리한다.
"""

import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.db import get_db
from app.models import Coupon, CouponPartner, Partner, User, UserCoupon
from app.schemas import (
    CouponOut,
    CouponUpdate,
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
        "trigger_type": coupon.trigger_type,
        "is_active": coupon.is_active,
        "partner_ids": [link.partner_id for link in coupon.partners],
        "created_at": coupon.created_at,
        "issued_count": issued_count,
        "used_count": used_count,
    }


@router.get("/coupons", response_model=list[CouponOut])
def list_coupons(db: Session = Depends(get_db)):
    """쿠폰 전체 목록(심은 순) + 발급/사용 수."""
    coupons = list(
        db.execute(select(Coupon).order_by(Coupon.created_at)).scalars()
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
    """쿠폰 수정(전체 교체). 발급분은 라이브 참조라 즉시 반영된다.

    사용 업체는 실제 있는 업체만 남기고 통째로 바꾼다. 비우면 모든 업체 허용.
    """
    coupon = _load_coupon_or_404(db, coupon_id)

    wanted = list(dict.fromkeys(payload.partner_ids))
    existing = set(
        db.execute(select(Partner.id).where(Partner.id.in_(wanted))).scalars()
    ) if wanted else set()
    missing = [pid for pid in wanted if pid not in existing]
    if missing:
        raise HTTPException(status_code=400, detail="없는 협력업체가 있어요.")

    coupon.name = payload.name.strip()
    coupon.benefit = payload.benefit.strip()
    coupon.description = (payload.description or "").strip() or None
    coupon.valid_until = payload.valid_until
    coupon.is_active = payload.is_active
    # 통째로 갈아끼우지 않고 차이만 반영한다 — 같은 (쿠폰, 업체) PK를 지웠다 다시 넣는
    # flush에 기대지 않으려고.
    current = {link.partner_id: link for link in coupon.partners}
    for pid, link in current.items():
        if pid not in wanted:
            coupon.partners.remove(link)
    for pid in wanted:
        if pid not in current:
            coupon.partners.append(CouponPartner(partner_id=pid))
    db.commit()
    db.refresh(coupon)
    issued, used = _issued_used_counts(db, [coupon.id])
    return _to_out(coupon, issued.get(coupon.id, 0), used.get(coupon.id, 0))


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
    """이 쿠폰이 누구에게 발급됐는지 + 사용 여부·사용 업체. 회원 닉네임까지 붙인다.

    닉네임·업체 이름은 이 페이지 발급분의 id들만 배치로 조회해 붙인다(N+1 없음). 탈퇴/닉네임
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
    partner_ids = {uc.used_partner_id for uc in rows if uc.used_partner_id is not None}
    partner_name = {}
    if partner_ids:
        partner_name = {
            pid: name
            for pid, name in db.execute(
                select(Partner.id, Partner.name).where(Partner.id.in_(partner_ids))
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
            "used_partner_name": partner_name.get(uc.used_partner_id),
            "status": _effective_status(
                uc.used_at, coupon.valid_until, now, uc.expired_at
            ),
        }
        for uc in rows
    ]
    return {"total": total, "items": items}
