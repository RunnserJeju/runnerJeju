"""FCM HTTP v1 발송. 토큰 하나에 요청 하나라 여러 건은 동시에 보낸다.

FCM_PROJECT_ID가 없으면 꺼진 상태다(로컬 기본). 인증은 Cloud Run 메타데이터 서버의 서비스 계정
토큰을 쓴다 — 키 파일이 없다. 로컬에서 실제로 보내 보려면 FCM_ACCESS_TOKEN에
`gcloud auth print-access-token` 값을 넣는다.
"""

import asyncio
import os
import time
from dataclasses import dataclass

import httpx

OK = "ok"
# 없는 토큰(앱 삭제·재설치). 지운다.
DEAD = "dead"
# 일시 오류. 나중에 다시 보낸다.
RETRY = "retry"
ERROR = "error"

CONCURRENCY = 100
TIMEOUT_SEC = 10.0
ANDROID_CHANNEL_ID = "default"

_METADATA_TOKEN_URL = (
    "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token"
)
_cached_token: tuple[str, float] | None = None


@dataclass(frozen=True)
class Message:
    token: str
    title: str
    body: str
    data: dict[str, str]


def project_id() -> str | None:
    return os.environ.get("FCM_PROJECT_ID") or None


def enabled() -> bool:
    return project_id() is not None


def _access_token() -> str:
    global _cached_token
    override = os.environ.get("FCM_ACCESS_TOKEN")
    if override:
        return override
    if _cached_token and _cached_token[1] > time.monotonic():
        return _cached_token[0]
    response = httpx.get(_METADATA_TOKEN_URL, headers={"Metadata-Flavor": "Google"}, timeout=3.0)
    response.raise_for_status()
    payload = response.json()
    # 만료 1분 전에 새로 받는다.
    _cached_token = (payload["access_token"], time.monotonic() + payload["expires_in"] - 60)
    return _cached_token[0]


def _headers() -> dict[str, str]:
    headers = {"Authorization": f"Bearer {_access_token()}"}
    # 사용자 계정 토큰(로컬)은 과금 프로젝트를 밝혀야 받아 준다.
    if os.environ.get("FCM_ACCESS_TOKEN"):
        headers["x-goog-user-project"] = project_id() or ""
    return headers


def _payload(message: Message) -> dict:
    return {
        "message": {
            "token": message.token,
            "notification": {"title": message.title, "body": message.body},
            "data": message.data,
            "android": {
                "priority": "HIGH",
                "notification": {"channel_id": ANDROID_CHANNEL_ID},
            },
            "apns": {"payload": {"aps": {"sound": "default"}}},
        }
    }


def classify(status_code: int, body: dict) -> tuple[str, str | None]:
    """FCM 응답을 OK/DEAD/RETRY/ERROR로. 두 번째 값은 사람이 볼 사유."""
    if status_code == 200:
        return OK, None
    error = body.get("error", {}) if isinstance(body, dict) else {}
    status = error.get("status", "")
    message = str(error.get("message", ""))[:150]
    detail_codes = {d.get("errorCode") for d in error.get("details", []) if isinstance(d, dict)}
    if status_code == 404 or "UNREGISTERED" in detail_codes:
        return DEAD, "unregistered"
    if status_code == 400 and "registration token" in message.lower():
        return DEAD, "invalid_token"
    if status_code in (429, 500, 503):
        return RETRY, f"{status_code} {status}".strip()
    return ERROR, f"{status_code} {status} {message}".strip()[:200]


async def _send_one(
    client: httpx.AsyncClient, url: str, gate: asyncio.Semaphore, message: Message
) -> tuple[str, str | None]:
    async with gate:
        try:
            response = await client.post(url, json=_payload(message))
        except httpx.HTTPError as error:
            return RETRY, type(error).__name__
    try:
        body = response.json()
    except ValueError:
        body = {}
    return classify(response.status_code, body)


async def _send_many(messages: list[Message]) -> list[tuple[str, str | None]]:
    url = f"https://fcm.googleapis.com/v1/projects/{project_id()}/messages:send"
    gate = asyncio.Semaphore(CONCURRENCY)
    limits = httpx.Limits(max_connections=CONCURRENCY, max_keepalive_connections=CONCURRENCY)
    async with httpx.AsyncClient(headers=_headers(), timeout=TIMEOUT_SEC, limits=limits) as client:
        return await asyncio.gather(*(_send_one(client, url, gate, m) for m in messages))


def send_all(messages: list[Message]) -> list[tuple[str, str | None]]:
    """messages와 같은 순서로 (결과, 사유). 동기 엔드포인트(스레드풀)에서 부른다."""
    if not messages:
        return []
    return asyncio.run(_send_many(messages))
