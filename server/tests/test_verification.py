"""경로 검증 로직 테스트.

두 가지 코스를 쓴다.

- 합성 직선 코스: 기하가 단순해서 "절반 뛰면 50%" 같은 비례 관계를 정확히 검증할 수 있다.
- 실제 코스(courses/sagye-coastal.gpx): 리샘플 파이프라인을 통과한 경로로 하는 스모크 테스트.
  이 코스는 **왕복**이라(같은 길을 되돌아옴) 전반부만 달려도 커버리지가 100%가 된다 —
  그 특성 자체를 문서화하는 테스트가 아래에 있다.
"""

from pathlib import Path

import pytest

from app import gpx, verification

SAGYE = Path(__file__).resolve().parent.parent / "courses" / "sagye-coastal.gpx"

# 위도 방향 미터 → 도 변환(픽스처 합성용).
LAT_PER_METER = 1 / 111_132.0


@pytest.fixture(scope="module")
def sagye() -> list[verification.Point]:
    """등록 파이프라인이 저장하는 것과 같은, 15m 리샘플된 실제 코스 경로."""
    parsed = gpx.parse(SAGYE.read_bytes())
    return [(p.lat, p.lng) for p in parsed.resampled_points]


@pytest.fixture(scope="module")
def straight() -> list[verification.Point]:
    """정북 방향 3km 직선, 15m 간격 201점."""
    return [(33.20 + i * 15 * LAT_PER_METER, 126.30) for i in range(201)]


def shift_east(path: list[verification.Point], meters: float) -> list[verification.Point]:
    """경로 전체를 동쪽으로 meters만큼 평행이동(직선 코스와 직각 방향)."""
    # 위도 33.2도에서 경도 1도 ≈ 93,160m.
    return [(lat, lng + meters / 93_160.0) for lat, lng in path]


