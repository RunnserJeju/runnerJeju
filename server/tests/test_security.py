"""JWT 발급/검증 테스트."""

import uuid
from datetime import datetime, timedelta, timezone

import jwt
import pytest

from app import security

USER_ID = uuid.uuid4()


class TestAccessToken:
    def test_decodes_with_expected_claims(self):
        token = security.create_access_token(USER_ID)
        payload = security.decode_token(token)

        assert payload["sub"] == str(USER_ID)
        assert payload["type"] == "access"

    def test_expires_in_configured_ttl(self):
        token = security.create_access_token(USER_ID)
        payload = security.decode_token(token)

        ttl = payload["exp"] - payload["iat"]
        assert ttl == pytest.approx(security.ACCESS_TOKEN_TTL.total_seconds(), abs=1)


class TestRefreshToken:
    def test_decodes_with_expected_claims(self):
        token_id = uuid.uuid4()
        token = security.create_refresh_token(USER_ID, token_id)
        payload = security.decode_token(token)

        assert payload["sub"] == str(USER_ID)
        assert payload["type"] == "refresh"
        assert payload["jti"] == str(token_id)

    def test_expires_in_configured_ttl(self):
        token = security.create_refresh_token(USER_ID, uuid.uuid4())
        payload = security.decode_token(token)

        ttl = payload["exp"] - payload["iat"]
        assert ttl == pytest.approx(security.REFRESH_TOKEN_TTL.total_seconds(), abs=1)

    def test_different_tokens_get_different_jti(self):
        first = security.decode_token(security.create_refresh_token(USER_ID, uuid.uuid4()))
        second = security.decode_token(security.create_refresh_token(USER_ID, uuid.uuid4()))

        assert first["jti"] != second["jti"]


class TestDecodeToken:
    def test_rejects_expired_token(self):
        now = datetime.now(timezone.utc)
        expired = jwt.encode(
            {
                "sub": str(USER_ID),
                "type": "access",
                "iat": now - timedelta(hours=2),
                "exp": now - timedelta(hours=1),
            },
            security.SECRET_KEY,
            algorithm=security.ALGORITHM,
        )

        with pytest.raises(jwt.ExpiredSignatureError):
            security.decode_token(expired)

    def test_rejects_token_signed_with_different_secret(self):
        forged = jwt.encode(
            {"sub": str(USER_ID), "type": "access"},
            "wrong-secret-but-long-enough-for-hs256",
            algorithm=security.ALGORITHM,
        )

        with pytest.raises(jwt.InvalidSignatureError):
            security.decode_token(forged)

    def test_rejects_garbage_string(self):
        with pytest.raises(jwt.DecodeError):
            security.decode_token("not-a-jwt")
