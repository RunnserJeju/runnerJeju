"""운영자 전용 공지 API — 작성/목록/수정/삭제 + 배너 이미지. 공개 조회는 app.routers.notices에 있다.

공개 GET /notices는 지금 노출 중인 공지만 보여줘서 운영자가 예약(미래)·만료 공지를
관리할 수 없다. 그래서 전체를 보는 GET /admin/notices를 따로 둔다(코스의
GET /admin/courses와 같은 이유).

배너 이미지는 공지의 한 필드(image_url)다. 텍스트 폼(JSON)과 파일 처리(multipart)를
섞지 않으려고 코스 썸네일처럼 PUT/DELETE /notices/{id}/image로 분리했다.
"""

import uuid

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from sqlalchemy import select
from sqlalchemy.orm import Session

from app import storage
from app.db import get_db
from app.models import Notice
from app.schemas import NoticeCreate, NoticeOut, NoticeUpdate

router = APIRouter(tags=["notices"])

# 폰 원본 사진이 올라올 수 있어 코스 썸네일과 같은 8MB.
MAX_IMAGE_BYTES = 8 * 1024 * 1024

# 값은 Storage 오브젝트 확장자로도 쓰인다.
_ALLOWED_IMAGE_TYPES = {
    "image/jpeg": "jpg",
    "image/png": "png",
    "image/webp": "webp",
}


def _load_notice_or_404(db: Session, notice_id: uuid.UUID) -> Notice:
    notice = db.get(Notice, notice_id)
    if notice is None:
        raise HTTPException(status_code=404, detail="공지를 찾을 수 없어요.")
    return notice


@router.get("/notices", response_model=list[NoticeOut])
def list_all_notices(db: Session = Depends(get_db)):
    """공지 전체 목록(예약·만료 포함). (관리자 전용 — 라우터 레벨에서 강제)

    노출 기간과 무관하게 다 내려준다 — 운영자는 아직 시작 안 한 공지나 끝난 공지도
    보고 고쳐야 하기 때문이다.
    """
    return list(
        db.execute(select(Notice).order_by(Notice.created_at.desc())).scalars()
    )


@router.post("/notices", response_model=NoticeOut, status_code=201)
def create_notice(
    payload: NoticeCreate,
    db: Session = Depends(get_db),
):
    """공지를 등록한다. (관리자 전용 — 라우터 레벨에서 강제)"""
    notice = Notice(
        title=payload.title,
        body=payload.body,
        starts_at=payload.starts_at,
        ends_at=payload.ends_at,
    )

    db.add(notice)
    db.commit()
    db.refresh(notice)

    return notice


@router.patch("/notices/{notice_id}", response_model=NoticeOut)
def update_notice(
    notice_id: uuid.UUID,
    payload: NoticeUpdate,
    db: Session = Depends(get_db),
):
    """공지를 수정한다(전체 교체). (관리자 전용 — 라우터 레벨에서 강제)"""
    notice = _load_notice_or_404(db, notice_id)

    notice.title = payload.title
    notice.body = payload.body
    notice.starts_at = payload.starts_at
    notice.ends_at = payload.ends_at

    db.commit()
    db.refresh(notice)

    return notice


@router.delete("/notices/{notice_id}", status_code=204)
def delete_notice(
    notice_id: uuid.UUID,
    db: Session = Depends(get_db),
):
    """공지를 삭제한다. (관리자 전용 — 라우터 레벨에서 강제) 배너 이미지 파일도 함께 지운다(실패해도 무시)."""
    notice = _load_notice_or_404(db, notice_id)
    image_url = notice.image_url
    db.delete(notice)
    db.commit()
    if image_url:
        storage.delete_image(image_url, bucket=storage.SUPABASE_STORAGE_BUCKET)


@router.put("/notices/{notice_id}/image", response_model=NoticeOut)
def set_notice_image(
    notice_id: uuid.UUID,
    file: UploadFile = File(..., description="배너 이미지 (jpg/png/webp)"),
    db: Session = Depends(get_db),
):
    """공지 배너 이미지를 올린다(교체 포함). (관리자 전용 — 라우터 레벨에서 강제)

    올리면 앱 홈 상단 캐러셀에 실린다. 교체 시 옛 오브젝트는 새로 올린 뒤 지운다 —
    Storage가 매번 새 경로에 저장해 옛 파일이 고아로 남기 때문(코스 썸네일과 동일).
    """
    notice = _load_notice_or_404(db, notice_id)

    extension = _ALLOWED_IMAGE_TYPES.get(file.content_type or "")
    if extension is None:
        raise HTTPException(status_code=422, detail="jpg/png/webp 이미지만 올릴 수 있어요.")

    content = file.file.read(MAX_IMAGE_BYTES + 1)
    if len(content) > MAX_IMAGE_BYTES:
        raise HTTPException(
            status_code=413,
            detail=f"이미지가 너무 커요. {MAX_IMAGE_BYTES // (1024 * 1024)}MB 이하여야 해요.",
        )
    if not content:
        raise HTTPException(status_code=422, detail="빈 파일이에요.")

    try:
        new_url = storage.upload_image(
            content,
            content_type=file.content_type,
            extension=extension,
            bucket=storage.SUPABASE_STORAGE_BUCKET,
        )
    except storage.StorageUploadError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    # 업로드가 성공한 뒤에야 옛 것을 지운다 — 실패하면 옛 이미지가 그대로 살아 있게.
    old_url = notice.image_url
    notice.image_url = new_url
    db.commit()
    db.refresh(notice)

    if old_url:
        storage.delete_image(old_url, bucket=storage.SUPABASE_STORAGE_BUCKET)

    return notice


@router.delete("/notices/{notice_id}/image", response_model=NoticeOut)
def delete_notice_image(
    notice_id: uuid.UUID,
    db: Session = Depends(get_db),
):
    """공지 배너 이미지를 뗀다(텍스트 공지로 돌아간다). 이미 없으면 no-op.

    (관리자 전용 — 라우터 레벨에서 강제) Storage 파일도 지우되 실패는 무시한다.
    """
    notice = _load_notice_or_404(db, notice_id)

    old_url = notice.image_url
    if old_url:
        notice.image_url = None
        db.commit()
        db.refresh(notice)
        storage.delete_image(old_url, bucket=storage.SUPABASE_STORAGE_BUCKET)

    return notice
