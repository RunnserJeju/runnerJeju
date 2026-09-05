"""운영자 인증의 순수 유틸 — 비밀번호 해시, 세션 토큰, 쿠키 설정.

FastAPI에 의존하지 않는다(app/admin/auth.py가 이걸 엮어 라우터를 만든다). 앱
사용자 JWT(app/security.py)와도 완전히 별개다 — 운영자는 아이디/비밀번호로
로그인하고, 앱 사용자는 소셜 로그인이라 비밀번호 자체가 없다.
"""

import hashlib
import os
import secrets
from datetime import timedelta

import bcrypt

# ── 비밀번호 ──────────────────────────────────────────────
# bcrypt는 비밀번호를 72바이트까지만 본다. 그 이상은 5.0부터 조용히 자르지 않고
# ValueError를 던진다 — 시드(tools/create_admin.py)에서 미리 막고, 로그인은
# verify_password가 예외를 삼켜 "불일치"로 처리한다.
BCRYPT_MAX_PASSWORD_BYTES = 72


def hash_password(password: str) -> str:
    """평문 비밀번호 → bcrypt 해시(60자). 저장 전 단 한 번 호출한다."""
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("ascii")


def verify_password(password: str, password_hash: str) -> bool:
    """평문과 해시를 상수시간 비교. 형식이 깨졌거나 72바이트 초과면 조용히 False."""
    try:
        return bcrypt.checkpw(
            password.encode("utf-8"), password_hash.encode("ascii")
        )
    except ValueError:
        # 해시가 손상됐거나(Invalid salt) 입력이 72바이트를 넘을 때. 어느 쪽이든
        # 인증 실패로 취급한다 — 여기서 터뜨리면 로그인 자체가 500이 된다.
        return False


# ── 세션 토큰 ─────────────────────────────────────────────
# 쿠키엔 원본 토큰, DB엔 그 sha256 해시만 저장한다(비밀번호와 같은 논리 — DB가
# 유출돼도 원본 토큰은 드러나지 않아 세션을 곧바로 탈취당하지 않는다).
SESSION_TOKEN_BYTES = 32


def new_session_token() -> str:
    """쿠키에 실을 불투명 랜덤 토큰(원본). URL-safe base64라 쿠키에 그대로 넣는다."""
    return secrets.token_urlsafe(SESSION_TOKEN_BYTES)


def hash_session_token(token: str) -> str:
    """DB에 저장/조회할 토큰 해시(sha256 hex, 64자)."""
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


# ── 쿠키/세션 설정 ────────────────────────────────────────
SESSION_COOKIE_NAME = "admin_session"
# 쿠키는 /admin 아래에서만 전송된다 — 정적 SPA(/admin-ui)나 앱 API(/auth 등)엔
# 실리지 않는다. 보호 대상 엔드포인트가 전부 /admin/* 아래라 이 범위로 충분하다.
SESSION_COOKIE_PATH = "/admin"
# 12시간이면 하루 운영 세션으로 충분하고, 자리를 비운 사이 방치된 세션도 곧 만료된다.
SESSION_TTL = timedelta(hours=12)


def session_cookie_secure() -> bool:
    """Secure 쿠키(HTTPS 전용) 여부. 운영은 HTTPS라 기본 켜짐 — 로컬(http)에서만
    SESSION_COOKIE_SECURE=false로 꺼야 쿠키가 저장된다."""
    return os.environ.get("SESSION_COOKIE_SECURE", "true").lower() != "false"
