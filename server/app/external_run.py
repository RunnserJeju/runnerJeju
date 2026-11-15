"""가민·순토 공개 활동 링크에서 달린 경로를 받아 온다.

**DB도 FastAPI도 모른다** — URL을 받아 좌표·시작 시각·거리를 돌려줄 뿐이다. 두 서비스의
비공식 경로에 기대므로 깨지면 여기만 고친다(판정·보상은 routers/external_completions).

서버가 실제로 부르는 주소는 사용자가 준 URL이 아니라 거기서 뽑은 id로 조립한 것뿐이다.
"""

import re
from dataclasses import dataclass
from datetime import datetime, timezone

import httpx

from app.verification import Point

GARMIN = "garmin"
SUUNTO = "suunto"

TIMEOUT_SEC = 15.0
_USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
)

_GARMIN_URL = re.compile(r"^https?://connect\.garmin\.com/(?:(?:modern|app)/)?activity/(\d{1,20})(?:[/?#].*)?$")
_SUUNTO_URL = re.compile(
    r"^https?://maps\.suunto\.com/move/([A-Za-z0-9_.-]{1,60})/([0-9a-f]{24})(?:[/?#].*)?$"
)
_GARMIN_CSRF = re.compile(r'<meta name="csrf-token" content="([^"]+)"')


@dataclass(frozen=True)
class ActivityRef:
    source: str
    # 서비스 안에서 활동을 가리키는 id. 같은 활동의 중복 제출을 이걸로 막는다.
    activity_id: str
    # 순토만: 주소에 든 사용자 이름.
    user: str | None = None


@dataclass(frozen=True)
class ExternalRun:
    points: list[Point]
    started_at: datetime | None
    distance_meters: float | None


class ExternalRunError(Exception):
    """받아 오지 못했다. message는 사용자에게 그대로 보여준다."""

    def __init__(self, code: str, message: str):
        super().__init__(message)
        # unavailable(비공개·삭제) | no_route(좌표 없음) | provider_error(차단·장애·형식 변경)
        self.code = code
        self.message = message


def parse_url(url: str) -> ActivityRef | None:
    """지원하는 활동 링크면 어느 서비스의 어떤 활동인지. 아니면 None."""
    url = url.strip()
    if m := _GARMIN_URL.match(url):
        return ActivityRef(GARMIN, m.group(1))
    if m := _SUUNTO_URL.match(url):
        return ActivityRef(SUUNTO, m.group(2), user=m.group(1))
    return None


def fetch(ref: ActivityRef) -> ExternalRun:
    try:
        run = _fetch_garmin(ref) if ref.source == GARMIN else _fetch_suunto(ref)
    except ExternalRunError:
        raise
    except httpx.HTTPError as e:
        raise _provider_error(f"{type(e).__name__}") from e
    except (KeyError, TypeError, ValueError) as e:
        # 응답 모양이 바뀌었다.
        raise _provider_error(f"parse {type(e).__name__}: {e}") from e
    if len(run.points) < 2:
        raise ExternalRunError("no_route", "이 기록에는 경로(GPS)가 없어요.")
    return run


def _provider_error(reason: str) -> ExternalRunError:
    return ExternalRunError(
        "provider_error", f"기록을 불러오지 못했어요. 잠시 후 다시 시도해 주세요. ({reason})"
    )


def _unavailable() -> ExternalRunError:
    return ExternalRunError(
        "unavailable", "기록을 볼 수 없어요. 링크가 맞는지, 공개된 기록인지 확인해 주세요."
    )


def _client() -> httpx.Client:
    return httpx.Client(
        headers={"User-Agent": _USER_AGENT}, timeout=TIMEOUT_SEC, follow_redirects=True
    )


# --- 순토 -----------------------------------------------------------------


def _fetch_suunto(ref: ActivityRef) -> ExternalRun:
    with _client() as client:
        response = client.get(f"https://maps.suunto.com/api/camera/{ref.user}/{ref.activity_id}")
    if response.status_code in (401, 403, 404):
        raise _unavailable()
    response.raise_for_status()
    workout = response.json().get("workout")
    if not workout:
        raise _unavailable()
    return ExternalRun(
        points=decode_polyline(workout.get("polyline") or ""),
        started_at=_from_epoch_ms(workout.get("startTime")),
        distance_meters=_to_float(workout.get("totalDistance")),
    )


# --- 가민 -----------------------------------------------------------------


def _fetch_garmin(ref: ActivityRef) -> ExternalRun:
    """활동 페이지에서 CSRF 토큰·쿠키를 받고 같은 세션으로 상세를 부른다.
    토큰 헤더와 Sec-Fetch-Site가 없으면 Cloudflare가 403, 쿠키가 없으면 401을 준다."""
    base = "https://connect.garmin.com"
    with _client() as client:
        page = client.get(f"{base}/modern/activity/{ref.activity_id}")
        page.raise_for_status()
        token = _GARMIN_CSRF.search(page.text)
        if token is None:
            raise _provider_error("csrf")
        headers = {
            "connect-csrf-token": token.group(1),
            "Sec-Fetch-Site": "same-origin",
            "Accept": "application/json",
            "Referer": f"{base}/modern/activity/{ref.activity_id}",
        }
        api = f"{base}/gc-api/activity-service/activity/{ref.activity_id}"
        details = client.get(f"{api}/details", headers=headers)
        if details.status_code in (401, 403, 404):
            # 비공개 활동도 이렇게 온다. 차단(Cloudflare)과는 본문으로 못 가른다.
            raise _unavailable()
        details.raise_for_status()
        polyline = (details.json().get("geoPolylineDTO") or {}).get("polyline") or []
        points = [
            (float(p["lat"]), float(p["lon"]))
            for p in polyline
            if p.get("lat") is not None and p.get("lon") is not None
        ]
        started_at = _from_epoch_ms(polyline[0].get("time")) if polyline else None

        # 거리는 요약에만 있다. 못 받아도 인증은 진행한다(저장용 정보).
        distance = None
        summary = client.get(api, headers=headers)
        if summary.status_code == 200:
            dto = summary.json().get("summaryDTO") or {}
            distance = _to_float(dto.get("distance"))
            started_at = started_at or _from_iso_utc(dto.get("startTimeGMT"))
    return ExternalRun(points=points, started_at=started_at, distance_meters=distance)


# --- 공통 -----------------------------------------------------------------


def decode_polyline(encoded: str, precision: int = 5) -> list[Point]:
    """구글 인코딩 폴리라인 → [(lat, lng)]."""
    factor = 10**precision
    points: list[Point] = []
    index = lat = lng = 0
    while index < len(encoded):
        delta = []
        for _ in range(2):
            shift = result = 0
            while True:
                byte = ord(encoded[index]) - 63
                index += 1
                result |= (byte & 0x1F) << shift
                shift += 5
                if byte < 0x20:
                    break
            delta.append(~(result >> 1) if result & 1 else result >> 1)
        lat += delta[0]
        lng += delta[1]
        points.append((lat / factor, lng / factor))
    return points


def _to_float(value) -> float | None:
    try:
        return None if value is None else float(value)
    except (TypeError, ValueError):
        return None


def _from_epoch_ms(value) -> datetime | None:
    ms = _to_float(value)
    return None if ms is None else datetime.fromtimestamp(ms / 1000, tz=timezone.utc)


def _from_iso_utc(value) -> datetime | None:
    if not value:
        return None
    try:
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
