"""공지사항 라우터 테스트 — 공개 목록(노출 기간 필터)과 운영자 CRUD.

test_auth_apple.py와 같은 방침으로 DB 없이 Session의 최소 인터페이스만 흉내내는
FakeSession을 쓴다. 노출 기간 필터는 SQL이 아니라 파이썬(_is_visible)에서 하므로
FakeSession이 전량을 돌려줘도 엔드포인트가 걸러낸다 — DB 없이 규칙을 검증할 수 있다.

require_admin(_key)이 하는 권한 검사는 라우터 함수를 직접 부르면 우회되므로
test_deps.py에서 따로 검증한다.
"""

import uuid
from datetime import datetime, timedelta, timezone

import pytest
from fastapi import HTTPException
from pydantic import ValidationError

from app.admin import notices as admin_notices_router
from app.models import Notice
from app.routers import notices as notices_router
from app.schemas import NoticeCreate, NoticeUpdate

NOW = datetime(2026, 9, 2, 12, 0, tzinfo=timezone.utc)
DAY = timedelta(days=1)


def _notice(**over) -> Notice:
    fields = dict(
        id=uuid.uuid4(),
        title="공지",
        body="내용",
        category="etc",
        starts_at=None,
        ends_at=None,
    )
    fields.update(over)
    return Notice(**fields)


class _FakeResult:
    def __init__(self, rows):
        self._rows = rows

    def scalars(self):
        return self._rows


class FakeSession:
    def __init__(self, notices: list[Notice] | None = None):
        self._notices = list(notices or [])
        self.added: list[object] = []
        self.deleted: list[object] = []

    def execute(self, _stmt):
        return _FakeResult(list(self._notices))

    def get(self, _model, notice_id):
        return next((n for n in self._notices if n.id == notice_id), None)

    def add(self, obj):
        if getattr(obj, "id", None) is None:
            obj.id = uuid.uuid4()
        self.added.append(obj)
        self._notices.append(obj)

    def delete(self, obj):
        self.deleted.append(obj)
        self._notices = [n for n in self._notices if n is not obj]

    def commit(self):
        pass

    def refresh(self, _obj):
        pass


class TestIsVisible:
    def test_no_period_is_visible(self):
        assert notices_router._is_visible(_notice(), NOW) is True

    def test_future_start_hidden(self):
        assert notices_router._is_visible(_notice(starts_at=NOW + DAY), NOW) is False

    def test_past_start_visible(self):
        assert notices_router._is_visible(_notice(starts_at=NOW - DAY), NOW) is True

    def test_past_end_hidden(self):
        assert notices_router._is_visible(_notice(ends_at=NOW - DAY), NOW) is False

    def test_future_end_visible(self):
        assert notices_router._is_visible(_notice(ends_at=NOW + DAY), NOW) is True

    def test_within_window_visible(self):
        n = _notice(starts_at=NOW - DAY, ends_at=NOW + DAY)
        assert notices_router._is_visible(n, NOW) is True


class TestListNotices:
    def test_only_visible_are_returned(self):
        visible = _notice(title="노출중", starts_at=NOW - DAY, ends_at=NOW + DAY)
        scheduled = _notice(title="예약", starts_at=NOW + DAY)
        expired = _notice(title="만료", ends_at=NOW - DAY)
        always = _notice(title="상시")
        db = FakeSession([visible, scheduled, expired, always])

        # 엔드포인트는 실제 now()를 쓰므로, 지금 시각 기준으로 상시/노출중만 남는다.
        result = notices_router.list_notices(db, user_id=str(uuid.uuid4()))
        titles = {n.title for n in result}

        assert "노출중" in titles and "상시" in titles
        assert "예약" not in titles and "만료" not in titles

    def test_empty_when_no_notices(self):
        assert notices_router.list_notices(FakeSession(), user_id="u") == []


class TestAdminListNotices:
    def test_returns_all_including_scheduled_and_expired(self):
        # 운영자 목록은 노출 기간과 무관하게 전부 보여준다.
        scheduled = _notice(title="예약", starts_at=NOW + DAY)
        expired = _notice(title="만료", ends_at=NOW - DAY)
        db = FakeSession([scheduled, expired])

        result = admin_notices_router.list_all_notices(db)

        assert {n.title for n in result} == {"예약", "만료"}


class TestCreateNotice:
    def test_creates_with_category_and_period(self):
        db = FakeSession()
        payload = NoticeCreate(
            title="점검 안내",
            body="새벽 점검 예정",
            category="maintenance",
            starts_at=NOW,
            ends_at=NOW + DAY,
        )

        result = admin_notices_router.create_notice(payload, db)

        assert result.title == "점검 안내"
        assert result.category == "maintenance"
        assert result.starts_at == NOW and result.ends_at == NOW + DAY
        assert result in db.added

    def test_period_defaults_to_none(self):
        db = FakeSession()
        payload = NoticeCreate(title="상시", body="내용", category="app_guide")

        result = admin_notices_router.create_notice(payload, db)

        assert result.starts_at is None and result.ends_at is None


class TestUpdateNotice:
    def test_replaces_fields(self):
        notice = _notice(title="옛 제목", category="etc")
        db = FakeSession([notice])
        payload = NoticeUpdate(
            title="새 제목",
            body="새 내용",
            category="event",
            starts_at=NOW,
            ends_at=NOW + DAY,
        )

        result = admin_notices_router.update_notice(notice.id, payload, db)

        assert notice.title == "새 제목"
        assert notice.category == "event"
        assert notice.ends_at == NOW + DAY
        assert result.title == "새 제목"

    def test_404_when_missing(self):
        db = FakeSession()
        payload = NoticeUpdate(title="t", body="b", category="etc")

        with pytest.raises(HTTPException) as exc:
            admin_notices_router.update_notice(uuid.uuid4(), payload, db)

        assert exc.value.status_code == 404


class TestDeleteNotice:
    def test_deletes(self):
        notice = _notice()
        db = FakeSession([notice])

        admin_notices_router.delete_notice(notice.id, db)

        assert notice in db.deleted

    def test_404_when_missing(self):
        db = FakeSession()

        with pytest.raises(HTTPException) as exc:
            admin_notices_router.delete_notice(uuid.uuid4(), db)

        assert exc.value.status_code == 404


class TestNoticeSchema:
    def test_rejects_unknown_category(self):
        with pytest.raises(ValidationError):
            NoticeCreate(title="t", body="b", category="notice")

    def test_rejects_end_before_start(self):
        with pytest.raises(ValidationError):
            NoticeCreate(
                title="t", body="b", category="event",
                starts_at=NOW, ends_at=NOW - DAY,
            )

    def test_allows_equal_start_end(self):
        # 시작=종료는 허용(경계). 그 순간만 노출되는 셈.
        NoticeCreate(title="t", body="b", category="event", starts_at=NOW, ends_at=NOW)
