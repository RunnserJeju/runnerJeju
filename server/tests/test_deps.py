"""요청 단위 의존성(current_user_id, require_admin_key) 테스트.

둘 다 DB 없이 검증 가능하다. require_admin_key는 환경변수(ADMIN_API_KEY)와
헤더 비교가 전부라 monkeypatch로 충분하다.
"""

import uuid

import pytest
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials

from app import deps, security

USER_ID = uuid.uuid4()


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


class TestRequireAdminKey:
    KEY = "test-admin-key"

    def test_allows_matching_key(self, monkeypatch):
        monkeypatch.setenv("ADMIN_API_KEY", self.KEY)

        assert deps.require_admin_key(self.KEY) is None

    def test_rejects_wrong_key(self, monkeypatch):
        monkeypatch.setenv("ADMIN_API_KEY", self.KEY)

        with pytest.raises(HTTPException) as exc_info:
            deps.require_admin_key("wrong-key")

        assert exc_info.value.status_code == 401

    def test_rejects_missing_header(self, monkeypatch):
        monkeypatch.setenv("ADMIN_API_KEY", self.KEY)

        with pytest.raises(HTTPException) as exc_info:
            deps.require_admin_key(None)

        assert exc_info.value.status_code == 401

    def test_refuses_when_server_key_unset(self, monkeypatch):
        # 서버에 키가 없으면 어떤 헤더로도 통과할 수 없어야 한다(빈 값 매칭 금지).
        monkeypatch.delenv("ADMIN_API_KEY", raising=False)

        with pytest.raises(HTTPException) as exc_info:
            deps.require_admin_key("")

        assert exc_info.value.status_code == 503
