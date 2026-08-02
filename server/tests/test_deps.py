"""요청 단위 의존성(current_user_id, require_admin) 테스트.

current_user_id는 DB 없이도 검증 가능하다. require_admin은 role 조회에 DB가
필요해서, test_auth_apple.py와 같은 방침으로 Session의 최소 인터페이스만
흉내내는 FakeDb를 쓴다. 실제 카카오 토큰 교환(POST /auth/kakao)처럼 외부 API
호출과 upsert가 얽힌 부분은 이 파일의 범위 밖이다.
"""

import uuid

import pytest
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials

from app import deps, security
from app.models import User

USER_ID = uuid.uuid4()


class FakeDb:
    """require_admin이 쓰는 db.get(User, id) 하나만 흉내낸다."""

    def __init__(self, user: User | None):
        self._user = user

    def get(self, _model, _id):
        return self._user


def bearer(token: str) -> HTTPAuthorizationCredentials:
    return HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)


class TestCurrentUserId:
    def test_returns_sub_for_valid_access_token(self):
        token = security.create_access_token(USER_ID)

        assert deps.current_user_id(bearer(token)) == str(USER_ID)

    def test_rejects_missing_credentials(self):
        with pytest.raises(HTTPException) as exc_info:
            deps.current_user_id(None)

        assert exc_info.value.status_code == 401

    def test_rejects_garbage_token(self):
        with pytest.raises(HTTPException) as exc_info:
            deps.current_user_id(bearer("not-a-jwt"))

        assert exc_info.value.status_code == 401

    def test_rejects_refresh_token_used_as_access_token(self):
        token = security.create_refresh_token(USER_ID, uuid.uuid4())

        with pytest.raises(HTTPException) as exc_info:
            deps.current_user_id(bearer(token))

        assert exc_info.value.status_code == 401


class TestRequireAdmin:
    def test_allows_admin_user(self):
        admin = User(id=USER_ID, role="admin")
        db = FakeDb(admin)

        assert deps.require_admin(str(USER_ID), db) == str(USER_ID)

    def test_rejects_non_admin_user(self):
        user = User(id=USER_ID, role="user")
        db = FakeDb(user)

        with pytest.raises(HTTPException) as exc_info:
            deps.require_admin(str(USER_ID), db)

        assert exc_info.value.status_code == 403

    def test_rejects_when_user_not_found(self):
        db = FakeDb(None)

        with pytest.raises(HTTPException) as exc_info:
            deps.require_admin(str(USER_ID), db)

        assert exc_info.value.status_code == 403
