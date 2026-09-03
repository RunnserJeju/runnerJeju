"""운영자 세션 인증 테스트 — 비밀번호 해시, 로그인, 세션 가드, 로그아웃.

DB 없이 돌린다. 다른 admin 테스트(test_banners 등)의 FakeSession은 execute가
저장된 행을 통째로 돌려주지만, 여기선 로그인/가드가 username·token_hash로
정확히 한 행을 집어야 하므로 select(...).where(col == value)를 최소 해석하는
FakeSession을 쓴다 — 라우터의 실제 쿼리 코드를 그대로 태운다.
"""

import uuid
from datetime import datetime, timedelta, timezone

import pytest
from fastapi import HTTPException, Response

from app.admin import auth
from app.admin.security import (
    SESSION_COOKIE_NAME,
    hash_password,
    hash_session_token,
    verify_password,
)
from app.models import AdminSession, AdminUser
from app.schemas import AdminLoginRequest


class _FakeResult:
    def __init__(self, rows):
        self._rows = rows

    def scalar_one_or_none(self):
        if not self._rows:
            return None
        if len(self._rows) > 1:
            raise AssertionError("기대와 달리 여러 행이 매칭됐어요")
        return self._rows[0]


class FakeSession:
    """select(Model).where(col == value) 하나짜리 조건과 get()/add()/commit()만 흉내낸다."""

    def __init__(self, admin_users=None, admin_sessions=None):
        self._rows = {
            AdminUser: list(admin_users or []),
            AdminSession: list(admin_sessions or []),
        }
        self.commits = 0

    def execute(self, stmt):
        entity = stmt.column_descriptions[0]["entity"]
        rows = self._rows[entity]
        where = stmt.whereclause
        if where is not None:
            attr = where.left.name
            value = where.right.value
            rows = [r for r in rows if getattr(r, attr) == value]
        return _FakeResult(list(rows))

    def get(self, model, pk):
        return next((r for r in self._rows[model] if r.id == pk), None)

    def add(self, obj):
        if getattr(obj, "id", None) is None:
            obj.id = uuid.uuid4()
        self._rows[type(obj)].append(obj)

    def commit(self):
        self.commits += 1


class FakeRequest:
    """require_admin_session이 쓰는 것은 .cookies뿐이다."""

    def __init__(self, cookies=None):
        self.cookies = cookies or {}


def _now():
    return datetime.now(timezone.utc)


def make_admin(password="correct-horse", disabled=False, username="jeju"):
    return AdminUser(
        id=uuid.uuid4(),
        username=username,
        password_hash=hash_password(password),
        display_name="제주 운영자",
        disabled_at=_now() if disabled else None,
    )


def make_session(admin, *, raw_token="raw-token", expires_in=timedelta(hours=1),
                 revoked=False):
    return AdminSession(
        id=uuid.uuid4(),
        admin_user_id=admin.id,
        token_hash=hash_session_token(raw_token),
        expires_at=_now() + expires_in,
        revoked_at=_now() if revoked else None,
    )


class TestPasswordHashing:
    def test_roundtrip(self):
        h = hash_password("hunter2")
        assert h != "hunter2"  # 평문이 아니어야 한다
        assert verify_password("hunter2", h) is True

    def test_wrong_password(self):
        assert verify_password("nope", hash_password("hunter2")) is False

    def test_malformed_hash_returns_false(self):
        # 손상된 해시로 500이 나면 안 된다 — 조용히 실패.
        assert verify_password("hunter2", "") is False

    def test_over_72_bytes_returns_false(self):
        # bcrypt 72바이트 초과 입력은 예외 대신 인증 실패로.
        assert verify_password("a" * 100, hash_password("hunter2")) is False


