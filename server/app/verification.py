"""경로 검증 로직.

이 모듈은 **의도적으로 순수 함수만 담는다.** DB 세션도, FastAPI도, ORM 모델도
참조하지 않는다. 검증 연산은 CPU를 오래 쓰기 때문에 나중에 별도 검증 서버로
분리할 예정이고, 그때 이 파일을 그대로 옮길 수 있어야 하기 때문이다.
자세한 배경은 docs/architecture.md 참고.
"""

from dataclasses import dataclass
from math import asin, cos, radians, sin, sqrt

EARTH_RADIUS_METERS = 6_371_000

# 코스 위의 한 점이 "지나간 것"으로 인정되는 반경(m).
# GPS 오차와 도로 폭을 감안한 값.
DEFAULT_TOLERANCE_METERS = 30.0

# 스탬프 기준은 "완주"가 아니라 **"코스의 85%를 달렸는가"**다(제품 결정).
# 그래서 종료 지점에 도달하지 못해도 85%를 채웠으면 인정하며,
# 시작/종료 지점 근접을 요구하지 않는다. 아래 두 값이 같은 85%인 이유다 —
# 하나의 기준을 두 가지 측정(궤적 일치, 실제 주행량)으로 확인할 뿐이다.

# 인정에 필요한 최소 일치율(코스 리샘플 점 중 지나간 비율).
DEFAULT_MATCH_THRESHOLD = 0.85

# 인정에 필요한 최소 주행 거리(코스 거리 대비, 경로에서 계산).
#
# 커버리지만으로는 왕복 코스의 편도 주행을 거를 수 없다 — 복로가 왕로의
# tolerance 안에 있어 편도만 달려도 커버리지가 100%가 된다(사계해안도로 실측).
# "실제로 코스 거리의 85%만큼 달렸는가"를 따로 확인해야 편도(50%)가 걸러진다.
DEFAULT_MIN_DISTANCE_RATIO = 0.85

Point = tuple[float, float]


@dataclass(frozen=True)
class VerificationOutcome:
    """검증 결과. status는 클라이언트 VerificationStatus.name과 값이 같아야 한다."""

    status: str
    match_rate: float | None
    detail: str | None


def distance_meters(a: Point, b: Point) -> float:
    """두 지점 사이의 대원 거리(m). 클라이언트 GeoUtils와 같은 공식을 쓴다."""
    lat1, lng1 = a
    lat2, lng2 = b

    d_lat = radians(lat2 - lat1)
    d_lng = radians(lng2 - lng1)

    h = (
        sin(d_lat / 2) ** 2
        + sin(d_lng / 2) ** 2 * cos(radians(lat1)) * cos(radians(lat2))
    )

    return 2 * EARTH_RADIUS_METERS * asin(min(1.0, sqrt(h)))


XY = tuple[float, float]


def _to_local_xy(path: list[Point], ref: Point) -> list[XY]:
    """위경도를 ref 기준 지역 평면 좌표(m)로 투영한다.

    코스 하나는 수 km 범위라 평면 근사 오차는 tolerance(30m) 대비 무시할 수준이다.
    투영을 한 번만 해두면 이후 거리 계산이 전부 산술 연산이 되어, 코스 수백 점 ×
    러닝 수천 점 비교에서 Haversine을 반복하는 것보다 훨씬 싸다.
    """
    lat_ref = radians(ref[0])
    m_per_deg_lat = 111_132.0
    m_per_deg_lng = 111_320.0 * cos(lat_ref)

    return [
        ((lng - ref[1]) * m_per_deg_lng, (lat - ref[0]) * m_per_deg_lat)
        for lat, lng in path
    ]


def _near_polyline(px: float, py: float, polyline: list[XY], tolerance: float) -> bool:
    """점 (px, py)가 꺾은선으로부터 tolerance(m) 이내인지.

    러닝 기록의 *점*이 아니라 점들을 이은 *선*과 비교한다. GPS 기록이 뜸했던
    구간(신호 끊김 등)에서 실제로는 그 사이 선 위를 지났는데도 점끼리의 거리로만
    재면 놓치기 때문이다. geo.distance_to_segment_meters와 같은 계산이지만,
    이 파일의 무의존 원칙 때문에 여기 다시 구현한다(모듈 docstring 참고).
    """
    tol_sq = tolerance * tolerance

    if len(polyline) == 1:
        x, y = polyline[0]
        return (px - x) ** 2 + (py - y) ** 2 <= tol_sq

    for (ax, ay), (bx, by) in zip(polyline, polyline[1:]):
        # 바운딩박스로 먼 세그먼트를 먼저 걸러낸다. 대부분의 세그먼트가 여기서
        # 탈락해서 투영 계산까지 가지 않는다.
        if px < min(ax, bx) - tolerance or px > max(ax, bx) + tolerance:
            continue
        if py < min(ay, by) - tolerance or py > max(ay, by) + tolerance:
            continue

        ex, ey = bx - ax, by - ay
        dx, dy = px - ax, py - ay

        seg_len_sq = ex * ex + ey * ey
        if seg_len_sq == 0:
            t = 0.0
        else:
            # 점을 세그먼트에 투영한 위치(0~1로 잘라냄).
            t = max(0.0, min(1.0, (dx * ex + dy * ey) / seg_len_sq))

        nx, ny = dx - t * ex, dy - t * ey
        if nx * nx + ny * ny <= tol_sq:
            return True

    return False