class TestCoverageRatioGeometry:
    """합성 직선 코스 — 비율과 거리의 정확한 관계를 검증한다."""

    def test_running_exactly_on_course(self, straight):
        assert verification.coverage_ratio(straight, straight) == 1.0

    def test_empty_paths(self, straight):
        assert verification.coverage_ratio([], straight) == 0.0
        assert verification.coverage_ratio(straight, []) == 0.0

    def test_half_course_gives_half_ratio(self, straight):
        # 리샘플 간격이 균등하므로 "점 개수 비율 = 거리 비율"이 성립해야 한다.
        half = straight[: len(straight) // 2]
        assert verification.coverage_ratio(straight, half) == pytest.approx(
            0.5, abs=0.05
        )

    def test_parallel_within_tolerance(self, straight):
        # 20m 옆(도로 반대편 인도 수준)은 tolerance 30m 안이라 전부 인정.
        assert verification.coverage_ratio(straight, shift_east(straight, 20)) == 1.0

    def test_parallel_outside_tolerance(self, straight):
        # 50m 옆은 tolerance 밖이라 전부 탈락.
        assert verification.coverage_ratio(straight, shift_east(straight, 50)) == 0.0

    def test_sparse_gps_recording_still_covers(self, straight):
        # GPS 기록이 뜸해서(75m마다 한 점) 점 사이가 벌어져도, 그 사이 선 위의
        # 코스 점들이 커버로 잡혀야 한다. 점-대-점 방식이었다면 기록 점에서 30m를
        # 넘는 코스 점들이 전부 탈락한다 — 이 교체의 핵심 회귀 테스트.
        sparse_run = straight[::5]
        assert verification.coverage_ratio(straight, sparse_run) == pytest.approx(
            1.0, abs=0.01
        )

    def test_single_point_run(self, straight):
        # 기록이 한 점뿐이면 그 주변 코스 점만 커버된다(30m 반경 → 시작점 부근 3점).
        ratio = verification.coverage_ratio(straight, [straight[0]])
        assert 0 < ratio < 0.05


class TestCoverageRatioRealCourse:
    """사계해안도로 — 리샘플 파이프라인 산출물로 하는 스모크 테스트."""

    def test_running_exactly_on_course(self, sagye):
        assert verification.coverage_ratio(sagye, sagye) == 1.0

    def test_far_away_run(self, sagye):
        far = [(lat + 1000 * LAT_PER_METER, lng) for lat, lng in sagye]
        assert verification.coverage_ratio(sagye, far) == 0.0

    def test_reverse_direction_counts(self, sagye):
        # 역주행도 같은 코스를 달린 것으로 인정한다(명시된 정책).
        assert verification.coverage_ratio(sagye, list(reversed(sagye))) == 1.0

    def test_out_and_back_half_run_covers_everything(self, sagye):
        # 이 코스는 왕복이라 전반부(편도)만 달려도 커버리지가 100%다.
        # 커버리지만으로는 편도와 완주를 구분할 수 없다는 한계의 기록이다.
        # verify()의 거리 하한이 이 구멍을 막는다(TestVerify 참고).
        half = sagye[: len(sagye) // 2]
        assert verification.coverage_ratio(sagye, half) > 0.99


class TestVerify:
    """기준은 완주가 아니라 "코스의 85%"다(제품 결정).

    matched = 커버리지 ≥ 85% AND 주행 거리 ≥ 코스의 85%.
    시작/종료 지점 도달은 요구하지 않는다.
    """

    def test_matched_on_real_course(self, sagye):
        outcome = verification.verify(sagye, sagye)
        assert outcome.status == "matched"
        assert outcome.match_rate == 1.0
        assert outcome.detail is None

    def test_matched_on_straight_course(self, straight):
        assert verification.verify(straight, straight).status == "matched"

    def test_reverse_run_still_matches(self, straight):
        # 역주행 정책: 두 조건 모두 방향에 무관해야 한다.
        assert verification.verify(straight, list(reversed(straight))).status == "matched"

    def test_stopping_short_of_finish_still_matches(self, straight):
        # 종점 전에 멈춰도 코스의 85%를 채웠으면 인정 — 이 정책의 핵심 테스트.
        # 90% 지점에서 멈춘 러닝: 커버리지 90%, 거리 90% → matched.
        stopped_at_90 = straight[: int(len(straight) * 0.9)]
        assert verification.verify(straight, stopped_at_90).status == "matched"

    def test_skipping_start_still_matches(self, straight):
        # 시작점을 건너뛰고 뒤쪽 90%만 달려도 같은 이유로 인정.
        assert verification.verify(straight, straight[int(len(straight) * 0.1):]).status == "matched"

    def test_low_coverage_reports_rate(self, straight):
        outcome = verification.verify(straight, straight[: len(straight) // 2])
        assert outcome.status == "mismatched"
        assert outcome.match_rate == pytest.approx(0.5, abs=0.05)
        assert "%" in outcome.detail

    def test_out_and_back_half_run_rejected_by_distance(self, sagye):
        # 왕복 코스의 편도 주행: 커버리지는 100%지만 실제 주행이 코스의 절반이라
        # 탈락해야 한다. 이게 뚫리면 왕복 코스는 절반만 뛰고 스탬프를 받는다.
        outcome = verification.verify(sagye, sagye[: len(sagye) // 2])
        assert outcome.status == "mismatched"
        assert outcome.match_rate > 0.99
        assert "거리" in outcome.detail

    def test_honest_slop_still_matches(self, straight):
        # 주차장에서 걸어와서 시작하고, 종료 후 기록을 끄지 않고 더 걸어도 인정 —
        # 커버리지는 여분 이동에 영향받지 않고 거리는 늘어나기만 한다.
        warmup = [(straight[0][0], straight[0][1] - i * 30 / 93_160.0) for i in (3, 2, 1)]
        cooldown = [(straight[-1][0], straight[-1][1] + i * 30 / 93_160.0) for i in (1, 2, 3)]
        outcome = verification.verify(straight, warmup + straight + cooldown)
        assert outcome.status == "matched"

    def test_failed_when_course_empty(self, sagye):
        outcome = verification.verify([], sagye)
        assert outcome.status == "failed"
        assert outcome.match_rate is None

    def test_failed_when_run_empty(self, sagye):
        outcome = verification.verify(sagye, [])
        assert outcome.status == "failed"


class TestToPoints:
    def test_converts_and_skips_incomplete(self):
        raw = [
            {"lat": 33.2, "lng": 126.3},
            {"lat": None, "lng": 126.3},
            {"lng": 126.3},
            {"lat": 33.3, "lng": 126.4, "altitude": 5.0},
        ]
        assert verification.to_points(raw) == [(33.2, 126.3), (33.3, 126.4)]