class TestLogin:
    def test_success_sets_cookie_and_creates_session(self):
        admin = make_admin(password="pw")
        db = FakeSession(admin_users=[admin])
        response = Response()

        result = auth.login(
            AdminLoginRequest(username="jeju", password="pw"), response, db
        )

        assert result.username == "jeju"
        assert db.commits == 1
        assert len(db._rows[AdminSession]) == 1
        # 저장된 건 해시뿐, 원본 토큰이 아니어야 한다.
        stored = db._rows[AdminSession][0]
        cookie = response.headers.get("set-cookie")
        assert SESSION_COOKIE_NAME in cookie
        assert "httponly" in cookie.lower()
        assert "samesite=strict" in cookie.lower()
        assert "path=/admin" in cookie.lower()
        assert stored.token_hash != "" and len(stored.token_hash) == 64

    def test_wrong_password_rejected(self):
        admin = make_admin(password="pw")
        db = FakeSession(admin_users=[admin])

        with pytest.raises(HTTPException) as exc:
            auth.login(AdminLoginRequest(username="jeju", password="WRONG"),
                       Response(), db)
        assert exc.value.status_code == 401
        assert len(db._rows[AdminSession]) == 0  # 세션이 생기면 안 된다

    def test_unknown_user_rejected(self):
        db = FakeSession(admin_users=[])

        with pytest.raises(HTTPException) as exc:
            auth.login(AdminLoginRequest(username="ghost", password="pw"),
                       Response(), db)
        assert exc.value.status_code == 401

    def test_disabled_user_rejected(self):
        admin = make_admin(password="pw", disabled=True)
        db = FakeSession(admin_users=[admin])

        with pytest.raises(HTTPException) as exc:
            auth.login(AdminLoginRequest(username="jeju", password="pw"),
                       Response(), db)
        assert exc.value.status_code == 401


class TestRequireAdminSession:
    def test_valid_session_returns_admin(self):
        admin = make_admin()
        session = make_session(admin, raw_token="tok")
        db = FakeSession(admin_users=[admin], admin_sessions=[session])

        result = auth.require_admin_session(
            FakeRequest({SESSION_COOKIE_NAME: "tok"}), db
        )
        assert result is admin

    def test_missing_cookie_rejected(self):
        db = FakeSession()
        with pytest.raises(HTTPException) as exc:
            auth.require_admin_session(FakeRequest({}), db)
        assert exc.value.status_code == 401

    def test_unknown_token_rejected(self):
        admin = make_admin()
        session = make_session(admin, raw_token="tok")
        db = FakeSession(admin_users=[admin], admin_sessions=[session])
        with pytest.raises(HTTPException) as exc:
            auth.require_admin_session(FakeRequest({SESSION_COOKIE_NAME: "other"}), db)
        assert exc.value.status_code == 401

    def test_revoked_session_rejected(self):
        admin = make_admin()
        session = make_session(admin, raw_token="tok", revoked=True)
        db = FakeSession(admin_users=[admin], admin_sessions=[session])
        with pytest.raises(HTTPException) as exc:
            auth.require_admin_session(FakeRequest({SESSION_COOKIE_NAME: "tok"}), db)
        assert exc.value.status_code == 401

    def test_expired_session_rejected(self):
        admin = make_admin()
        session = make_session(admin, raw_token="tok", expires_in=timedelta(hours=-1))
        db = FakeSession(admin_users=[admin], admin_sessions=[session])
        with pytest.raises(HTTPException) as exc:
            auth.require_admin_session(FakeRequest({SESSION_COOKIE_NAME: "tok"}), db)
        assert exc.value.status_code == 401

    def test_disabled_admin_rejected_even_with_valid_session(self):
        admin = make_admin(disabled=True)
        session = make_session(admin, raw_token="tok")
        db = FakeSession(admin_users=[admin], admin_sessions=[session])
        with pytest.raises(HTTPException) as exc:
            auth.require_admin_session(FakeRequest({SESSION_COOKIE_NAME: "tok"}), db)
        assert exc.value.status_code == 401


class TestLogout:
    def test_revokes_session_and_clears_cookie(self):
        admin = make_admin()
        session = make_session(admin, raw_token="tok")
        db = FakeSession(admin_users=[admin], admin_sessions=[session])
        response = Response()

        result = auth.logout(FakeRequest({SESSION_COOKIE_NAME: "tok"}), response, db)

        assert result == {"ok": True}
        assert session.revoked_at is not None  # 폐기됨
        cookie = response.headers.get("set-cookie")
        assert SESSION_COOKIE_NAME in cookie
        # 삭제 쿠키는 즉시 만료된다(Max-Age=0).
        assert "max-age=0" in cookie.lower()

    def test_without_cookie_is_idempotent(self):
        db = FakeSession()
        response = Response()
        result = auth.logout(FakeRequest({}), response, db)
        assert result == {"ok": True}  # 쿠키가 없어도 성공
