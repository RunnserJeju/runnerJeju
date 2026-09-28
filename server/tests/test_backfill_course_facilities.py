"""tools/backfill_course_facilities의 주소 정리·재시도 규칙 테스트.

옛 컬럼 값은 손으로 적은 문자열이라 형태가 제각각이다(쉼표로 여러 개, 장소명 붙음,
\\xa0 섞임). 네트워크 없이 geocoding.geocode를 흉내내 규칙만 본다.
"""

from app import geocoding
from app.geocoding import GeocodeResult
from tools import backfill_course_facilities as backfill


def _fake_geocode(known: dict[str, int]):
    """known[주소] = 후보 수. 모르는 주소는 못 찾음(빈 리스트)."""

    def geocode(address: str) -> list[GeocodeResult]:
        count = known.get(address, 0)
        return [
            GeocodeResult(address=f"{address} (지번)", road_address=f"{address} (도로명)", lat=33.5 + i, lng=126.5)
            for i in range(count)
        ]

    return geocode


class TestSplit:
    def test_splits_comma_separated_addresses_and_trims(self):
        raw = "제주시 구좌읍 김녕로14길 6, 제주시 구좌읍 김녕로 209 "

        assert backfill._split(raw) == ["제주시 구좌읍 김녕로14길 6", "제주시 구좌읍 김녕로 209"]

    def test_normalizes_nbsp_and_spaces(self):
        assert backfill._split("월드컵경기장 \xa0서귀포시 법환동 870") == [
            "월드컵경기장 서귀포시 법환동 870"
        ]


class TestResolve:
    def test_exact_match_needs_no_review(self, monkeypatch):
        monkeypatch.setattr(geocoding, "geocode", _fake_geocode({"제주시 탑동로2길 4": 1}))

        resolved = backfill.resolve("제주시 탑동로2길 4")

        assert resolved.needs_review is False
        assert resolved.facility["name"] is None
        # 운영 웹 "좌표 확인"과 같게 도로명 주소를 저장한다.
        assert resolved.facility["address"] == "제주시 탑동로2길 4 (도로명)"

    def test_drops_leading_place_name_and_keeps_it_as_name(self, monkeypatch):
        monkeypatch.setattr(geocoding, "geocode", _fake_geocode({"서귀포시 법환동 870": 1}))

        resolved = backfill.resolve("월드컵경기장 서귀포시 법환동 870")

        assert resolved.facility["name"] == "월드컵경기장"
        assert resolved.needs_review is True

    def test_drops_trailing_place_name(self, monkeypatch):
        monkeypatch.setattr(geocoding, "geocode", _fake_geocode({"제주 서귀포시 칠십리로 156-8": 1}))

        resolved = backfill.resolve("제주 서귀포시 칠십리로 156-8 정모시쉼터")

        assert resolved.facility["name"] == "정모시쉼터"
        assert resolved.needs_review is True

    def test_multiple_candidates_flag_review(self, monkeypatch):
        monkeypatch.setattr(geocoding, "geocode", _fake_geocode({"제주시 조천읍 함덕리 산 4": 3}))

        resolved = backfill.resolve("제주시 조천읍 함덕리 산 4")

        assert resolved.needs_review is True
        assert "후보 3개" in resolved.note

    def test_returns_none_when_nothing_matches(self, monkeypatch):
        monkeypatch.setattr(geocoding, "geocode", _fake_geocode({}))

        assert backfill.resolve("어딘가 없는 주소 1") is None
