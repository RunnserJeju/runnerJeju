"""운영자 전용 협력업체 API — 목록/등록/수정/삭제.

업체는 여기서 한 번 등록하고, 코스 등록/수정 폼(admin/courses.py)에서 id로 골라
연결한다(course_partners). 앱에는 따로 내려가지 않고 코스 응답에 실려 간다.
"""

import uuid

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app import storage
from app.admin.images import MAX_EXTRA_IMAGES, read_image_or_raise
from app.db import get_db
from app.models import CoursePartner, Partner, UserCoupon
from app.schemas import PartnerImagesUpdate, PartnerOut, PartnerPayload

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


def _coupon_used_counts(db: Session, partner_ids: list[uuid.UUID]) -> dict[uuid.UUID, int]:
    """업체별 쿠폰 사용 수(업체 이용률)."""
    if not partner_ids:
        return {}
    rows = db.execute(
        select(UserCoupon.used_partner_id, func.count())
        .where(UserCoupon.used_partner_id.in_(partner_ids))
        .group_by(UserCoupon.used_partner_id)
    ).all()
    return {partner_id: count for partner_id, count in rows}


def _to_out(partner: Partner, course_count: int, coupon_used_count: int = 0) -> PartnerOut:
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
        thumbnail_url=partner.thumbnail_url,
        image_urls=list(partner.image_urls or []),
        course_count=course_count,
        coupon_used_count=coupon_used_count,
        coupon_pin=partner.coupon_pin,
        created_at=partner.created_at,
        updated_at=partner.updated_at,
    )


