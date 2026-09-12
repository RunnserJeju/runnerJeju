"""Sign in with Apple 서버 연동 — authorization code → refresh 토큰 교환, 토큰 폐기.

앱스토어 계정 삭제 요건: 탈퇴 시 Apple 쪽 연결도 끊어야 한다(REST API로 revoke).
revoke에는 Apple이 준 refresh 토큰이 필요하고, 그 토큰은 로그인 때 받은
authorization code를 여기서 교환해야만 얻는다. 두 호출 모두 client_secret이
필요한데, 이는 Apple 개발자 콘솔의 .p8 키로 서명한 JWT다.

환경변수(없으면 비활성 — 로그인은 되지만 refresh 토큰을 저장하지 않는다):
  APPLE_TEAM_ID      Apple Developer 팀 ID (예: G92RR9396W)
  APPLE_KEY_ID       Sign in with Apple 키의 Key ID (10자)
  APPLE_PRIVATE_KEY  .p8 파일 내용(PEM). 한 줄 env면 \\n 이스케이프 허용.
"""

import logging
import os
import time

import httpx
import jwt

logger = logging.getLogger(__name__)

APPLE_TOKEN_URL = "https://appleid.apple.com/auth/token"
APPLE_REVOKE_URL = "https://appleid.apple.com/auth/revoke"
APPLE_AUDIENCE = "https://appleid.apple.com"

# client_secret 유효기간. Apple 최대는 6개월이지만 요청마다 새로 만들므로 짧게 둔다.
_CLIENT_SECRET_TTL = 300


class AppleAuthError(RuntimeError):
    """Apple 토큰 API 호출 실패(네트워크·설정 오류). 호출자가 재시도 가능하게 올린다."""


def _env(name: str) -> str:
    return os.environ.get(name, "").strip()


def is_configured() -> bool:
    return bool(_env("APPLE_TEAM_ID") and _env("APPLE_KEY_ID") and _env("APPLE_PRIVATE_KEY"))


def _private_key() -> str:
    # Secret Manager/.env에 한 줄로 넣으면 개행이 \n 문자열로 들어온다.
    return _env("APPLE_PRIVATE_KEY").replace("\\n", "\n")


def make_client_secret(client_id: str) -> str:
    """Apple 토큰 API용 client_secret(ES256 JWT)."""
    now = int(time.time())
    return jwt.encode(
        {
            "iss": _env("APPLE_TEAM_ID"),
            "iat": now,
            "exp": now + _CLIENT_SECRET_TTL,
            "aud": APPLE_AUDIENCE,
            "sub": client_id,
        },
        _private_key(),
        algorithm="ES256",
        headers={"kid": _env("APPLE_KEY_ID")},
    )


def exchange_code(client_id: str, authorization_code: str) -> str:
    """authorization code를 refresh 토큰으로 바꾼다. 실패하면 AppleAuthError."""
    try:
        resp = httpx.post(
            APPLE_TOKEN_URL,
            data={
                "client_id": client_id,
                "client_secret": make_client_secret(client_id),
                "code": authorization_code,
                "grant_type": "authorization_code",
            },
            timeout=10,
        )
    except httpx.HTTPError as e:
        raise AppleAuthError(f"Apple 토큰 교환 요청 실패: {e}") from e

    if resp.status_code != 200:
        raise AppleAuthError(f"Apple 토큰 교환 거부 {resp.status_code}: {resp.text}")

    token = resp.json().get("refresh_token")
    if not token:
        raise AppleAuthError("Apple 토큰 응답에 refresh_token이 없어요.")
    return token


def revoke_refresh_token(client_id: str, refresh_token: str) -> None:
    """refresh 토큰을 폐기해 Apple 쪽 앱 연결을 끊는다.

    이미 무효한 토큰(사용자가 설정에서 먼저 끊은 경우 등)은 invalid_grant로 오는데,
    끊을 게 없다는 뜻이라 성공으로 본다. 그 외 실패는 AppleAuthError.
    """
    try:
        resp = httpx.post(
            APPLE_REVOKE_URL,
            data={
                "client_id": client_id,
                "client_secret": make_client_secret(client_id),
                "token": refresh_token,
                "token_type_hint": "refresh_token",
            },
            timeout=10,
        )
    except httpx.HTTPError as e:
        raise AppleAuthError(f"Apple 토큰 폐기 요청 실패: {e}") from e

    if resp.status_code == 200:
        return
    if resp.status_code == 400 and "invalid_grant" in resp.text:
        logger.info("Apple refresh 토큰이 이미 무효라 폐기를 건너뜀")
        return
    raise AppleAuthError(f"Apple 토큰 폐기 거부 {resp.status_code}: {resp.text}")
