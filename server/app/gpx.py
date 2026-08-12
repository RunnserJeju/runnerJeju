"""GPX 파일 → 코스 경로 변환.

`verification.py`와 같은 이유로 순수 함수만 담는다. DB도 FastAPI도 모른다.
지금은 업로드 API가 유일한 호출자지만, 배치 임포트나 별도 도구에서도 그대로 쓴다.

다루는 GPX의 성격
-----------------
관리자가 경로 플래너(komoot/Outdooractive 계열)에서 **그려서 내보낸 경로**를
전제로 한다. 실제로 달린 기록이 아니라서 `<time>`이 없는 것이 정상이고, 점 간격도
초 단위가 아니라 수십 미터 단위다(사계해안도로 6.2km 예시는 207점, 평균 30m).

그래서 흔히 하는 다운샘플링(Douglas-Peucker)을 하지 않는다. 줄일 점이 애초에 없고,
오히려 성긴 쪽이 문제라 검증에서 점-대-선분 거리를 쓴다(`geo.distance_to_segment_meters`).
"""

import xml.etree.ElementTree as ET
from dataclasses import dataclass
from datetime import datetime

from app import geo

# 시작점과 끝점이 이 거리 안이면 순환 코스로 본다.
# 사계해안도로 예시는 10.5m다.
LOOP_THRESHOLD_METERS = 50.0

# 코스로 인정하는 최소 점 개수. 2점이면 직선 하나라 코스라 부르기 어렵다.
MIN_POINTS = 3

# 저장용 경로의 리샘플 간격(m). 러닝 기록(5m 필터)보다 성기고 검증 tolerance(30m)보다
# 촘촘해야 한다: 기록 간격 < 리샘플 간격 < tolerance. 자세한 배경은 resample_path 참고.
RESAMPLE_INTERVAL_METERS = 15.0


class GpxParseError(ValueError):
    """GPX를 코스로 만들 수 없을 때. message는 그대로 사용자에게 보여진다."""


@dataclass(frozen=True)
class TrackPoint:
    lat: float
    lng: float
    altitude: float | None = None
    recorded_at: datetime | None = None

    def to_json(self) -> dict:
        """`GeoPointSchema` / Flutter `GeoPoint.fromJson`과 같은 키를 쓴다."""
        payload: dict = {"lat": self.lat, "lng": self.lng}
        if self.altitude is not None:
            payload["altitude"] = self.altitude
        if self.recorded_at is not None:
            payload["recorded_at"] = self.recorded_at.isoformat()
        return payload


@dataclass(frozen=True)
class ParsedCourse:
    """GPX 한 개에서 뽑아낸, 코스로 저장할 수 있는 모든 것."""

    name: str | None
    points: list[TrackPoint]
    distance_meters: float
    elevation_gain_meters: float | None
    is_loop: bool

    # 균등 간격(RESAMPLE_INTERVAL_METERS)으로 다시 찍은 경로. DB에 저장되어
    # 지도 그리기와 검증 매칭률 계산에 쓰인다 — 매칭률이 "코스 거리의 몇 %"라는
    # 직관과 일치하려면 점 밀도가 균등해야 한다(geo.resample_path 참고).
    #
    # 점별 고도는 담지 않는다. 보간한 점의 고도는 계산해봐야 추정치이고,
    # 앱에서 점별 고도를 쓰는 곳이 없다(코스 고도는 elevation_gain_meters 하나로 충분).
    resampled_points: list[TrackPoint]

    @property
    def coordinates(self) -> list[geo.Point]:
        return [(p.lat, p.lng) for p in self.points]


def _local_name(tag: str) -> str:
    """'{http://...}trkpt' → 'trkpt'.

    GPX는 1.0과 1.1의 네임스페이스가 다르고, 네임스페이스를 아예 빼고 내보내는
    도구도 있다. 버전마다 분기하는 대신 태그 이름만 보고 처리한다.
    """
    return tag.rpartition("}")[2]


def _find_all(root: ET.Element, name: str) -> list[ET.Element]:
    return [el for el in root.iter() if _local_name(el.tag) == name]


def _find_child(parent: ET.Element, name: str) -> ET.Element | None:
    for child in parent:
        if _local_name(child.tag) == name:
            return child
    return None


def _parse_time(raw: str | None) -> datetime | None:
    if not raw:
        return None
    try:
        return datetime.fromisoformat(raw.strip())
    except ValueError:
        # 시각은 코스에 필수가 아니다. 못 읽으면 조용히 버린다.
        return None


def _parse_float(raw: str | None) -> float | None:
    if raw is None:
        return None
    try:
        return float(raw)
    except ValueError:
        return None


