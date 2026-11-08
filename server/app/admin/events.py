"""운영자 전용 이벤트 API — 목록/등록/수정/삭제 + 이미지. 앱 조회는 app.routers.events에 있다.

이벤트는 그림 한 장(선택)과 게시글이다. 이미지는 공지 배너처럼 텍스트 폼(JSON)과
파일(multipart)을 섞지 않으려고 PUT/DELETE /events/{id}/image로 뗐다.
"""

import uuid

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from sqlalchemy import distinct, func, select
from sqlalchemy.orm import Session

from app import storage, user_log
from app.db import get_db
from app.models import Event, UserLog
from app.schemas import (
    AdminEventOut,
    EventCreate,
    EventOrder,
    EventUpdate,
    EventViewCount,
)

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
    event.visibility = payload.visibility


@router.get("/events", response_model=list[AdminEventOut])
def list_events(db: Session = Depends(get_db)):
    """전체 목록(숨김·예약·만료 포함). 정렬은 앱과 같다 — sort_order, 같으면 최신순."""
    return list(
        db.execute(select(Event).order_by(Event.sort_order, Event.created_at.desc())).scalars()
    )


@router.get("/events/views", response_model=list[EventViewCount])
def event_view_counts(db: Session = Depends(get_db)):
    """이벤트별 상세 조회 수(전체 기간). 앱이 상세를 열 때 남기는 event_detail_open을 센다.

    조회한 적 없는 이벤트는 빠진다(0으로 보면 된다). 로그는 앱 업데이트 뒤부터 쌓인다.
    """
    event_id = UserLog.detail["event_id"].astext
    # GROUP BY는 식이 아니라 결과 열 이름으로 묶는다. 식을 그대로 두면 키('event_id')가
    # SELECT와 GROUP BY에 따로 바인딩돼 Postgres가 다른 식으로 본다(metrics/sources 참고).
    rows = db.execute(
        select(
            event_id.label("viewed_event_id"),
            func.count(),
            func.count(distinct(UserLog.user_id)),
        )
        .where(UserLog.log_name == user_log.EVENT_DETAIL_OPEN, event_id.is_not(None))
        .group_by("viewed_event_id")
    ).all()

    counts = []
    for raw_id, views, viewers in rows:
        try:
            parsed = uuid.UUID(raw_id)
        except ValueError:
            continue  # 앱이 이상한 값을 보냈다. 세지 않는다.
        counts.append({"event_id": parsed, "views": views, "viewers": viewers})
    return counts


@router.put("/events/order", response_model=list[AdminEventOut])
def reorder_events(payload: EventOrder, db: Session = Depends(get_db)):
    """이벤트 순서를 통째로 다시 매긴다. 공지 순서(PUT /admin/notices/order)와 같은 규칙 —
    전부를 받고, 그새 목록이 바뀌었으면 409."""
    ids = payload.ids
    if len(set(ids)) != len(ids):
        raise HTTPException(status_code=422, detail="같은 이벤트가 두 번 들어 있어요.")

    events = {event.id: event for event in db.execute(select(Event)).scalars()}
    if set(ids) != set(events):
        raise HTTPException(
            status_code=409,
            detail="그새 이벤트 목록이 바뀌었어요. 새로고침한 뒤 다시 정해 주세요.",
        )

    for order, event_id in enumerate(ids):
        events[event_id].sort_order = order
    db.commit()

    return [events[event_id] for event_id in ids]


@router.post("/events", response_model=AdminEventOut, status_code=201)
def create_event(payload: EventCreate, db: Session = Depends(get_db)):
    """이벤트를 등록한다. 맨 앞에 붙는다."""
    # 지금 맨 앞보다 하나 앞. 음수가 돼도 상관없다 — 순서를 저장하면 0부터 다시 매긴다.
    first = db.execute(select(func.min(Event.sort_order))).scalar()
    event = Event(sort_order=(first if first is not None else 0) - 1)
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
