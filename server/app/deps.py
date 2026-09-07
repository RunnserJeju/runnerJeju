"""요청 단위 의존성.

운영자용 가드(require_admin_session)는 app/admin/auth.py에 있다 — 세션·DB에
의존하고 admin 모듈에서만 쓰여 여기(앱 공용 의존성)와 분리했다.
"""

import uuid

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import get_db
from app.models import User
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


def current_user_is_admin(
    user_id: str = Depends(current_user_id),
    db: Session = Depends(get_db),
) -> bool:
    """요청자가 role='admin'인 앱 사용자인지. 토큰에 싣지 않고 매번 DB에서 본다 —
    role은 DB에서 직접 바꾸므로 토큰 만료를 기다리지 않고 바로 반영돼야 한다."""
    role = db.scalar(select(User.role).where(User.id == uuid.UUID(user_id)))
    return role == "admin"
