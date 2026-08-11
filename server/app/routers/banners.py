import uuid

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from sqlalchemy import select
from sqlalchemy.orm import Session

from app import storage
from app.db import get_db
from app.deps import current_user_id, require_admin
from app.models import Banner
from app.schemas import BannerOut

router = APIRouter(tags=["banners"])

# 배너는 폰 카메라 원본 사진이 올라올 수 있어 GPX(MAX_GPX_BYTES=5MB)보다 여유를 둔다.
MAX_BANNER_IMAGE_BYTES = 8 * 1024 * 1024

# 값은 Supabase Storage 오브젝트 확장자로도 쓰인다.
_ALLOWED_CONTENT_TYPES = {
    "image/jpeg": "jpg",
    "image/png": "png",
    "image/webp": "webp",
}


@router.get("/banners", response_model=list[BannerOut])
def list_banners(
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
):
    """홈 화면에 노출할 배너. 활성 상태만, 지정한 순서대로 내려준다."""
    stmt = (
        select(Banner)
        .where(Banner.is_active.is_(True))
        .order_by(Banner.sort_order, Banner.created_at)
    )
    return list(db.execute(stmt).scalars())


@router.post("/banners", response_model=BannerOut, status_code=201)
def create_banner(
    file: UploadFile = File(..., description="배너 이미지 (jpg/png/webp)"),
    sort_order: int = Form(default=0, description="낮을수록 먼저 보인다"),
    db: Session = Depends(get_db),
    user_id: str = Depends(require_admin),
):
    """배너 이미지를 Storage에 올리고 등록한다. **관리자 전용.**"""
    extension = _ALLOWED_CONTENT_TYPES.get(file.content_type or "")
    if extension is None:
        raise HTTPException(status_code=422, detail="jpg/png/webp 이미지만 올릴 수 있어요.")

    content = file.file.read(MAX_BANNER_IMAGE_BYTES + 1)
    if len(content) > MAX_BANNER_IMAGE_BYTES:
        raise HTTPException(
            status_code=413,
            detail=f"이미지가 너무 커요. {MAX_BANNER_IMAGE_BYTES // (1024 * 1024)}MB 이하여야 해요.",
        )
    if not content:
        raise HTTPException(status_code=422, detail="빈 파일이에요.")

    try:
        image_url = storage.upload_image(
            content, content_type=file.content_type, extension=extension
        )
    except storage.StorageUploadError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    banner = Banner(image_url=image_url, sort_order=sort_order, created_by=user_id)
    db.add(banner)
    db.commit()
    db.refresh(banner)

    return banner


@router.delete("/banners/{banner_id}", status_code=204)
def delete_banner(
    banner_id: uuid.UUID,
    db: Session = Depends(get_db),
    user_id: str = Depends(require_admin),
):
    """배너를 지운다. **관리자 전용.** Storage 파일도 함께 지운다(실패해도 무시)."""
    banner = db.get(Banner, banner_id)
    if banner is None:
        raise HTTPException(status_code=404, detail="배너를 찾을 수 없어요.")

    storage.delete_image(banner.image_url)
    db.delete(banner)
    db.commit()
