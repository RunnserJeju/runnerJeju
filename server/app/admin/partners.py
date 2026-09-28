"""운영자 전용 협력업체 API — 목록/등록/수정/삭제.

업체는 여기서 한 번 등록하고, 코스 등록/수정 폼(admin/courses.py)에서 id로 골라
연결한다(course_partners). 앱에는 따로 내려가지 않고 코스 응답에 실려 간다.
"""

import uuid

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.db import get_db
from app.models import CoursePartner, Partner
from app.schemas import PartnerOut, PartnerPayload

router = APIRouter(tags=["partners"])


def _load_partner_or_404(db: Session, partner_id: uuid.UUID) -> Partner:
    partner = db.get(Partner, partner_id)
    if partner is None:
        raise HTTPException(status_code=404, detail="협력업체를 찾을 수 없어요.")
    return partner


def _course_counts(db: Session, partner_ids: list[uuid.UUID]) -> dict[uuid.UUID, int]:
    """업체별 연결된 코스 수를 한 번에 센다(목록에서 N+1을 피하려고)."""
    if not partner_ids:
        return {}
    rows = db.execute(
        select(CoursePartner.partner_id, func.count())
        .where(CoursePartner.partner_id.in_(partner_ids))
        .group_by(CoursePartner.partner_id)
    ).all()
    return {partner_id: count for partner_id, count in rows}


def _to_out(partner: Partner, course_count: int) -> PartnerOut:
    return PartnerOut(
        id=partner.id,
        name=partner.name,
        address=partner.address,
        lat=partner.lat,
        lng=partner.lng,
        comment=partner.comment,
        instagram=partner.instagram,
        benefit=partner.benefit,
        detail=partner.detail or {},
        course_count=course_count,
        created_at=partner.created_at,
        updated_at=partner.updated_at,
    )


def _apply(partner: Partner, payload: PartnerPayload) -> None:
    # 빈 문자열은 "없음"으로 저장한다 — 폼에서 칸을 지우면 null로 돌아가게.
    partner.name = payload.name.strip()
    partner.address = (payload.address or "").strip() or None
    partner.lat = payload.lat
    partner.lng = payload.lng
    partner.comment = (payload.comment or "").strip() or None
    partner.instagram = (payload.instagram or "").strip() or None
    partner.benefit = (payload.benefit or "").strip() or None
    partner.detail = payload.detail


@router.get("/partners", response_model=list[PartnerOut])
def list_partners(db: Session = Depends(get_db)):
    """협력업체 전체 목록(이름순). (관리자 전용 — 라우터 레벨에서 강제)"""
    partners = list(db.execute(select(Partner).order_by(Partner.name)).scalars())
    counts = _course_counts(db, [partner.id for partner in partners])
    return [_to_out(partner, counts.get(partner.id, 0)) for partner in partners]


@router.post("/partners", response_model=PartnerOut, status_code=201)
def create_partner(payload: PartnerPayload, db: Session = Depends(get_db)):
    """협력업체를 등록한다. (관리자 전용 — 라우터 레벨에서 강제)"""
    partner = Partner()
    _apply(partner, payload)

    db.add(partner)
    db.commit()
    db.refresh(partner)

    return _to_out(partner, 0)


@router.patch("/partners/{partner_id}", response_model=PartnerOut)
def update_partner(
    partner_id: uuid.UUID,
    payload: PartnerPayload,
    db: Session = Depends(get_db),
):
    """협력업체를 수정한다(전체 교체). 연결된 모든 코스에 바로 반영된다.
    (관리자 전용 — 라우터 레벨에서 강제)"""
    partner = _load_partner_or_404(db, partner_id)
    _apply(partner, payload)

    db.commit()
    db.refresh(partner)

    return _to_out(partner, _course_counts(db, [partner.id]).get(partner.id, 0))


@router.delete("/partners/{partner_id}", status_code=204)
def delete_partner(partner_id: uuid.UUID, db: Session = Depends(get_db)):
    """협력업체를 삭제한다. 코스 연결은 FK CASCADE로 함께 지워진다.
    (관리자 전용 — 라우터 레벨에서 강제)"""
    partner = _load_partner_or_404(db, partner_id)
    db.delete(partner)
    db.commit()