def _to_point(element: ET.Element) -> TrackPoint | None:
    """<trkpt> / <rtept> 하나를 TrackPoint로. 좌표가 없으면 None."""
    lat = _parse_float(element.get("lat"))
    lng = _parse_float(element.get("lon"))
    if lat is None or lng is None:
        return None

    ele_el = _find_child(element, "ele")
    time_el = _find_child(element, "time")

    # <ele>를 쓰고 비표준 originalElevation 속성은 무시한다. 플래너가 보정한
    # <ele> 쪽이 경로 전체에서 일관되기 때문이다.
    return TrackPoint(
        lat=lat,
        lng=lng,
        altitude=_parse_float(ele_el.text) if ele_el is not None else None,
        recorded_at=_parse_time(time_el.text) if time_el is not None else None,
    )


def _collect_points(root: ET.Element) -> list[TrackPoint]:
    """트랙 → 루트 → 웨이포인트 순으로 좌표를 찾는다.

    `<trk>`가 여러 개면 문서 순서대로 이어 붙인다. 플래너가 구간을 나눠 내보낸
    경우라 하나의 코스로 합치는 것이 맞다.
    """
    for tag in ("trkpt", "rtept", "wpt"):
        elements = _find_all(root, tag)
        if elements:
            return [p for p in (_to_point(el) for el in elements) if p is not None]
    return []


def _dedupe(points: list[TrackPoint]) -> list[TrackPoint]:
    """연속으로 같은 좌표가 반복되면 하나만 남긴다.

    플래너 출력에는 같은 점이 붙어 나오는 경우가 있다(사계해안도로 예시는 207점 중 22개).
    거리에도 그리기에도 기여하지 않으면서 검증 연산만 늘린다.
    """
    result: list[TrackPoint] = []
    for point in points:
        if result and result[-1].lat == point.lat and result[-1].lng == point.lng:
            continue
        result.append(point)
    return result


def _extract_name(root: ET.Element) -> str | None:
    """<metadata><name> 우선, 없으면 <trk><name>."""
    metadata = _find_child(root, "metadata")
    if metadata is not None:
        name_el = _find_child(metadata, "name")
        if name_el is not None and name_el.text and name_el.text.strip():
            return name_el.text.strip()

    for trk in _find_all(root, "trk"):
        name_el = _find_child(trk, "name")
        if name_el is not None and name_el.text and name_el.text.strip():
            return name_el.text.strip()

    return None


def parse(content: bytes) -> ParsedCourse:
    """GPX 바이트를 코스로 변환한다. 실패하면 GpxParseError."""
    try:
        # ElementTree가 XML 선언의 encoding을 읽으므로 bytes를 그대로 넘긴다.
        # 직접 디코딩하면 UTF-8이 아닌 파일에서 오히려 깨진다.
        root = ET.fromstring(content)
    except ET.ParseError as exc:
        raise GpxParseError(f"GPX 파일을 읽을 수 없어요: {exc}") from exc

    if _local_name(root.tag) != "gpx":
        raise GpxParseError("GPX 파일이 아니에요. 최상위 태그가 <gpx>여야 해요.")

    points = _dedupe(_collect_points(root))

    if len(points) < MIN_POINTS:
        raise GpxParseError(
            f"경로 좌표가 {len(points)}개뿐이라 코스로 쓸 수 없어요. "
            f"{MIN_POINTS}개 이상이어야 해요."
        )

    coordinates = [(p.lat, p.lng) for p in points]

    if not geo.is_within_jeju(coordinates):
        min_lat, min_lng, max_lat, max_lng = geo.bounds(coordinates)
        raise GpxParseError(
            "제주도 밖의 좌표가 들어 있어요 "
            f"(위도 {min_lat:.4f}~{max_lat:.4f}, 경도 {min_lng:.4f}~{max_lng:.4f})."
        )

    elevations = [p.altitude for p in points if p.altitude is not None]
    # 일부 점에만 고도가 있으면 누적 상승이 왜곡되므로 전부 있을 때만 계산한다.
    gain = (
        geo.elevation_gain_meters(elevations) if len(elevations) == len(points) else None
    )

    return ParsedCourse(
        name=_extract_name(root),
        points=points,
        distance_meters=geo.path_length_meters(coordinates),
        elevation_gain_meters=gain,
        is_loop=geo.distance_meters(coordinates[0], coordinates[-1])
        <= LOOP_THRESHOLD_METERS,
        resampled_points=[
            TrackPoint(lat=lat, lng=lng)
            for lat, lng in geo.resample_path(coordinates, RESAMPLE_INTERVAL_METERS)
        ],
    )
