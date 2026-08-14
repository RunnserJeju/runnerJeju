"""JWT 발급/검증 유틸.

SECRET_KEY는 반드시 환경변수(JWT_SECRET_KEY)로 덮어써야 한다. 기본값을 남겨두는
건 테스트가 환경변수 없이 이 모듈을 임포트할 수 있게 하려는 것뿐이고, 이 값으로
서버가 뜨는 일은 app.config_guard가 기동 시점에 막는다.
"""

import os
import uuid
from datetime import datetime, timedelta, timezone

import jwt

INSECURE_DEFAULT_SECRET = "dev-only-insecure-secret-change-me"

SECRET_KEY = os.environ.get("JWT_SECRET_KEY", INSECURE_DEFAULT_SECRET)
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
