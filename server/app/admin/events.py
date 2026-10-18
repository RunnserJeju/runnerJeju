"""운영자 전용 이벤트 API — 목록/등록/수정/삭제 + 이미지. 앱 조회는 app.routers.events에 있다.

이벤트는 그림 한 장(선택)과 게시글이다. 이미지는 공지 배너처럼 텍스트 폼(JSON)과
파일(multipart)을 섞지 않으려고 PUT/DELETE /events/{id}/image로 뗐다.
"""

import uuid

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from sqlalchemy import select
from sqlalchemy.orm import Session

from app import storage
from app.db import get_db
from app.models import Event
from app.schemas import AdminEventOut, EventCreate, EventUpdate

router = APIRouter(tags=["events"])

MAX_IMAGE_BYTES = 8 * 1024 * 1024

_ALLOWED_IMAGE_TYPES = {
    "image/jpeg": "jpg",
    "image/png": "png",
    "image/webp": "webp",
}


def _load_or_404(db: Session, event_id: uuid.UUID) -> Event:
    event = db.get(Event, event_id)
    if event is None:
        raise HTTPException(status_code=404, detail="이벤트를 찾을 수 없어요.")
    return event


def _apply(event: Event, payload: EventCreate) -> None:
    event.title = payload.title
    event.body = payload.body
    event.starts_at = payload.starts_at
    event.ends_at = payload.ends_at
    event.is_active = payload.is_active
    event.sort_order = payload.sort_order


@router.get("/events", response_model=list[AdminEventOut])
def list_events(db: Session = Depends(get_db)):
    """전체 목록(숨김·예약·만료 포함). 정렬은 앱과 같다 — sort_order, 같으면 최신순."""
    return list(
        db.execute(select(Event).order_by(Event.sort_order, Event.created_at.desc())).scalars()
    )


@router.post("/events", response_model=AdminEventOut, status_code=201)
def create_event(payload: EventCreate, db: Session = Depends(get_db)):
    event = Event()
    _apply(event, payload)
    db.add(event)
    db.commit()
    db.refresh(event)
    return event


@router.patch("/events/{event_id}", response_model=AdminEventOut)
def update_event(event_id: uuid.UUID, payload: EventUpdate, db: Session = Depends(get_db)):
    event = _load_or_404(db, event_id)
    _apply(event, payload)
    db.commit()
    db.refresh(event)
    return event


@router.delete("/events/{event_id}", status_code=204)
def delete_event(event_id: uuid.UUID, db: Session = Depends(get_db)):
    """삭제. 이미지 파일도 함께 지운다."""
    event = _load_or_404(db, event_id)
    image_url = event.image_url
    db.delete(event)
    db.commit()
    if image_url:
        storage.delete_image(image_url, bucket=storage.SUPABASE_STORAGE_BUCKET)


@router.put("/events/{event_id}/image", response_model=AdminEventOut)
def set_event_image(
    event_id: uuid.UUID,
    file: UploadFile = File(..., description="이벤트 이미지 (jpg/png/webp)"),
    db: Session = Depends(get_db),
):
    """이미지를 올린다(교체 포함). 옛 파일은 새로 올린 뒤 지운다(공지와 같다)."""
    event = _load_or_404(db, event_id)

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

    old_url = event.image_url
    event.image_url = new_url
    db.commit()
    db.refresh(event)

    if old_url:
        storage.delete_image(old_url, bucket=storage.SUPABASE_STORAGE_BUCKET)
    return event


@router.delete("/events/{event_id}/image", response_model=AdminEventOut)
def delete_event_image(event_id: uuid.UUID, db: Session = Depends(get_db)):
    event = _load_or_404(db, event_id)
    image_url = event.image_url
    if image_url:
        event.image_url = None
        db.commit()
        db.refresh(event)
        storage.delete_image(image_url, bucket=storage.SUPABASE_STORAGE_BUCKET)
    return event
