"""요청 단위 의존성."""

import os
import secrets

import jwt
from fastapi import Depends, Header, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.security import decode_token

_bearer = HTTPBearer(auto_error=False)


def current_user_id(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
) -> str:
    """현재 요청자의 사용자 id. `Authorization: Bearer <access token>` 헤더가 필요하다."""
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="로그인이 필요해요."
        )

    try:
        payload = decode_token(credentials.credentials)
    except jwt.PyJWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="유효하지 않은 토큰이에요."
        )

    if payload.get("type") != "access":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="유효하지 않은 토큰이에요."
        )

    return payload["sub"]


def require_admin_key(
    api_key: str | None = Header(default=None, alias="X-Admin-Api-Key"),
) -> None:
    """운영자 API 키를 확인한다. `X-Admin-Api-Key` 헤더가 `ADMIN_API_KEY`와 일치해야 한다.

    운영 웹의 잠정 인증이다 — 세션 로그인(docs/admin-web.md 4단계)이 준비되면
    이 함수만 교체한다. 앱의 JWT 흐름(current_user_id)과는 완전히 독립.
    """
    expected = os.environ.get("ADMIN_API_KEY", "")
    if not expected:
        # config_guard가 기동을 거부하지만, 그 경로를 우회해 떴을 때의 이중 방어.
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="서버에 관리자 키가 설정되지 않았어요.",
        )

    if api_key is None or not secrets.compare_digest(api_key, expected):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="유효한 관리자 API 키가 필요해요.",
        )
