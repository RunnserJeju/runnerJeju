"""요청 단위 의존성.

운영자용 가드(require_admin_session)는 app/admin/auth.py에 있다 — 세션·DB에
의존하고 admin 모듈에서만 쓰여 여기(앱 공용 의존성)와 분리했다.
"""

import uuid
from dataclasses import dataclass

import jwt
from fastapi import Depends, Header, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import get_db
from app.models import User
from app.security import decode_token
from app.user_log import PLATFORMS

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


def optional_user_id(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
) -> str | None:
    """토큰이 있으면 사용자 id, 없거나 유효하지 않으면 None. 행동 로그(POST /user-logs)처럼
    로그인 전에도 받아야 하는 요청용 — 401을 내지 않는다."""
    if credentials is None:
        return None
    try:
        payload = decode_token(credentials.credentials)
    except jwt.PyJWTError:
        return None
    if payload.get("type") != "access":
        return None
    return payload["sub"]


def current_user_is_admin(
    user_id: str = Depends(current_user_id),
    db: Session = Depends(get_db),
) -> bool:
    """요청자가 role='admin'인 앱 사용자인지. 토큰에 싣지 않고 매번 DB에서 본다 —
    role은 DB에서 직접 바꾸므로 토큰 만료를 기다리지 않고 바로 반영돼야 한다."""
    role = db.scalar(select(User.role).where(User.id == uuid.UUID(user_id)))
    return role == "admin"


@dataclass(frozen=True)
class ClientContext:
    """앱이 모든 요청에 헤더로 실어 보내는 문맥. 서버가 직접 남기는 user_log
    (코스 상세 조회 등)에 세션·플랫폼·앱 버전을 채우는 데 쓴다. 없으면 전부 None."""

    session_id: str | None = None
    platform: str | None = None
    app_version: str | None = None


def client_context(
    x_session_id: str | None = Header(default=None),
    x_platform: str | None = Header(default=None),
    x_app_version: str | None = Header(default=None),
) -> ClientContext:
    """X-Session-Id / X-Platform / X-App-Version 헤더를 읽는다(앱 ClientContextInterceptor).

    로그용 부가 정보라 검증 실패로 본 요청을 거절하지 않는다 — 길면 컬럼 폭에 맞춰
    자르고, platform은 허용값 밖이면 버린다(로그에 임의 문자열이 쌓이지 않게).
    """
    return ClientContext(
        session_id=_clip(x_session_id, 36),
        platform=x_platform if x_platform in PLATFORMS else None,
        app_version=_clip(x_app_version, 20),
    )


def _clip(value: str | None, max_length: int) -> str | None:
    return None if value is None else value[:max_length]
