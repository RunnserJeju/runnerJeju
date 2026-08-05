
"""GPX 파서 테스트.

실제 코스 파일(courses/sagye-coastal.gpx) 하나를 기준점으로 쓰고, 나머지는
파서가 거절해야 하는 입력들이다.
"""

from pathlib import Path

import pytest

from app import gpx

SAGYE = Path(__file__).resolve().parent.parent / "courses" / "sagye-coastal.gpx"


def wrap(body: str, ns: str = 'xmlns="http://www.topografix.com/GPX/1/1"') -> bytes:
    return f'<?xml version="1.0" encoding="UTF-8"?><gpx {ns} version="1.1">{body}</gpx>'.encode()


def track(points: list[tuple[float, float]]) -> str:
    inner = "".join(f'<trkpt lat="{lat}" lon="{lng}"></trkpt>' for lat, lng in points)
    return f"<trk><trkseg>{inner}</trkseg></trk>"


# 제주 안의 임의의 세 점.
JEJU_POINTS = [(33.2285, 126.3064), (33.2280, 126.3054), (33.2270, 126.3040)]


@pytest.fixture(scope="module")
def parsed() -> gpx.ParsedCourse:
    return gpx.parse(SAGYE.read_bytes())


class TestRealCourse:
    """사계해안도로 6.2km — 경로 플래너에서 내보낸 실제 파일."""

    def test_reads_name_from_metadata(self, parsed):
        assert parsed.name == "사계해안도로 6.2km"

    def test_removes_duplicate_points(self, parsed):
        # 원본은 207점이고 그중 22점이 직전 점과 좌표가 같다.
        assert len(parsed.points) == 185

    def test_distance_matches_filename(self, parsed):
        # 파일명이 6.2km라고 말한다. 계산값이 그 근처여야 한다.
        assert parsed.distance_meters == pytest.approx(6232.6, abs=1.0)

    def test_detects_loop(self, parsed):
        # 시작점과 끝점이 10.5m 떨어져 있다.
        assert parsed.is_loop is True

    def test_keeps_elevation(self, parsed):
        assert all(p.altitude is not None for p in parsed.points)
        # 해안도로라 고도 상승이 거의 없다.
        assert parsed.elevation_gain_meters == pytest.approx(3.0, abs=0.5)

    def test_has_no_timestamps(self, parsed):
        # 달린 기록이 아니라 그린 경로라서 <time>이 없다.
        assert all(p.recorded_at is None for p in parsed.points)

    def test_json_keys_match_client_contract(self, parsed):
        # 이 키들은 Flutter GeoPoint.fromJson과 1:1이다. 바꾸면 앱이 조용히 깨진다.
        assert set(parsed.points[0].to_json()) == {"lat", "lng", "altitude"}


class TestRealCourseResampled:
    """저장용 리샘플 경로 — 원본은 평균 30m·최장 252m 간격인데, 이걸 15m 균등으로 만든다."""

    def _gaps(self, points):
        from app import geo

        coords = [(p.lat, p.lng) for p in points]
        return [
            geo.distance_meters(coords[i], coords[i + 1])
            for i in range(len(coords) - 1)
        ]

    def test_point_count_matches_distance(self, parsed):
        # 6232.6m ÷ 15m ≈ 415 구간이므로 점은 그보다 1~2개 많은 정도여야 한다.
        expected = parsed.distance_meters / gpx.RESAMPLE_INTERVAL_METERS
        assert expected < len(parsed.resampled_points) <= expected + 2

    def test_no_gap_exceeds_interval(self, parsed):
        # 원본의 최장 252m 간격이 사라지고 모든 간격이 15m 이하가 되어야 한다.
        assert max(self._gaps(parsed.resampled_points)) <= 15.1

    def test_spacing_is_uniform(self, parsed):
        # 간격은 *경로상* 15m다. 직선거리로 재면 굽은 구간에서 그보다 짧게
        # 나온다(코너 커팅) — 사계해안도로 실측: 대부분 15.0m, 곡선부 14.8m대,
        # 급커브 2곳만 8.8~14m. 평균과 최솟값으로 그 분포를 검증한다.
        gaps = self._gaps(parsed.resampled_points)

        assert all(gap <= 15.1 for gap in gaps)
        assert sum(gaps) / len(gaps) > 14.7
        assert min(gaps[:-1]) > 5

    def test_preserves_endpoints(self, parsed):
        first, last = parsed.resampled_points[0], parsed.resampled_points[-1]
        assert (first.lat, first.lng) == (parsed.points[0].lat, parsed.points[0].lng)
        assert (last.lat, last.lng) == (parsed.points[-1].lat, parsed.points[-1].lng)

    def test_length_nearly_preserved(self, parsed):
        # 코너 커팅으로 길이가 아주 조금 줄 수는 있지만(실측 0.25%) 그 이상 왜곡되면
        # 리샘플이 경로를 벗어났다는 신호다. 코스의 공식 거리는 원본으로 계산해 저장한다.
        from app import geo

        resampled_length = geo.path_length_meters(
            [(p.lat, p.lng) for p in parsed.resampled_points]
        )
        assert resampled_length == pytest.approx(parsed.distance_meters, rel=0.005)

    def test_json_has_no_altitude(self, parsed):
        # 보간한 점의 고도는 추정치라 싣지 않는다. 코스 고도는 elevation_gain 하나로 충분.
        assert set(parsed.resampled_points[0].to_json()) == {"lat", "lng"}