def _check_pin_free(
    db: Session, pin: str | None, partner_id: uuid.UUID | None = None
) -> None:
    """쿠폰 번호는 업체마다 달라야 한다(겹치면 어느 업체에서 썼는지 못 가린다)."""
    if pin is None:
        return
    query = select(Partner.name).where(Partner.coupon_pin == pin)
    if partner_id is not None:
        query = query.where(Partner.id != partner_id)
    taken = db.execute(query).scalar()
    if taken is not None:
        raise HTTPException(
            status_code=409, detail=f"'{taken}'에서 이미 쓰는 쿠폰 번호예요."
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
    partner.coupon_pin = payload.coupon_pin
    partner.detail = payload.detail


@router.get("/partners", response_model=list[PartnerOut])
def list_partners(db: Session = Depends(get_db)):
    """협력업체 전체 목록(이름순). (관리자 전용 — 라우터 레벨에서 강제)"""
    partners = list(db.execute(select(Partner).order_by(Partner.name)).scalars())
    ids = [partner.id for partner in partners]
    counts = _course_counts(db, ids)
    used = _coupon_used_counts(db, ids)
    return [
        _to_out(partner, counts.get(partner.id, 0), used.get(partner.id, 0))
        for partner in partners
    ]


@router.post("/partners", response_model=PartnerOut, status_code=201)
def create_partner(payload: PartnerPayload, db: Session = Depends(get_db)):
    """협력업체를 등록한다. (관리자 전용 — 라우터 레벨에서 강제)"""
    _check_pin_free(db, payload.coupon_pin)
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
    _check_pin_free(db, payload.coupon_pin, partner.id)
    _apply(partner, payload)

    db.commit()
    db.refresh(partner)

    return _to_out(partner, _course_counts(db, [partner.id]).get(partner.id, 0))


@router.delete("/partners/{partner_id}", status_code=204)
def delete_partner(partner_id: uuid.UUID, db: Session = Depends(get_db)):
    """협력업체를 삭제한다. 코스 연결은 FK CASCADE로 함께 지워지고, 이미지 파일도 지운다.
    (관리자 전용 — 라우터 레벨에서 강제)"""
    partner = _load_partner_or_404(db, partner_id)
    urls = [partner.thumbnail_url, *(partner.image_urls or [])]
    db.delete(partner)
    db.commit()
    for url in urls:
        if url:
            storage.delete_image(url, bucket=storage.SUPABASE_PARTNER_BUCKET)


# --- 썸네일·추가 이미지 (코스와 같은 구조: admin/courses.py) -------------------------


def _out_for(db: Session, partner: Partner) -> PartnerOut:
    return _to_out(
        partner,
        _course_counts(db, [partner.id]).get(partner.id, 0),
        _coupon_used_counts(db, [partner.id]).get(partner.id, 0),
    )


def _upload(file: UploadFile) -> str:
    content, extension = read_image_or_raise(file)
    try:
        storage.ensure_public_bucket(storage.SUPABASE_PARTNER_BUCKET)
        return storage.upload_image(
            content,
            content_type=file.content_type,
            extension=extension,
            bucket=storage.SUPABASE_PARTNER_BUCKET,
        )
    except storage.StorageUploadError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc


@router.put("/partners/{partner_id}/thumbnail", response_model=PartnerOut)
def set_partner_thumbnail(
    partner_id: uuid.UUID,
    file: UploadFile = File(..., description="썸네일 이미지 (jpg/png/webp)"),
    db: Session = Depends(get_db),
):
    """썸네일을 올린다(교체 포함). 옛 파일은 지운다. (관리자 전용)"""
    partner = _load_partner_or_404(db, partner_id)
    new_url = _upload(file)
    old_url = partner.thumbnail_url
    partner.thumbnail_url = new_url
    db.commit()
    db.refresh(partner)
    if old_url:
        storage.delete_image(old_url, bucket=storage.SUPABASE_PARTNER_BUCKET)
    return _out_for(db, partner)


@router.delete("/partners/{partner_id}/thumbnail", response_model=PartnerOut)
def delete_partner_thumbnail(partner_id: uuid.UUID, db: Session = Depends(get_db)):
    """썸네일을 뗀다. 파일도 지운다. (관리자 전용)"""
    partner = _load_partner_or_404(db, partner_id)
    old_url = partner.thumbnail_url
    if old_url:
        partner.thumbnail_url = None
        db.commit()
        db.refresh(partner)
        storage.delete_image(old_url, bucket=storage.SUPABASE_PARTNER_BUCKET)
    return _out_for(db, partner)


@router.post("/partners/{partner_id}/images", response_model=PartnerOut)
def add_partner_image(
    partner_id: uuid.UUID,
    file: UploadFile = File(..., description="추가 이미지 (jpg/png/webp)"),
    db: Session = Depends(get_db),
):
    """상세 갤러리 이미지를 맨 뒤에 하나 붙인다. (관리자 전용)"""
    partner = _load_partner_or_404(db, partner_id)
    if len(partner.image_urls or []) >= MAX_EXTRA_IMAGES:
        raise HTTPException(
            status_code=422, detail=f"이미지는 {MAX_EXTRA_IMAGES}장까지 올릴 수 있어요."
        )
    url = _upload(file)
    # JSONB 목록은 새 리스트를 대입해야 변경으로 잡힌다.
    partner.image_urls = [*(partner.image_urls or []), url]
    db.commit()
    db.refresh(partner)
    return _out_for(db, partner)


@router.put("/partners/{partner_id}/images", response_model=PartnerOut)
def set_partner_images(
    partner_id: uuid.UUID,
    payload: PartnerImagesUpdate,
    db: Session = Depends(get_db),
):
    """갤러리 이미지 순서를 바꾸거나 뺀다. 지금 있는 URL로만. 빠진 것은 파일도 지운다. (관리자 전용)"""
    partner = _load_partner_or_404(db, partner_id)
    current = list(partner.image_urls or [])
    unknown = [url for url in payload.image_urls if url not in current]
    if unknown:
        raise HTTPException(status_code=422, detail="이 업체에 없는 이미지가 섞여 있어요.")

    removed = [url for url in current if url not in payload.image_urls]
    partner.image_urls = list(payload.image_urls)
    db.commit()
    db.refresh(partner)
    for url in removed:
        storage.delete_image(url, bucket=storage.SUPABASE_PARTNER_BUCKET)
    return _out_for(db, partner)
