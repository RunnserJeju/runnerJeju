"""지오메트리 유틸 테스트."""

import pytest

from app import geo

JEJU_CITY_HALL = (33.4996, 126.5312)


class TestDistance:
    def test_same_point_is_zero(self):
        assert geo.distance_meters(JEJU_CITY_HALL, JEJU_CITY_HALL) == 0

    def test_one_degree_latitude(self):
        # 위도 1도는 어디서나 약 111km.
        assert geo.distance_meters((33.0, 126.0), (34.0, 126.0)) == pytest.approx(
            111_195, rel=0.001
        )

    def test_is_symmetric(self):
        a, b = (33.2285, 126.3064), (33.2270, 126.3040)
        assert geo.distance_meters(a, b) == pytest.approx(geo.distance_meters(b, a))


class TestPathLength:
    def test_empty_and_single_point(self):
        assert geo.path_length_meters([]) == 0
        assert geo.path_length_meters([JEJU_CITY_HALL]) == 0

    def test_sums_segments(self):
        path = [(33.0, 126.0), (33.01, 126.0), (33.02, 126.0)]
        expected = geo.distance_meters(path[0], path[1]) * 2
        assert geo.path_length_meters(path) == pytest.approx(expected)


class TestSegmentDistance:
    """코스 점 간격이 성길 때(최장 252m) 검증이 오판하지 않게 하는 핵심 함수."""

    def test_point_on_segment_is_zero(self):
        start, end = (33.20, 126.30), (33.21, 126.30)
        midpoint = (33.205, 126.30)
        assert geo.distance_to_segment_meters(midpoint, start, end) == pytest.approx(
            0, abs=1.0
        )

    def test_midpoint_beats_nearest_vertex(self):
        # 250m 떨어진 두 점 사이 한가운데에 서 있는 경우.
        # 꼭짓점까지의 거리는 125m지만, 선분까지의 거리는 0이어야 한다.
        start, end = (33.2000, 126.3000), (33.2000, 126.3027)
        midpoint = (33.2000, 126.30135)

        to_vertex = min(
            geo.distance_meters(midpoint, start), geo.distance_meters(midpoint, end)
        )
        to_segment = geo.distance_to_segment_meters(midpoint, start, end)

        assert to_vertex > 100
        assert to_segment == pytest.approx(0, abs=1.0)

    def test_clamps_beyond_endpoints(self):
        # 선분 연장선 바깥의 점은 가장 가까운 끝점까지의 거리로 잘린다.
        start, end = (33.2000, 126.3000), (33.2000, 126.3010)
        beyond = (33.2000, 126.3020)
        assert geo.distance_to_segment_meters(beyond, start, end) == pytest.approx(
            geo.distance_meters(beyond, end), rel=0.01
        )

    def test_degenerate_segment(self):
        point, same = (33.2010, 126.3000), (33.2000, 126.3000)
        assert geo.distance_to_segment_meters(point, same, same) == pytest.approx(
            geo.distance_meters(point, same), rel=0.01
        )

    def test_distance_to_path_takes_minimum(self):
        path = [(33.20, 126.30), (33.21, 126.30), (33.22, 126.30)]
        assert geo.distance_to_path_meters((33.215, 126.30), path) == pytest.approx(
            0, abs=1.0
        )

    def test_distance_to_empty_path(self):
        assert geo.distance_to_path_meters(JEJU_CITY_HALL, []) == float("inf")


class TestJejuBounds:
    def test_accepts_jeju(self):
        assert geo.is_within_jeju([JEJU_CITY_HALL, (33.2285, 126.3064)])

    def test_rejects_seoul(self):
        assert not geo.is_within_jeju([JEJU_CITY_HALL, (37.5665, 126.9780)])


class TestElevationGain:
    def test_ignores_noise_below_threshold(self):
        # 1m 미만으로 오르내리는 잔떨림은 상승으로 치지 않는다.
        noisy = [2.5, 2.6, 2.5, 2.7, 2.6, 2.5]
        assert geo.elevation_gain_meters(noisy) == 0

    def test_counts_real_climb(self):
        assert geo.elevation_gain_meters([0, 10, 20]) == pytest.approx(20)

    def test_ignores_descent(self):
        assert geo.elevation_gain_meters([100, 50, 10]) == 0

    def test_counts_each_climb_separately(self):
        # 올라갔다 내려갔다 다시 올라가면 두 번의 상승이 모두 잡힌다.
        assert geo.elevation_gain_meters([0, 10, 0, 10]) == pytest.approx(20)

    def test_short_input(self):
        assert geo.elevation_gain_meters([]) == 0
        assert geo.elevation_gain_meters([5.0]) == 0


class TestBoundsAndCenter:
    def test_bounds(self):
        path = [(33.20, 126.30), (33.25, 126.35), (33.22, 126.28)]
        assert geo.bounds(path) == (33.20, 126.28, 33.25, 126.35)

    def test_center_of_symmetric_pair(self):
        lat, lng = geo.center_of([(33.20, 126.30), (33.30, 126.30)])
        assert lat == pytest.approx(33.25, abs=0.001)
        assert lng == pytest.approx(126.30, abs=0.001)
