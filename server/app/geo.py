"""위경도 계산 유틸.

`verification.py`와 마찬가지로 순수 함수만 담는다. 다만 두 모듈을 서로 import하지는
않는다 — `verification.py`는 나중에 검증 서버로 통째로 떼어낼 파일이라 의존성을 하나도
갖지 않는 편이 낫고, 그래서 Haversine과 점-선분 거리 구현이 양쪽에 각각 있다.
수십 줄짜리 중복을 감수하고 그 파일의 이식성을 지키는 쪽을 택했다 (docs/architecture.md 참고).
"""

from math import asin, atan2, cos, degrees, radians, sin, sqrt

EARTH_RADIUS_METERS = 6_371_000

Point = tuple[float, float]

# 코스가 제주도 안에 있는지 보는 대략적인 경계. 엉뚱한 지역의 GPX가
# 코스로 등록되는 것을 막는 용도라 넉넉하게 잡았다(부속 도서 포함).
JEJU_MIN_LAT, JEJU_MAX_LAT = 33.0, 33.65
JEJU_MIN_LNG, JEJU_MAX_LNG = 126.0, 127.0


def distance_meters(a: Point, b: Point) -> float:
    """두 지점 사이의 대원 거리(m)."""
    lat1, lng1 = a
    lat2, lng2 = b

    d_lat = radians(lat2 - lat1)
    d_lng = radians(lng2 - lng1)

    h = (
        sin(d_lat / 2) ** 2
        + sin(d_lng / 2) ** 2 * cos(radians(lat1)) * cos(radians(lat2))
    )

    return 2 * EARTH_RADIUS_METERS * asin(min(1.0, sqrt(h)))


def path_length_meters(path: list[Point]) -> float:
    """경로 전체 길이(m). 점이 2개 미만이면 0."""
    return sum(distance_meters(path[i], path[i + 1]) for i in range(len(path) - 1))


def bounds(path: list[Point]) -> tuple[float, float, float, float]:
    """경로의 (min_lat, min_lng, max_lat, max_lng)."""
    lats = [p[0] for p in path]
    lngs = [p[1] for p in path]
    return min(lats), min(lngs), max(lats), max(lngs)


def is_within_jeju(path: list[Point]) -> bool:
    """경로의 모든 점이 제주 경계 안에 있는지."""
    return all(
        JEJU_MIN_LAT <= lat <= JEJU_MAX_LAT and JEJU_MIN_LNG <= lng <= JEJU_MAX_LNG
        for lat, lng in path
    )


def distance_to_segment_meters(point: Point, start: Point, end: Point) -> float:
    """점에서 선분 [start, end]까지의 최단 거리(m).

    코스 데이터는 점 사이가 성기다(사계해안도로 GPX는 평균 30m, 최장 252m 간격).
    "러너가 코스 위에 있는가"를 코스 *꼭짓점*과의 거리로만 재면, 긴 직선 구간
    한가운데를 정확히 달린 사람이 100m 넘게 벗어난 것으로 잡힌다. 그래서
    꼭짓점이 아니라 선분까지의 거리를 재야 한다.

    거리가 짧아 지역 평면 근사(위경도를 미터로 투영)로 계산한다. 수 km 범위에서
    오차는 무시할 수준이다.
    """
    # 위도 1도는 어디서나 약 111km, 경도 1도는 cos(위도)만큼 짧아진다.
    lat_ref = radians(start[0])
    m_per_deg_lat = 111_132.0
    m_per_deg_lng = 111_320.0 * cos(lat_ref)

    def to_xy(p: Point) -> tuple[float, float]:
        return (p[1] - start[1]) * m_per_deg_lng, (p[0] - start[0]) * m_per_deg_lat

    px, py = to_xy(point)
    ex, ey = to_xy(end)

    seg_len_sq = ex * ex + ey * ey
    if seg_len_sq == 0:
        # 선분이 한 점으로 붕괴한 경우.
        return sqrt(px * px + py * py)

    # 점을 선분에 투영한 위치(0이면 start, 1이면 end). 선분 밖이면 끝점으로 잘라낸다.
    t = max(0.0, min(1.0, (px * ex + py * ey) / seg_len_sq))
    dx, dy = px - t * ex, py - t * ey

    return sqrt(dx * dx + dy * dy)


