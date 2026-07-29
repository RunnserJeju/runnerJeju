"""JWT 발급/검증 유틸.

SECRET_KEY는 반드시 환경변수(JWT_SECRET_KEY)로 덮어써야 한다.
기본값은 로컬 개발 편의용이고 운영에 쓰면 안 된다.
"""

import os
import uuid
from datetime import datetime, timedelta, timezone

import jwt

SECRET_KEY = os.environ.get("JWT_SECRET_KEY", "dev-only-insecure-secret-change-me")
ALGORITHM = "HS256"

ACCESS_TOKEN_TTL = timedelta(hours=1)
REFRESH_TOKEN_TTL = timedelta(days=30)


def create_access_token(user_id: uuid.UUID) -> str:
    now = datetime.now(timezone.utc)
    payload = {
        "sub": str(user_id),
        "type": "access",
        "iat": now,
        "exp": now + ACCESS_TOKEN_TTL,
    }
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


def create_refresh_token(user_id: uuid.UUID, token_id: uuid.UUID) -> str:
    now = datetime.now(timezone.utc)
    payload = {
        "sub": str(user_id),
        "type": "refresh",
        "jti": str(token_id),
        "iat": now,
        "exp": now + REFRESH_TOKEN_TTL,
    }
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


def decode_token(token: str) -> dict:
    """서명/만료만 검증해서 페이로드를 돌려준다. 무효하면 jwt.PyJWTError를 던진다."""
    return jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
