"""current_user_id 인증 dependency 테스트.

DB 없이도 검증 가능한 부분만 다룬다 — 실제 카카오 토큰 교환(POST /auth/kakao)은
외부 API 호출과 upsert가 얽혀 있어 이 파일의 범위 밖이다.
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
