"""커뮤니티 이벤트(#70) — 앱용 목록·상세. 운영툴은 app.admin.events에 있다."""

import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import get_db
from app.deps import current_user_id
from app.models import Event
from app.schemas import EventOut

router = APIRouter(tags=["events"])


def is_visible(event: Event, now: datetime) -> bool:
    """공지와 같은 규칙. 꺼져 있거나 노출 기간 밖이면 앱에 안 뜬다."""
    if not event.is_active:
        return False
    if event.starts_at is not None and event.starts_at > now:
        return False
    if event.ends_at is not None and event.ends_at < now:
        return False
    return True


@router.get("/events", response_model=list[EventOut])
def list_events(
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
):
    """지금 노출 중인 이벤트. sort_order 오름차순, 같으면 최신순.

    소량이라 공지처럼 전부 읽어 파이썬에서 거른다.
    """
    now = datetime.now(timezone.utc)
    events = db.execute(
        select(Event).order_by(Event.sort_order, Event.created_at.desc())
    ).scalars()
    return [event for event in events if is_visible(event, now)]


@router.get("/events/{event_id}", response_model=EventOut)
def get_event(
    event_id: uuid.UUID,
    db: Session = Depends(get_db),
    user_id: str = Depends(current_user_id),
):
    """상세. 노출 중이 아니면 없는 것과 같이 404."""
    event = db.get(Event, event_id)
    if event is None or not is_visible(event, datetime.now(timezone.utc)):
        raise HTTPException(status_code=404, detail="이벤트를 찾을 수 없어요.")
    return event
