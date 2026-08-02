"""구글 로그인(login_with_google) 테스트.

애플과 마찬가지로 구글 공개키 검증(JWKS 조회 + jwt.decode) 부분을 monkeypatch로
가짜 claims를 흘려보내게 만들고, 그 이후 로직(유저 upsert, 토큰 발급)만
검증한다. test_auth_apple.py와 같은 방침이다.
"""

import uuid

import jwt
import pytest

from app.models import User
from app.routers import auth as auth_router
from app.schemas import GoogleLoginRequest

GOOGLE_SUB = "109876543210987654321"


class FakeSession:
    """add()로 들어온 User에 실제 DB의 default=uuid.uuid4 흉내만 낸다."""

    def __init__(self, existing_user: User | None = None):
        self._existing_user = existing_user
        self.added: list[object] = []

    def scalar(self, _stmt):
        return self._existing_user

    def add(self, obj):
        if getattr(obj, "id", None) is None:
            obj.id = uuid.uuid4()
        self.added.append(obj)

    def commit(self):
        pass

    def refresh(self, _obj):
        pass


def _patch_google_verification(monkeypatch, claims: dict):
    monkeypatch.setattr(
        auth_router._google_jwk_client,
        "get_signing_key_from_jwt",
        lambda token: type("SigningKey", (), {"key": "fake-key"})(),
    )
    monkeypatch.setattr(auth_router.jwt, "decode", lambda *a, **k: claims)


class TestLoginWithGoogle:
    def test_creates_new_user_from_claims(self, monkeypatch):
        _patch_google_verification(
            monkeypatch,
            {
                "sub": GOOGLE_SUB,
                "email": "tester@example.com",
                "iss": "https://accounts.google.com",
            },
        )
        db = FakeSession(existing_user=None)
        payload = GoogleLoginRequest(id_token="fake.jwt.token")

        result = auth_router.login_with_google(payload, db)

        new_user = next(obj for obj in db.added if isinstance(obj, User))
        assert new_user.google_id == GOOGLE_SUB
        assert new_user.email == "tester@example.com"
        # 닉네임은 provider가 안 채운다 — 앱의 닉네임 설정 화면으로 유도해야 한다.
        assert new_user.nickname is None
        assert result.needs_nickname is True
        assert result.access_token
        assert result.refresh_token

    def test_reuses_existing_user_by_google_id(self, monkeypatch):
        # 구글은 애플과 달리 매 로그인마다 email 클레임을 내려준다.
        _patch_google_verification(
            monkeypatch,
            {
                "sub": GOOGLE_SUB,
                "email": "new@example.com",
                "iss": "accounts.google.com",
            },
        )
        existing = User(
            id=uuid.uuid4(),
            google_id=GOOGLE_SUB,
            nickname="기존닉네임",
            email="old@example.com",
        )
        db = FakeSession(existing_user=existing)
        payload = GoogleLoginRequest(id_token="fake.jwt.token")

        result = auth_router.login_with_google(payload, db)

        assert not any(isinstance(obj, User) for obj in db.added)
        assert existing.nickname == "기존닉네임"
        assert existing.email == "new@example.com"
        assert result.needs_nickname is False

    def test_rejects_invalid_token(self, monkeypatch):
        monkeypatch.setattr(
            auth_router._google_jwk_client,
            "get_signing_key_from_jwt",
            lambda token: type("SigningKey", (), {"key": "fake-key"})(),
        )
        monkeypatch.setattr(
            auth_router.jwt,
            "decode",
            lambda *a, **k: (_ for _ in ()).throw(jwt.InvalidSignatureError("bad sig")),
        )
        db = FakeSession()
        payload = GoogleLoginRequest(id_token="not-a-real-token")

        with pytest.raises(Exception) as exc_info:
            auth_router.login_with_google(payload, db)

        assert exc_info.value.status_code == 401

    def test_rejects_wrong_issuer(self, monkeypatch):
        # 서명 자체는 유효하지만 발급자가 구글이 아닌 경우 — 다른 서비스용
        # idToken을 재사용하려는 시도를 막는다.
        _patch_google_verification(
            monkeypatch,
            {"sub": GOOGLE_SUB, "email": "tester@example.com", "iss": "https://evil.example.com"},
        )
        db = FakeSession()
        payload = GoogleLoginRequest(id_token="fake.jwt.token")

        with pytest.raises(Exception) as exc_info:
            auth_router.login_with_google(payload, db)

        assert exc_info.value.status_code == 401
