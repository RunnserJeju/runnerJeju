"""회원 조회 운영자 라우터 테스트 — 목록/상세와 완주 집계·N+1 회피 로직.

DB 없이 Session의 최소 인터페이스만 흉내내는 fake를 쓴다(test_missions.py와 같은
방침). SQL 자체(정렬·offset·조인)는 fake로 검증하지 않으므로, 배치 집계/조인
매핑·provider 파생·404·응답 shape 같은 파이썬 로직을 본다. require_admin_session
권한 검사는 함수 직접 호출로 우회되므로 test_admin_auth.py에서 따로 검증한다.
"""

import uuid
from datetime import datetime, timezone

import pytest
from fastapi import HTTPException

from app.admin import users as users_router
from app.models import User

NOW = datetime(2026, 9, 5, 12, 0, tzinfo=timezone.utc)


def _user(**over) -> User:
    fields = dict(
        id=uuid.uuid4(),
        kakao_id="k1",
        apple_id=None,
        google_id=None,
        nickname="러너",
        profile_image_url=None,
        email="a@example.com",
        created_at=NOW,
    )
    fields.update(over)
    return User(**fields)


class _AllResult:
    def __init__(self, rows):
        self._rows = rows

    def all(self):
        return self._rows


class _ScalarsResult:
    def __init__(self, rows):
        self._rows = rows

    def scalars(self):
        return self._rows


class TestProviders:
    def test_kakao_only(self):
        u = _user(kakao_id="k", apple_id=None, google_id=None)
        assert users_router._providers(u) == ["kakao"]

    def test_apple_only(self):
        u = _user(kakao_id=None, apple_id="a", google_id=None)
        assert users_router._providers(u) == ["apple"]

    def test_google_only(self):
        u = _user(kakao_id=None, apple_id=None, google_id="g")
        assert users_router._providers(u) == ["google"]

    def test_multiple_linked(self):
        u = _user(kakao_id="k", apple_id="a", google_id="g")
        assert users_router._providers(u) == ["kakao", "apple", "google"]

    def test_none(self):
        u = _user(kakao_id=None, apple_id=None, google_id=None)
        assert users_router._providers(u) == []


class TestCompletedCounts:
    def test_maps_grouped_rows(self):
        a, b = str(uuid.uuid4()), str(uuid.uuid4())

        class Fake:
            def execute(self, _stmt):
                return _AllResult([(a, 3), (b, 1)])

        assert users_router._completed_counts(Fake(), [a, b]) == {a: 3, b: 1}

    def test_empty_ids_skips_query(self):
        # 빈 id면 쿼리 없이 빈 dict를 준다 — execute를 부르면 안 된다.
        class Boom:
            def execute(self, _stmt):
                raise AssertionError("빈 id에는 쿼리하면 안 된다")

        assert users_router._completed_counts(Boom(), []) == {}


class TestCompletedCourses:
    def test_maps_joined_rows(self):
        cid = uuid.uuid4()

        class Fake:
            def execute(self, _stmt):
                return _AllResult([(cid, "사계 해안", NOW)])

        result = users_router._completed_courses(Fake(), _user())

        assert result == [{"course_id": cid, "name": "사계 해안", "acquired_at": NOW}]

    def test_empty_when_no_stamps(self):
        class Fake:
            def execute(self, _stmt):
                return _AllResult([])

        assert users_router._completed_courses(Fake(), _user()) == []


class ListFakeSession:
    """목록 엔드포인트가 부르는 것만 흉내낸다: scalar(total), execute().scalars()(유저).

    완주 집계(_completed_counts)는 테스트에서 monkeypatch하므로 그 쿼리는 안 탄다.
    """

    def __init__(self, users, total):
        self._users = users
        self._total = total

    def scalar(self, _stmt):
        return self._total

    def execute(self, _stmt):
        return _ScalarsResult(self._users)


class TestListUsers:
    def test_returns_total_and_items(self, monkeypatch):
        u = _user(nickname="러너", email="a@example.com")
        monkeypatch.setattr(
            users_router, "_completed_counts", lambda db, ids: {str(u.id): 2}
        )
        db = ListFakeSession([u], total=1)

        result = users_router.list_users(keyword=None, limit=20, offset=0, db=db)

        assert result["total"] == 1
        assert len(result["items"]) == 1
        item = result["items"][0]
        assert item["id"] == u.id
        assert item["nickname"] == "러너"
        assert item["providers"] == ["kakao"]
        assert item["email"] == "a@example.com"
        assert item["completed_count"] == 2

    def test_count_defaults_to_zero(self, monkeypatch):
        # 완주가 없는 유저는 집계에 안 잡히므로 0으로 떨어진다.
        u = _user()
        monkeypatch.setattr(users_router, "_completed_counts", lambda db, ids: {})
        db = ListFakeSession([u], total=1)

        result = users_router.list_users(keyword=None, limit=20, offset=0, db=db)

        assert result["items"][0]["completed_count"] == 0

    def test_empty_page(self, monkeypatch):
        monkeypatch.setattr(users_router, "_completed_counts", lambda db, ids: {})
        db = ListFakeSession([], total=0)

        result = users_router.list_users(keyword=None, limit=20, offset=0, db=db)

        assert result == {"total": 0, "items": []}

    def test_keyword_does_not_crash(self, monkeypatch):
        # keyword가 있으면 필터가 붙는다 — fake는 필터를 무시하지만 흐름이 깨지지 않아야 한다.
        u = _user()
        monkeypatch.setattr(users_router, "_completed_counts", lambda db, ids: {})
        db = ListFakeSession([u], total=1)

        result = users_router.list_users(keyword="러너", limit=20, offset=0, db=db)

        assert result["total"] == 1


class DetailFakeSession:
    def __init__(self, user):
        self._user = user

    def get(self, _model, user_id):
        if self._user is not None and self._user.id == user_id:
            return self._user
        return None


class TestGetUser:
    def test_returns_detail(self, monkeypatch):
        u = _user(nickname="러너", email="a@example.com", profile_image_url="https://cdn/p.png")
        cid = uuid.uuid4()
        monkeypatch.setattr(
            users_router,
            "_completed_courses",
            lambda db, user: [{"course_id": cid, "name": "사계 해안", "acquired_at": NOW}],
        )
        db = DetailFakeSession(u)

        result = users_router.get_user(u.id, db)

        assert result["id"] == u.id
        assert result["nickname"] == "러너"
        assert result["providers"] == ["kakao"]
        assert result["profile_image_url"] == "https://cdn/p.png"
        assert result["completed_count"] == 1
        assert result["completed_courses"][0]["name"] == "사계 해안"

    def test_completed_count_matches_list_length(self, monkeypatch):
        u = _user()
        cid1, cid2 = uuid.uuid4(), uuid.uuid4()
        monkeypatch.setattr(
            users_router,
            "_completed_courses",
            lambda db, user: [
                {"course_id": cid1, "name": "A", "acquired_at": NOW},
                {"course_id": cid2, "name": "B", "acquired_at": NOW},
            ],
        )
        db = DetailFakeSession(u)

        result = users_router.get_user(u.id, db)

        assert result["completed_count"] == 2

    def test_404_when_missing(self):
        with pytest.raises(HTTPException) as exc:
            users_router.get_user(uuid.uuid4(), DetailFakeSession(None))
        assert exc.value.status_code == 404
