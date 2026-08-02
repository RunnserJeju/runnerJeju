"""공지사항 라우터(list_notices, create_notice) 테스트.

test_auth_apple.py와 같은 방침으로 DB 없이 Session의 최소 인터페이스만
흉내내는 FakeSession을 쓴다. require_admin이 하는 권한 검사 자체는 라우터
함수를 직접 호출하면 우회되므로(Depends가 실행되지 않는다) test_deps.py의
TestRequireAdmin에서 따로 검증한다.
"""

import uuid

from app.models import Notice
from app.routers import notices as notices_router
from app.schemas import NoticeCreate


class _FakeResult:
    def __init__(self, rows):
        self._rows = rows

    def scalars(self):
        return self._rows


class FakeSession:
    def __init__(self, notices: list[Notice] | None = None):
        self._notices = list(notices or [])
        self.added: list[object] = []

    def execute(self, _stmt):
        return _FakeResult(list(self._notices))

    def add(self, obj):
        if getattr(obj, "id", None) is None:
            obj.id = uuid.uuid4()
        self.added.append(obj)
        self._notices.append(obj)

    def commit(self):
        pass

    def refresh(self, _obj):
        pass


class TestListNotices:
    def test_returns_existing_notices(self):
        existing = [
            Notice(id=uuid.uuid4(), title="첫 공지", body="내용1"),
            Notice(id=uuid.uuid4(), title="둘째 공지", body="내용2"),
        ]
        db = FakeSession(notices=existing)

        result = notices_router.list_notices(db, user_id=str(uuid.uuid4()))

        assert result == existing

    def test_returns_empty_list_when_no_notices(self):
        db = FakeSession()

        result = notices_router.list_notices(db, user_id=str(uuid.uuid4()))

        assert result == []


class TestCreateNotice:
    def test_creates_notice_with_given_title_and_body(self):
        db = FakeSession()
        payload = NoticeCreate(title="새 공지", body="공지 내용입니다")

        result = notices_router.create_notice(payload, db, user_id=str(uuid.uuid4()))

        assert result.title == "새 공지"
        assert result.body == "공지 내용입니다"
        assert result.id is not None
        assert result in db.added

    def test_created_notice_is_returned_by_list(self):
        db = FakeSession()
        payload = NoticeCreate(title="공지", body="내용")

        notices_router.create_notice(payload, db, user_id=str(uuid.uuid4()))
        result = notices_router.list_notices(db, user_id=str(uuid.uuid4()))

        assert len(result) == 1
        assert result[0].title == "공지"