class TestNamespaces:
    def test_gpx_1_0(self):
        content = wrap(track(JEJU_POINTS), ns='xmlns="http://www.topografix.com/GPX/1/0"')
        assert len(gpx.parse(content).points) == 3

    def test_no_namespace(self):
        assert len(gpx.parse(wrap(track(JEJU_POINTS), ns="")).points) == 3


class TestFallbacks:
    def test_merges_multiple_tracks(self):
        content = wrap(track(JEJU_POINTS[:2]) + track(JEJU_POINTS[2:]))
        assert len(gpx.parse(content).points) == 3

    def test_falls_back_to_route_points(self):
        inner = "".join(
            f'<rtept lat="{lat}" lon="{lng}"></rtept>' for lat, lng in JEJU_POINTS
        )
        assert len(gpx.parse(wrap(f"<rte>{inner}</rte>")).points) == 3

    def test_prefers_track_over_waypoints(self):
        # 트랙과 웨이포인트가 함께 있으면 트랙이 코스다.
        waypoints = '<wpt lat="33.5" lon="126.5"></wpt>'
        parsed = gpx.parse(wrap(waypoints + track(JEJU_POINTS)))
        assert len(parsed.points) == 3
        assert parsed.points[0].lat == 33.2285

    def test_name_falls_back_to_track_name(self):
        content = wrap(f"<trk><name>한라산 둘레길</name>{track(JEJU_POINTS)[5:]}")
        assert gpx.parse(content).name == "한라산 둘레길"


class TestRejects:
    def test_malformed_xml(self):
        with pytest.raises(gpx.GpxParseError, match="읽을 수 없어요"):
            gpx.parse(b"<gpx><trk>")

    def test_not_a_gpx_file(self):
        with pytest.raises(gpx.GpxParseError, match="GPX 파일이 아니에요"):
            gpx.parse(b"<kml><Document/></kml>")

    def test_too_few_points(self):
        with pytest.raises(gpx.GpxParseError, match="코스로 쓸 수 없어요"):
            gpx.parse(wrap(track(JEJU_POINTS[:2])))

    def test_empty_track(self):
        with pytest.raises(gpx.GpxParseError, match="코스로 쓸 수 없어요"):
            gpx.parse(wrap("<trk><trkseg></trkseg></trk>"))

    def test_outside_jeju(self):
        seoul = [(37.5665, 126.9780), (37.5670, 126.9790), (37.5680, 126.9800)]
        with pytest.raises(gpx.GpxParseError, match="제주도 밖"):
            gpx.parse(wrap(track(seoul)))

    def test_duplicates_collapse_below_minimum(self):
        # 서로 다른 점이 2개뿐이라 중복 제거 후 최소 개수에 못 미친다.
        repeated = [JEJU_POINTS[0], JEJU_POINTS[0], JEJU_POINTS[0], JEJU_POINTS[1]]
        with pytest.raises(gpx.GpxParseError, match="코스로 쓸 수 없어요"):
            gpx.parse(wrap(track(repeated)))


class TestPartialElevation:
    def test_elevation_is_none_when_incomplete(self):
        # 일부 점에만 <ele>가 있으면 누적 상승이 왜곡되므로 계산하지 않는다.
        inner = (
            '<trkpt lat="33.2285" lon="126.3064"><ele>10</ele></trkpt>'
            '<trkpt lat="33.2280" lon="126.3054"></trkpt>'
            '<trkpt lat="33.2270" lon="126.3040"><ele>30</ele></trkpt>'
        )
        parsed = gpx.parse(wrap(f"<trk><trkseg>{inner}</trkseg></trk>"))
        assert parsed.elevation_gain_meters is None


class TestTimestamps:
    def test_parses_recorded_at(self):
        inner = "".join(
            f'<trkpt lat="{lat}" lon="{lng}"><time>2026-07-27T0{i}:00:00Z</time></trkpt>'
            for i, (lat, lng) in enumerate(JEJU_POINTS)
        )
        parsed = gpx.parse(wrap(f"<trk><trkseg>{inner}</trkseg></trk>"))
        assert parsed.points[0].recorded_at is not None
        assert "recorded_at" in parsed.points[0].to_json()

    def test_ignores_unparseable_time(self):
        inner = "".join(
            f'<trkpt lat="{lat}" lon="{lng}"><time>어제</time></trkpt>'
            for lat, lng in JEJU_POINTS
        )
        parsed = gpx.parse(wrap(f"<trk><trkseg>{inner}</trkseg></trk>"))
        assert parsed.points[0].recorded_at is None


class TestSlugify:
    @pytest.mark.parametrize(
        "value,expected",
        [
            ("사계해안도로", "사계해안도로"),
            ("Sagye Coastal Road", "sagye-coastal-road"),
            ("  공백   투성이  ", "공백-투성이"),
            ("특수!@#문자", "특수-문자"),
        ],
    )
    def test_slugify(self, value, expected):
        assert gpx.slugify(value) == expected
