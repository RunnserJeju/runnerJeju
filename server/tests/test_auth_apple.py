"""애플 로그인(login_with_apple) 테스트.

Apple Developer 계정이 없어 실제 identityToken을 발급받을 방법이 없다(docs/mvp.md
"Apple 로그인 복구" 참고). 그래서 애플 공개키 검증(JWKS 조회 + jwt.decode) 부분을
monkeypatch로 가짜 claims를 흘려보내게 만들고, 그 이후 로직(유저 upsert, 토큰
발급)만 검증한다. DB 없이 검증 가능한 부분만 다루는 test_deps.py와 같은 방침이다.
"""

import uuid

import jwt
import pytest

from app.models import User
from app.routers import auth as auth_router
from app.schemas import AppleLoginRequest

APPLE_SUB = "000123.abcdef1234567890.1234"


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


def _patch_apple_verification(monkeypatch, claims: dict):
    monkeypatch.setattr(
        auth_router._apple_jwk_client,
        "get_signing_key_from_jwt",
        lambda token: type("SigningKey", (), {"key": "fake-key"})(),
    )
    monkeypatch.setattr(auth_router.jwt, "decode", lambda *a, **k: claims)


class TestLoginWithApple:
    def test_creates_new_user_from_claims(self, monkeypatch):
        _patch_apple_verification(monkeypatch, {"sub": APPLE_SUB})
        db = FakeSession(existing_user=None)
        payload = AppleLoginRequest(identity_token="fake.jwt.token", full_name="테스터")

        result = auth_router.login_with_apple(payload, db)

        new_user = next(obj for obj in db.added if isinstance(obj, User))
        assert new_user.apple_id == APPLE_SUB
        assert new_user.nickname == "테스터"
        assert result.access_token
        assert result.refresh_token

    def test_reuses_existing_user_by_apple_id(self, monkeypatch):
        _patch_apple_verification(monkeypatch, {"sub": APPLE_SUB})
        existing = User(id=uuid.uuid4(), apple_id=APPLE_SUB, nickname="기존닉네임")
        db = FakeSession(existing_user=existing)
        # 최초 인가 이후에는 애플이 full_name을 다시 내려주지 않는다.
        payload = AppleLoginRequest(identity_token="fake.jwt.token", full_name=None)

        auth_router.login_with_apple(payload, db)

        assert not any(isinstance(obj, User) for obj in db.added)
        assert existing.nickname == "기존닉네임"

    def test_rejects_invalid_token(self, monkeypatch):
        monkeypatch.setattr(
            auth_router._apple_jwk_client,
            "get_signing_key_from_jwt",
            lambda token: type("SigningKey", (), {"key": "fake-key"})(),
        )
        monkeypatch.setattr(
            auth_router.jwt,
            "decode",
            lambda *a, **k: (_ for _ in ()).throw(jwt.InvalidSignatureError("bad sig")),
        )
        db = FakeSession()
        payload = AppleLoginRequest(identity_token="not-a-real-token")

        with pytest.raises(Exception) as exc_info:
            auth_router.login_with_apple(payload, db)

        assert exc_info.value.status_code == 401
