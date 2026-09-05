import os
import uuid
from datetime import datetime, timezone

import httpx
import jwt
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import delete, select, update
from sqlalchemy.orm import Session

from app.db import get_db
from app.deps import current_user_id
from app.models import RefreshToken, Run, User
from app.schemas import (
    AccessTokenOut,
    AppleLoginRequest,
    GoogleLoginRequest,
    KakaoLoginRequest,
    NicknameUpdate,
    RefreshRequest,
    TokenPair,
    UserOut,
)
from app.security import (
    REFRESH_TOKEN_TTL,
    create_access_token,
    create_refresh_token,
    decode_token,
)

router = APIRouter(prefix="/auth", tags=["auth"])

KAKAO_USER_ME_URL = "https://kapi.kakao.com/v2/user/me"

APPLE_KEYS_URL = "https://appleid.apple.com/auth/keys"
APPLE_ISSUER = "https://appleid.apple.com"
# iOS 앱의 Bundle ID. identityToken의 aud 클레임이 이 값과 같아야 우리 앱 몫으로
# 발급된 토큰이라고 확신할 수 있다 (다른 앱용 토큰 재사용 방지).
APPLE_BUNDLE_ID = os.environ.get("APPLE_BUNDLE_ID", "com.runnersjeju.runnersJeju")

# 애플 공개키(JWKS)를 가져와 캐싱한다. 생성 시점엔 네트워크 호출을 하지 않고,
# 최초 검증 때 lazy하게 fetch한다.
_apple_jwk_client = jwt.PyJWKClient(APPLE_KEYS_URL)

GOOGLE_KEYS_URL = "https://www.googleapis.com/oauth2/v3/certs"
GOOGLE_ISSUERS = {"https://accounts.google.com", "accounts.google.com"}
# 구글 클라우드 콘솔의 "웹 애플리케이션" 클라이언트 ID. iOS/Android 앱 모두 로그인 시
# serverClientId로 이 값을 넘겨서, idToken의 aud가 플랫폼별로 갈리지 않고 이 값
# 하나로 고정되게 한다 — 그래야 서버가 aud 하나만 검증하면 된다.
GOOGLE_CLIENT_ID = os.environ.get(
    "GOOGLE_CLIENT_ID",
    "425895001003-ih0unh7qark9fa1sadp45g78cobjftob.apps.googleusercontent.com",
)

_google_jwk_client = jwt.PyJWKClient(GOOGLE_KEYS_URL)


def _issue_tokens(db: Session, user: User) -> TokenPair:
    # 로그인·재발급 시 최근 접속 시각을 남긴다(활성 이용자 통계·휴면 판정용).
    user.last_login_at = datetime.now(timezone.utc)
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
        needs_nickname=user.nickname is None,
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

    # 닉네임은 카카오 프로필 값을 그대로 쓰지 않는다 — 최초 로그인 후 앱에서 직접
    # 받는다(_issue_tokens의 needs_nickname). provider마다 제공 방식이 달라(카카오는
    # 매번, 애플은 최초 1회만) 동기화 로직을 따로 두는 대신 앱 내 값을 기준으로 삼는다.
    user.profile_image_url = profile.get("profile_image_url")
    # 이메일 동의항목이 꺼져 있거나 사용자가 거부했으면 안 내려온다 — 그럴 땐 기존 값 유지.
    email = (kakao_user.get("kakao_account") or {}).get("email")
    if email:
        user.email = email
    db.commit()
    db.refresh(user)

    return _issue_tokens(db, user)


@router.post("/apple", response_model=TokenPair)
def login_with_apple(payload: AppleLoginRequest, db: Session = Depends(get_db)):
    """iOS의 Sign in with Apple로 받은 identityToken을 검증한다.

    카카오와 달리 애플은 토큰 조회 API가 없다 — identityToken 자체가 애플이 서명한
    JWT이므로, 애플 공개키(JWKS)로 서명을 검증하고 aud/iss를 확인하는 방식으로
    대신한다. sub 클레임이 카카오의 id에 해당하는 안정적인 사용자 식별자다.
    """
    try:
        signing_key = _apple_jwk_client.get_signing_key_from_jwt(
            payload.identity_token
        )
        claims = jwt.decode(
            payload.identity_token,
            signing_key.key,
            algorithms=["RS256"],
            audience=APPLE_BUNDLE_ID,
            issuer=APPLE_ISSUER,
        )
    except jwt.PyJWTError:
        raise HTTPException(status_code=401, detail="애플 토큰 검증에 실패했어요.")

    apple_id = claims["sub"]

    user = db.scalar(select(User).where(User.apple_id == apple_id))
    if user is None:
        user = User(apple_id=apple_id)
        db.add(user)

    # identityToken의 email 클레임을 우선한다 — 구글처럼 서명이 검증된 값이라, 앱이
    # 임의로 채울 수 있는 payload.email보다 믿을 수 있다. payload.email은 클레임이
    # 없을 때(email 스코프 미동의)의 폴백이고, 둘 다 없으면 기존 값을 유지한다.
    # 닉네임은 (카카오와 마찬가지로) provider 값을 안 쓰고 앱에서 직접 받는다.
    email = claims.get("email") or payload.email
    if email:
        user.email = email
    db.commit()
    db.refresh(user)

    return _issue_tokens(db, user)


