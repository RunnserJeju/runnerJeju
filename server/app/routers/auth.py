import uuid
from datetime import datetime, timezone

import httpx
import jwt
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import get_db
from app.models import RefreshToken, User
from app.schemas import AccessTokenOut, KakaoLoginRequest, RefreshRequest, TokenPair
from app.security import (
    REFRESH_TOKEN_TTL,
    create_access_token,
    create_refresh_token,
    decode_token,
)

router = APIRouter(prefix="/auth", tags=["auth"])

KAKAO_USER_ME_URL = "https://kapi.kakao.com/v2/user/me"


def _issue_tokens(db: Session, user: User) -> TokenPair:
    token_id = uuid.uuid4()
    db.add(
        RefreshToken(
            id=token_id,
            user_id=user.id,
            expires_at=datetime.now(timezone.utc) + REFRESH_TOKEN_TTL,
        )
    )
    db.commit()

    return TokenPair(
        access_token=create_access_token(user.id),
        refresh_token=create_refresh_token(user.id, token_id),
    )


@router.post("/kakao", response_model=TokenPair)
def login_with_kakao(payload: KakaoLoginRequest, db: Session = Depends(get_db)):
    """앱에서 카카오 SDK로 로그인해 받은 accessToken을 카카오 서버에 그대로 조회해 검증한다."""
    try:
        response = httpx.get(
            KAKAO_USER_ME_URL,
            headers={"Authorization": f"Bearer {payload.access_token}"},
            timeout=5.0,
        )
        response.raise_for_status()
    except httpx.HTTPError:
        raise HTTPException(status_code=401, detail="카카오 토큰 검증에 실패했어요.")

    kakao_user = response.json()
    kakao_id = str(kakao_user["id"])
    profile = (kakao_user.get("kakao_account") or {}).get("profile") or {}

    user = db.scalar(select(User).where(User.kakao_id == kakao_id))
    if user is None:
        user = User(kakao_id=kakao_id)
        db.add(user)

    user.nickname = profile.get("nickname")
    user.profile_image_url = profile.get("profile_image_url")
    db.commit()
    db.refresh(user)

    return _issue_tokens(db, user)


@router.post("/refresh", response_model=AccessTokenOut)
def refresh_access_token(payload: RefreshRequest, db: Session = Depends(get_db)):
    """refresh token으로 access token만 재발급한다.

    refresh token rotation은 아직 정책 미정이라(docs/mvp.md 참고) 여기서는 하지 않는다 —
    같은 refresh token을 만료/로그아웃 전까지 계속 쓸 수 있다.
    """
    try:
        decoded = decode_token(payload.refresh_token)
    except jwt.PyJWTError:
        raise HTTPException(status_code=401, detail="다시 로그인해 주세요.")

    if decoded.get("type") != "refresh":
        raise HTTPException(status_code=401, detail="다시 로그인해 주세요.")

    stored = db.get(RefreshToken, uuid.UUID(decoded["jti"]))
    if (
        stored is None
        or stored.revoked_at is not None
        or stored.expires_at < datetime.now(timezone.utc)
    ):
        raise HTTPException(status_code=401, detail="다시 로그인해 주세요.")

    return AccessTokenOut(access_token=create_access_token(stored.user_id))


@router.post("/logout", status_code=204)
def logout(payload: RefreshRequest, db: Session = Depends(get_db)):
    """refresh token을 폐기한다. 이미 무효한 토큰이면 조용히 넘어간다."""
    try:
        decoded = decode_token(payload.refresh_token)
    except jwt.PyJWTError:
        return

    jti = decoded.get("jti")
    if jti is None:
        return

    stored = db.get(RefreshToken, uuid.UUID(jti))
    if stored is not None and stored.revoked_at is None:
        stored.revoked_at = datetime.now(timezone.utc)
        db.commit()
