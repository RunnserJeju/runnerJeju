"""이벤트 라우터 테스트 — 운영자 CRUD, 앱 노출 규칙, 값 검증.

옛 test_missions.py를 이벤트로 옮겼다(missions → events, 0033). DB 없이 Session의
최소 인터페이스만 흉내내는 FakeSession을 쓴다(test_notices.py와 같은 방침).
"""

import uuid
from datetime import datetime, timedelta, timezone

import pytest
from fastapi import HTTPException
from pydantic import ValidationError

from app.admin import events as admin_events
from app.models import Event
from app.routers import events as events_router
from app.schemas import EventCreate, EventUpdate

NOW = datetime(2026, 9, 2, 12, 0, tzinfo=timezone.utc)
DAY = timedelta(days=1)


def _event(**over) -> Event:
    fields = dict(
        id=uuid.uuid4(),
        title="가을 챌린지",
        body="자세한 내용은 https://example.com 에서 확인하세요.",
        image_url=None,
        starts_at=None,
        ends_at=None,
        is_active=True,
        visibility="public",
        sort_order=0,
    )
    fields.update(over)
    return Event(**fields)


class _FakeResult:
    def __init__(self, rows):
        self._rows = rows

    def scalars(self):
        return self._rows


class FakeSession:
    def __init__(self, events: list[Event] | None = None):
        self._events = list(events or [])
        self.added: list[object] = []
        self.deleted: list[object] = []

    def execute(self, _stmt):
        return _FakeResult(list(self._events))

    def get(self, _model, event_id):
        return next((e for e in self._events if e.id == event_id), None)

    def add(self, obj):
        if getattr(obj, "id", None) is None:
            obj.id = uuid.uuid4()
        self.added.append(obj)
        self._events.append(obj)

    def delete(self, obj):
        self.deleted.append(obj)
        self._events = [e for e in self._events if e is not obj]

    def commit(self):
        pass

    def refresh(self, _obj):
        pass


class TestAdminCrud:
    def test_creates_with_all_fields(self):
        db = FakeSession()
        payload = EventCreate(
            title="가을 챌린지",
            body="본문",
            starts_at=NOW,
            ends_at=NOW + DAY,
            sort_order=2,
            is_active=False,
        )

        result = admin_events.create_event(payload, db)

        assert result.title == "가을 챌린지" and result.body == "본문"
        assert result.starts_at == NOW and result.ends_at == NOW + DAY
        assert result.sort_order == 2 and result.is_active is False
        assert result in db.added

    def test_update_replaces_fields(self):
        e = _event(title="옛")
        db = FakeSession([e])

        admin_events.update_event(
            e.id, EventUpdate(title="새", body="새 본문", is_active=False, sort_order=5), db
        )

        assert e.title == "새" and e.body == "새 본문"
        assert e.is_active is False and e.sort_order == 5

    def test_delete(self):
        e = _event()
        db = FakeSession([e])

        admin_events.delete_event(e.id, db)

        assert e in db.deleted

    def test_404_when_missing(self):
        with pytest.raises(HTTPException) as exc:
            admin_events.update_event(
                uuid.uuid4(), EventUpdate(title="t", body="b"), FakeSession()
            )
        assert exc.value.status_code == 404


class TestVisibility:
    def test_hidden_scheduled_and_expired_are_not_visible(self):
        assert events_router.is_visible(_event(), NOW, is_admin=False)
        assert not events_router.is_visible(_event(is_active=False), NOW, is_admin=False)
        assert not events_router.is_visible(_event(starts_at=NOW + DAY), NOW, is_admin=False)
        assert not events_router.is_visible(_event(ends_at=NOW - DAY), NOW, is_admin=False)

    def test_admin_only_event_is_visible_to_admin_only(self):
        e = _event(visibility="admin")
        assert not events_router.is_visible(e, NOW, is_admin=False)
        assert events_router.is_visible(e, NOW, is_admin=True)
        # 공개 범위는 기간과 별개 — 운영자라도 기간 밖이면 안 보인다.
        assert not events_router.is_visible(
            _event(visibility="admin", ends_at=NOW - DAY), NOW, is_admin=True
        )

    def test_app_detail_404_when_hidden(self):
        e = _event(is_active=False)

        with pytest.raises(HTTPException) as exc:
            events_router.get_event(e.id, FakeSession([e]), user_id="u", is_admin=False)
        assert exc.value.status_code == 404


class TestEventSchema:
    def test_rejects_end_before_start(self):
        with pytest.raises(ValidationError):
            EventCreate(title="t", body="b", starts_at=NOW, ends_at=NOW - DAY)

    def test_rejects_blank_body(self):
        with pytest.raises(ValidationError):
            EventCreate(title="t", body="")