@router.post("/google", response_model=TokenPair)
def login_with_google(payload: GoogleLoginRequest, db: Session = Depends(get_db)):
    """Google Sign-In으로 받은 idToken을 검증한다.

    애플과 같은 방식이다 — idToken 자체가 구글이 서명한 JWT이므로, 구글 공개키
    (JWKS)로 서명을 검증하고 aud/iss를 확인한다. sub 클레임이 안정적인 사용자
    식별자다. 애플과 달리 email 클레임은 매 로그인마다 내려온다.
    """
    try:
        signing_key = _google_jwk_client.get_signing_key_from_jwt(payload.id_token)
        claims = jwt.decode(
            payload.id_token,
            signing_key.key,
            algorithms=["RS256"],
            audience=GOOGLE_CLIENT_ID,
        )
    except jwt.PyJWTError:
        raise HTTPException(status_code=401, detail="구글 토큰 검증에 실패했어요.")

    if claims.get("iss") not in GOOGLE_ISSUERS:
        raise HTTPException(status_code=401, detail="구글 토큰 검증에 실패했어요.")

    google_id = claims["sub"]

    user = db.scalar(select(User).where(User.google_id == google_id))
    if user is None:
        user = User(google_id=google_id)
        db.add(user)

    email = claims.get("email")
    if email:
        user.email = email
    db.commit()
    db.refresh(user)

    return _issue_tokens(db, user)


@router.get("/me", response_model=UserOut)
def get_me(
    user_id: str = Depends(current_user_id),
    db: Session = Depends(get_db),
):
    """현재 로그인한 사용자. 앱이 admin 전용 UI 노출 여부를 정하는 데 쓴다."""
    user = db.get(User, uuid.UUID(user_id))
    if user is None:
        raise HTTPException(status_code=404, detail="사용자를 찾을 수 없어요.")

    return user


@router.patch("/nickname", status_code=204)
def update_nickname(
    payload: NicknameUpdate,
    user_id: str = Depends(current_user_id),
    db: Session = Depends(get_db),
):
    """로그인 직후(닉네임 없을 때) 앱이 보여주는 닉네임 설정 화면에서 호출한다."""
    user = db.get(User, uuid.UUID(user_id))
    if user is None:
        raise HTTPException(status_code=404, detail="사용자를 찾을 수 없어요.")

    user.nickname = payload.nickname
    db.commit()


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

    # 탈퇴(익명화)된 계정이면 재발급을 막는다. 탈퇴 시 refresh 토큰을 지우므로 보통
    # 위에서 stored=None으로 걸리지만, 혹시 남아 있어도 여기서 한 번 더 차단한다.
    user = db.get(User, stored.user_id)
    if user is None or user.deleted_at is not None:
        raise HTTPException(status_code=401, detail="다시 로그인해 주세요.")

    # 최근 접속 시각 갱신(활성 이용자 통계용).
    user.last_login_at = datetime.now(timezone.utc)
    db.commit()

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


@router.delete("/me", status_code=204)
def withdraw(
    user_id: str = Depends(current_user_id),
    db: Session = Depends(get_db),
):
    """회원 탈퇴. 신원/PII를 익명화(스크럽)하고 세션을 폐기한다.

    hard delete가 아니라 soft delete + 익명화다 — users 행은 남기되 개인식별 정보를
    전부 지우고 deleted_at을 찍는다. 활동(완주·찜)은 익명 상태로 보존해 코스 통계의
    역사적 누적을 유지한다(단 러닝 GPS 경로는 위치정보라 제거한다).

    provider id를 null로 밀어 재로그인 시 새 계정이 생기게 한다. 멱등하다 — 이미
    탈퇴했거나 없는 계정이면 조용히 204.

    NOTE: 소셜 provider 토큰 revoke(Apple 등)는 아직 하지 않는다. provider 토큰을
    저장하지 않아 별도 작업이 필요하다(Apple 프로덕션 출시 전 추가).
    """
    user = db.get(User, uuid.UUID(user_id))
    if user is None or user.deleted_at is not None:
        return  # 이미 없거나 탈퇴한 계정 — 멱등

    # ① PII 스크럽 + 탈퇴 마커. provider id를 지워 재로그인=새 계정이 되게 한다.
    user.email = None
    user.nickname = None
    user.profile_image_url = None
    user.kakao_id = None
    user.apple_id = None
    user.google_id = None
    user.deleted_at = datetime.now(timezone.utc)

    # ② 세션 폐기 — refresh 토큰 전부 삭제(모든 기기 로그아웃 + users FK 해소).
    db.execute(delete(RefreshToken).where(RefreshToken.user_id == user.id))

    # ③ 러닝 GPS 경로 제거(위치정보=개인정보). 거리·시간·course_id 메타는 익명
    #    활동으로 남겨 통계에 쓴다. 완주(stamps)·찜(favorites)은 그대로 둔다.
    db.execute(update(Run).where(Run.user_id == str(user.id)).values(path=[]))

    db.commit()