def distance_to_path_meters(point: Point, path: list[Point]) -> float:
    """점에서 경로(꺾은선)까지의 최단 거리(m)."""
    if not path:
        return float("inf")
    if len(path) == 1:
        return distance_meters(point, path[0])

    return min(
        distance_to_segment_meters(point, path[i], path[i + 1])
        for i in range(len(path) - 1)
    )


def resample_path(path: list[Point], interval_meters: float) -> list[Point]:
    """경로를 따라 interval_meters 간격으로 점을 다시 찍는다.

    코스 GPX는 사람이 그린 것이라 점 밀도가 불균등하다(곡선은 촘촘, 직선은 성김 —
    사계해안도로는 평균 30m, 최장 252m). 이대로 "커버된 점 개수 비율"을 매칭률로
    쓰면 점이 몰린 구간에 가중치가 쏠려서, 사용자가 이해하는 "코스 거리의 몇 %"와
    어긋난다. 균등 간격으로 리샘플링하면 점 개수 비율이 곧 거리 비율이 된다.

    새 점은 원본 꺾은선 위에 놓인다(두 점 사이 선형 보간 — 수십 m 간격에서
    구면 오차는 무시할 수준). 시작점과 끝점은 원본 그대로 보존하므로 순환 판정과
    시작/종료 지점 확인에 그대로 쓸 수 있다. 마지막 구간만 interval보다 짧을 수 있다.
    """
    if interval_meters <= 0:
        raise ValueError("interval_meters는 양수여야 한다.")
    if len(path) < 2:
        return list(path)

    result = [path[0]]
    # 직전에 찍은 점 이후로 걸어온 거리. 세그먼트 경계를 넘어 누적된다.
    walked = 0.0

    for start, end in zip(path, path[1:]):
        seg_len = distance_meters(start, end)
        if seg_len == 0:
            continue

        # 이 세그먼트 안에서 다음 점을 찍을 위치(세그먼트 시작 기준 거리).
        offset = interval_meters - walked
        while offset <= seg_len:
            t = offset / seg_len
            result.append(
                (
                    start[0] + (end[0] - start[0]) * t,
                    start[1] + (end[1] - start[1]) * t,
                )
            )
            offset += interval_meters
        walked = seg_len - (offset - interval_meters)

    # 끝점 보존. 마지막으로 찍힌 점이 사실상 끝점이면 중복을 만들지 않는다.
    if distance_meters(result[-1], path[-1]) > 1e-6:
        result.append(path[-1])

    return result


def elevation_gain_meters(elevations: list[float], threshold: float = 3.0) -> float:
    """누적 고도 상승(m).

    연속한 두 점의 차이를 그대로 더하면 고도 측정 노이즈가 전부 상승분으로
    쌓인다. threshold 이상 올라갔을 때만 반영해서 잔떨림을 걸러낸다.
    """
    if len(elevations) < 2:
        return 0.0

    gain = 0.0
    reference = elevations[0]

    for value in elevations[1:]:
        if value - reference >= threshold:
            gain += value - reference
            reference = value
        elif value < reference:
            reference = value

    return gain


def center_of(path: list[Point]) -> Point:
    """경로의 중심점. 위경도 평균이 아니라 구면 평균이라 경도 180도 부근에서도 안전하다."""
    x = y = z = 0.0

    for lat, lng in path:
        lat_r, lng_r = radians(lat), radians(lng)
        x += cos(lat_r) * cos(lng_r)
        y += cos(lat_r) * sin(lng_r)
        z += sin(lat_r)

    count = len(path)
    x, y, z = x / count, y / count, z / count

    return degrees(atan2(z, sqrt(x * x + y * y))), degrees(atan2(y, x))