def coverage_ratio(
    course_path: list[Point],
    run_path: list[Point],
    tolerance: float = DEFAULT_TOLERANCE_METERS,
) -> float:
    """코스 지점 중 러닝 경로가 tolerance 이내로 지나간 지점의 비율 (0.0 ~ 1.0).

    코스 경로는 등록 시 균등 간격으로 리샘플되어 있으므로(gpx.RESAMPLE_INTERVAL_METERS)
    이 비율은 곧 "코스 거리의 몇 %를 지나갔는가"다. 비교 대상은 러닝 기록의 점이
    아니라 점들을 이은 꺾은선이다(_near_polyline 참고).

    방향은 보지 않는다. 역주행도 같은 코스를 달린 것으로 인정한다.
    """
    if not course_path or not run_path:
        return 0.0

    ref = course_path[0]
    course_xy = _to_local_xy(course_path, ref)
    run_xy = _to_local_xy(run_path, ref)

    covered = sum(
        1 for px, py in course_xy if _near_polyline(px, py, run_xy, tolerance)
    )
    return covered / len(course_path)


def path_length_meters(path: list[Point]) -> float:
    """경로 전체 길이(m). geo.path_length_meters와 같은 계산(무의존 원칙으로 재구현)."""
    return sum(distance_meters(path[i], path[i + 1]) for i in range(len(path) - 1))


def verify(
    course_path: list[Point],
    run_path: list[Point],
    tolerance: float = DEFAULT_TOLERANCE_METERS,
    threshold: float = DEFAULT_MATCH_THRESHOLD,
    min_distance_ratio: float = DEFAULT_MIN_DISTANCE_RATIO,
) -> VerificationOutcome:
    """러닝이 코스의 85% 기준을 채웠는지 판정한다.

    matched 조건은 둘의 AND다. 같은 85% 기준을 두 측정으로 확인한다.

    1. 커버리지 ≥ threshold        — 코스 점의 85% 이상을 지나갔는가 (궤적 일치)
    2. 주행 거리 ≥ 코스의 85%      — 실제로 그만큼 달렸는가 (왕복 편도 차단)

    시작/종료 지점 도달은 요구하지 않는다 — 기준이 완주가 아니라 85%이기 때문이다
    (모듈 상수 주석 참고). detail은 실패 사유 하나만 담는다(커버리지 → 거리 순).
    """
    if not course_path:
        return VerificationOutcome(
            status="failed",
            match_rate=None,
            detail="코스에 경로 데이터가 없어 검증할 수 없어요.",
        )

    if not run_path:
        return VerificationOutcome(
            status="failed",
            match_rate=None,
            detail="러닝 경로가 비어 있어 검증할 수 없어요.",
        )

    rate = coverage_ratio(course_path, run_path, tolerance)

    if rate < threshold:
        return VerificationOutcome(
            status="mismatched",
            match_rate=rate,
            detail=f"코스의 {round(rate * 100)}%만 지나갔어요. "
            f"인정되려면 {round(threshold * 100)}% 이상이어야 해요.",
        )

    course_length = path_length_meters(course_path)
    run_length = path_length_meters(run_path)

    if course_length > 0 and run_length < course_length * min_distance_ratio:
        return VerificationOutcome(
            status="mismatched",
            match_rate=rate,
            detail=f"달린 거리가 코스의 {round(run_length / course_length * 100)}%예요. "
            f"인정되려면 {round(min_distance_ratio * 100)}% 이상이어야 해요.",
        )

    return VerificationOutcome(
        status="matched",
        match_rate=rate,
        detail=None,
    )


def to_points(raw_path: list[dict]) -> list[Point]:
    """저장된 JSON 경로를 (lat, lng) 튜플 목록으로 바꾼다."""
    return [
        (float(item["lat"]), float(item["lng"]))
        for item in raw_path
        if item.get("lat") is not None and item.get("lng") is not None
    ]
