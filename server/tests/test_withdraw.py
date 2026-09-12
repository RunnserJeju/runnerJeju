"""회원 탈퇴(DELETE /auth/me)와 last_login 갱신 테스트.

DB 없이 Session의 최소 인터페이스만 흉내내는 fake를 쓴다(test_courses.py의
GpxReplaceFakeSession처럼 execute된 statement 종류를 세어 delete/update 호출을 검증).
탈퇴는 PII 스크럽 + deleted_at + 세션 삭제 + 러닝 경로 비움을, last_login은 로그인·
리프레시에서의 갱신과 탈퇴 계정 차단을 본다.
"""

import uuid
from datetime import datetime, timezone

import pytest
from fastapi import HTTPException

from app.models import RefreshToken, User
from app.routers import auth as auth_router
from app.schemas import RefreshRequest
from app.security import create_refresh_token

NOW = datetime(2026, 9, 6, 12, 0, tzinfo=timezone.utc)
FAR_FUTURE = datetime(2099, 1, 1, tzinfo=timezone.utc)


def _user(**over) -> User:
    fields = dict(
        id=uuid.uuid4(),
        kakao_id="k1",
        apple_id=None,
        google_id=None,
        nickname="러너",
        profile_image_url="https://cdn/p.png",
        email="a@example.com",
        created_at=NOW,
        last_login_at=None,
        deleted_at=None,
    )
    fields.update(over)
    return User(**fields)


class WithdrawFakeSession:
    """withdraw가 부르는 것만 흉내낸다: get(User), execute(delete/update), commit."""

    def __init__(self, user):
        self._user = user
        self.executed = []
        self.committed = False

    def get(self, _model, key):
        return self._user if (self._user is not None and self._user.id == key) else None

    def execute(self, stmt):
        self.executed.append(stmt)
        return None

    def commit(self):
        self.committed = True

    @property
    def delete_count(self) -> int:
        return sum(1 for s in self.executed if type(s).__name__ == "Delete")

    @property
    def update_count(self) -> int:
        return sum(1 for s in self.executed if type(s).__name__ == "Update")


class TestWithdraw:
    def test_scrubs_pii_and_marks_deleted(self):
        u = _user()
        db = WithdrawFakeSession(u)

        auth_router.withdraw(user_id=str(u.id), db=db)

        assert u.email is None
        assert u.nickname is None
        assert u.profile_image_url is None
        assert u.kakao_id is None and u.apple_id is None and u.google_id is None
        assert u.deleted_at is not None
        assert db.committed is True

    def test_deletes_sessions_and_scrubs_run_paths(self):
        u = _user()
        db = WithdrawFakeSession(u)

        auth_router.withdraw(user_id=str(u.id), db=db)

        assert db.delete_count == 1  # refresh 토큰 삭제
        assert db.update_count == 1  # 러닝 GPS 경로 비움

    def test_idempotent_when_already_withdrawn(self):
        u = _user(deleted_at=NOW)
        db = WithdrawFakeSession(u)

        auth_router.withdraw(user_id=str(u.id), db=db)

        # 이미 탈퇴한 계정 — 아무것도 하지 않는다.
        assert db.committed is False
        assert db.executed == []

    def test_noop_when_user_missing(self):
        db = WithdrawFakeSession(None)

        auth_router.withdraw(user_id=str(uuid.uuid4()), db=db)

        assert db.committed is False
        assert db.executed == []


class IssueFakeSession:
    def __init__(self):
        self.added = []
        self.committed = False

    def add(self, obj):
        self.added.append(obj)

    def commit(self):
        self.committed = True


class TestLastLoginOnIssue:
    def test_issue_tokens_sets_last_login(self):
        u = _user(last_login_at=None)
        db = IssueFakeSession()

        auth_router._issue_tokens(db, u)

        assert u.last_login_at is not None
        assert any(isinstance(o, RefreshToken) for o in db.added)


class RefreshFakeSession:
    def __init__(self, stored, user):
        self._stored = stored
        self._user = user
        self.committed = False

    def get(self, model, _key):
        if model is RefreshToken:
            return self._stored
        if model is User:
            return self._user
        return None

    def commit(self):
        self.committed = True


class TestRefresh:
    def _token_and_stored(self, uid):
        jti = uuid.uuid4()
        token = create_refresh_token(uid, jti)
        stored = RefreshToken(
            id=jti, user_id=uid, expires_at=FAR_FUTURE, revoked_at=None
        )
        return token, stored

    def test_updates_last_login(self):
        uid = uuid.uuid4()
        token, stored = self._token_and_stored(uid)
        user = _user(id=uid, last_login_at=None, deleted_at=None)
        db = RefreshFakeSession(stored, user)

        result = auth_router.refresh_access_token(
            RefreshRequest(refresh_token=token), db
        )

        assert user.last_login_at is not None
        assert db.committed is True
        assert result.access_token

    def test_rejects_withdrawn_user(self):
        uid = uuid.uuid4()
        token, stored = self._token_and_stored(uid)
        user = _user(id=uid, deleted_at=NOW)
        db = RefreshFakeSession(stored, user)

        with pytest.raises(HTTPException) as exc:
            auth_router.refresh_access_token(RefreshRequest(refresh_token=token), db)
        assert exc.value.status_code == 401
