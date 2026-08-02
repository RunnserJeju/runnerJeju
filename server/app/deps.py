"""요청 단위 의존성."""

import uuid

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
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


def require_admin(
    user_id: str = Depends(current_user_id),
    db: Session = Depends(get_db),
) -> str:
    """current_user_id에 더해 role이 admin인지 확인한다. 관리자 전용 엔드포인트에 쓴다."""
    user = db.get(User, uuid.UUID(user_id))
    if user is None or user.role != "admin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail="관리자만 사용할 수 있어요."
        )

    return user_id
