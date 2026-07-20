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

# 완주로 인정하는 최소 일치율. 신호 대기·우회로 인한 이탈을 감안해 100%를 요구하지 않는다.
DEFAULT_MATCH_THRESHOLD = 0.85

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


def _is_covered(point: Point, path: list[Point], tolerance: float) -> bool:
    """path 위에 point로부터 tolerance 이내인 지점이 하나라도 있는지."""
    return any(distance_meters(point, candidate) <= tolerance for candidate in path)


def coverage_ratio(
    course_path: list[Point],
    run_path: list[Point],
    tolerance: float = DEFAULT_TOLERANCE_METERS,
) -> float:
    """코스 지점 중 실제로 지나간 지점의 비율 (0.0 ~ 1.0).

    방향은 보지 않는다. 역주행도 같은 코스를 달린 것으로 인정한다.
    """
    if not course_path:
        return 0.0

    covered = sum(
        1 for point in course_path if _is_covered(point, run_path, tolerance)
    )
    return covered / len(course_path)


def verify(
    course_path: list[Point],
    run_path: list[Point],
    tolerance: float = DEFAULT_TOLERANCE_METERS,
    threshold: float = DEFAULT_MATCH_THRESHOLD,
) -> VerificationOutcome:
    """러닝 경로가 코스를 따라간 것인지 판정한다."""
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

    if rate >= threshold:
        return VerificationOutcome(
            status="matched",
            match_rate=rate,
            detail=None,
        )

    return VerificationOutcome(
        status="mismatched",
        match_rate=rate,
        detail=f"코스의 {round(rate * 100)}%만 지나갔어요. "
        f"완주로 인정되려면 {round(threshold * 100)}% 이상이어야 해요.",
    )


def to_points(raw_path: list[dict]) -> list[Point]:
    """저장된 JSON 경로를 (lat, lng) 튜플 목록으로 바꾼다."""
    return [
        (float(item["lat"]), float(item["lng"]))
        for item in raw_path
        if item.get("lat") is not None and item.get("lng") is not None
    ]
