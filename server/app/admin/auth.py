"""운영자 세션 로그인 — 로그인/로그아웃/세션확인 + /admin/* 접근 가드.

공유 API 키(옛 require_admin_key) 방식을 대체한다. 운영자가 아이디/비밀번호로
로그인하면 서버가 세션을 만들고 HttpOnly 쿠키를 내려준다. 이후 /admin/* 요청은
브라우저가 쿠키를 자동으로 실어 보내고, require_admin_session이 그 세션을 확인한다.

로그인 엔드포인트는 세션이 없어도 닿아야 하므로(닭-달걀) 이 라우터는 admin_router의
가드 밖에 둔다(app/admin/__init__.py). 앱 사용자 JWT 흐름과는 완전히 독립이다.
"""

import secrets
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.admin.security import (
    SESSION_COOKIE_NAME,
    SESSION_COOKIE_PATH,
    SESSION_TTL,
    hash_password,
    hash_session_token,
    new_session_token,
    session_cookie_secure,
    verify_password,
)
from app.db import get_db
from app.models import AdminSession, AdminUser
from app.schemas import AdminIdentityOut, AdminLoginRequest

router = APIRouter(prefix="/admin/auth", tags=["admin-auth"])

# 존재하지 않는 아이디로 로그인해도 bcrypt 검증을 한 번은 돌려, "아이디가 있는지"가
# 응답 시간으로 새지 않게 한다(사용자 열거 방지). 임의 비밀번호의 해시라 절대 안 맞는다.
_DUMMY_PASSWORD_HASH = hash_password(secrets.token_urlsafe(16))


def _get_admin_by_username(db: Session, username: str) -> AdminUser | None:
    return db.execute(
        select(AdminUser).where(AdminUser.username == username)
    ).scalar_one_or_none()


def _get_session_by_token_hash(db: Session, token_hash: str) -> AdminSession | None:
    return db.execute(
        select(AdminSession).where(AdminSession.token_hash == token_hash)
    ).scalar_one_or_none()


def _set_session_cookie(response: Response, raw_token: str) -> None:
    response.set_cookie(
        key=SESSION_COOKIE_NAME,
        value=raw_token,
        max_age=int(SESSION_TTL.total_seconds()),
        path=SESSION_COOKIE_PATH,
        httponly=True,  # JS가 못 읽음 — XSS로 세션 토큰이 새는 걸 막는다.
        secure=session_cookie_secure(),  # 운영(HTTPS) 기본 켜짐, 로컬만 끔.
        samesite="strict",  # 타 사이트발 요청엔 쿠키를 안 실음 — CSRF 방어.
    )


def require_admin_session(
    request: Request, db: Session = Depends(get_db)
) -> AdminUser:
    """세션 쿠키를 확인하고 운영자를 돌려준다. 무효하면 401.

    admin_router에 dependencies로 걸면 반환값은 버려지고 통과 여부만 쓰인다.
    GET /admin/auth/me처럼 "누구인지"가 필요한 곳은 반환된 AdminUser를 받아 쓴다.
    """
    token = request.cookies.get(SESSION_COOKIE_NAME)
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="로그인이 필요해요."
        )

    session = _get_session_by_token_hash(db, hash_session_token(token))
    now = datetime.now(timezone.utc)
    if session is None or session.revoked_at is not None or session.expires_at <= now:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="세션이 만료됐어요. 다시 로그인해 주세요.",
        )

    admin = db.get(AdminUser, session.admin_user_id)
    if admin is None or admin.disabled_at is not None:
        # 세션은 살아있어도 계정이 비활성화됐으면 막는다(즉시 차단).
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="사용할 수 없는 계정이에요.",
        )
    return admin


@router.post("/login", response_model=AdminIdentityOut)
def login(
    payload: AdminLoginRequest, response: Response, db: Session = Depends(get_db)
):
    admin = _get_admin_by_username(db, payload.username)

    # 아이디가 없거나 비활성이어도 더미 해시로 항상 한 번은 검증한다(타이밍 평탄화).
    active = admin is not None and admin.disabled_at is None
    password_hash = admin.password_hash if active else _DUMMY_PASSWORD_HASH
    if not verify_password(payload.password, password_hash) or not active:
        # 어느 실패든 같은 메시지 — 아이디 존재 여부를 흘리지 않는다.
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="아이디 또는 비밀번호가 올바르지 않아요.",
        )

    raw_token = new_session_token()
    db.add(
        AdminSession(
            admin_user_id=admin.id,
            token_hash=hash_session_token(raw_token),
            expires_at=datetime.now(timezone.utc) + SESSION_TTL,
        )
    )
    db.commit()

    _set_session_cookie(response, raw_token)
    return AdminIdentityOut(username=admin.username, display_name=admin.display_name)


@router.post("/logout")
def logout(request: Request, response: Response, db: Session = Depends(get_db)):
    """현재 세션을 폐기하고 쿠키를 지운다. 쿠키가 없어도 조용히 성공한다(멱등)."""
    token = request.cookies.get(SESSION_COOKIE_NAME)
    if token:
        session = _get_session_by_token_hash(db, hash_session_token(token))
        if session is not None and session.revoked_at is None:
            session.revoked_at = datetime.now(timezone.utc)
            db.commit()

    # delete는 set과 path/secure/samesite가 맞아야 브라우저가 지운다.
    response.delete_cookie(
        key=SESSION_COOKIE_NAME,
        path=SESSION_COOKIE_PATH,
        httponly=True,
        secure=session_cookie_secure(),
        samesite="strict",
    )
    return {"ok": True}


@router.get("/me", response_model=AdminIdentityOut)
def me(admin: AdminUser = Depends(require_admin_session)):
    """현재 로그인 상태. 세션이 없으면 가드가 401을 던진다 — 프론트가 이걸로
    로그인 화면 노출 여부를 판단한다."""
    return AdminIdentityOut(username=admin.username, display_name=admin.display_name)
