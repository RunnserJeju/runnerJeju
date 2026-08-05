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


class TestResample:
    """코스 리샘플링 — 불균등한 GPX 점을 균등 간격으로 다시 찍는다."""

    def test_short_paths_returned_as_is(self):
        assert geo.resample_path([], 15.0) == []
        assert geo.resample_path([JEJU_CITY_HALL], 15.0) == [JEJU_CITY_HALL]

    def test_rejects_non_positive_interval(self):
        with pytest.raises(ValueError):
            geo.resample_path([(33.20, 126.30), (33.21, 126.30)], 0)

    def test_uniform_spacing_on_straight_line(self):
        # 정북으로 약 111m 직선. 15m 간격이면 마지막 구간만 짧고 나머지는 전부 15m.
        path = [(33.2000, 126.3000), (33.2010, 126.3000)]
        resampled = geo.resample_path(path, 15.0)

        gaps = [
            geo.distance_meters(resampled[i], resampled[i + 1])
            for i in range(len(resampled) - 1)
        ]
        assert all(gap == pytest.approx(15.0, abs=0.1) for gap in gaps[:-1])
        assert gaps[-1] <= 15.1

    def test_preserves_endpoints(self):
        path = [(33.2000, 126.3000), (33.2010, 126.3005), (33.2013, 126.3020)]
        resampled = geo.resample_path(path, 15.0)

        assert resampled[0] == path[0]
        assert geo.distance_meters(resampled[-1], path[-1]) < 0.01

    def test_spacing_crosses_segment_boundaries(self):
        # 원본 점 간격(약 7m씩)이 리샘플 간격보다 촘촘해도, 세그먼트 경계를 넘어
        # 거리를 누적해서 15m마다 찍어야 한다.
        path = [(33.2000 + i * 0.00006, 126.3000) for i in range(20)]
        resampled = geo.resample_path(path, 15.0)

        gaps = [
            geo.distance_meters(resampled[i], resampled[i + 1])
            for i in range(len(resampled) - 1)
        ]
        assert all(gap == pytest.approx(15.0, abs=0.1) for gap in gaps[:-1])

    def test_uneven_input_becomes_uniform(self):
        # 성긴 구간(111m)과 촘촘한 구간(11m×5)이 섞인 경로 → 출력 간격은 균일해야 한다.
        sparse_then_dense = [
            (33.2000, 126.3000),
            (33.2010, 126.3000),  # 111m 점프
            *[(33.2010 + i * 0.0001, 126.3000) for i in range(1, 6)],  # 11m 간격
        ]
        resampled = geo.resample_path(sparse_then_dense, 15.0)

        gaps = [
            geo.distance_meters(resampled[i], resampled[i + 1])
            for i in range(len(resampled) - 1)
        ]
        assert all(gap == pytest.approx(15.0, abs=0.1) for gap in gaps[:-1])

    def test_new_points_lie_on_original_polyline(self):
        # 꺾인 경로를 리샘플해도 새 점은 원본 꺾은선 위에 있어야 한다(경로 왜곡 금지).
        bent = [(33.2000, 126.3000), (33.2010, 126.3000), (33.2010, 126.3012)]
        resampled = geo.resample_path(bent, 15.0)

        for point in resampled:
            assert geo.distance_to_path_meters(point, bent) < 0.5

    def test_total_length_preserved(self):
        # 점은 전부 원본 선 위에 있으므로 경로 길이가 달라지면 안 된다.
        path = [(33.2000, 126.3000), (33.2010, 126.3005), (33.2020, 126.3000)]
        original = geo.path_length_meters(path)
        resampled = geo.path_length_meters(geo.resample_path(path, 15.0))

        assert resampled == pytest.approx(original, rel=0.001)

    def test_interval_longer_than_path(self):
        # 전체 길이(약 111m)보다 긴 간격이면 시작점과 끝점만 남는다.
        path = [(33.2000, 126.3000), (33.2005, 126.3000), (33.2010, 126.3000)]
        assert geo.resample_path(path, 500.0) == [path[0], path[-1]]

    def test_skips_duplicate_points(self):
        # 같은 좌표가 연달아 있어도(0m 세그먼트) 0으로 나누지 않고 건너뛴다.
        path = [(33.2000, 126.3000), (33.2000, 126.3000), (33.2010, 126.3000)]
        resampled = geo.resample_path(path, 15.0)

        gaps = [
            geo.distance_meters(resampled[i], resampled[i + 1])
            for i in range(len(resampled) - 1)
        ]
        assert all(gap == pytest.approx(15.0, abs=0.1) for gap in gaps[:-1])


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
