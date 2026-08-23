"""지오코딩(app.geocoding.geocode) 테스트.

카카오 호출은 실제 네트워크를 타므로 httpx.get을 monkeypatch로 갈아끼운다.
test_banners.py가 Supabase 호출을 갈아끼우는 것과 같은 방침이다. 이 파일은
'찾음 / 못 찾음 / 호출 실패 / 키 미설정' 네 갈래가 각각 맞게 갈리는지만 본다.
"""

import httpx
import pytest

from app import geocoding


class FakeResponse:
    def __init__(self, payload: dict, status_code: int = 200):
        self._payload = payload
        self.status_code = status_code

    def raise_for_status(self):
        if self.status_code >= 400:
            raise httpx.HTTPStatusError(
                "error", request=httpx.Request("GET", "http://x"), response=None
            )

    def json(self):
        return self._payload


def _patch_key(monkeypatch, key: str | None = "fake-rest-key"):
    monkeypatch.setattr(geocoding, "KAKAO_REST_API_KEY", key)


def _patch_get(monkeypatch, response: FakeResponse):
    monkeypatch.setattr(geocoding.httpx, "get", lambda *a, **k: response)


# 카카오 주소검색 응답의 실제 형태를 최소로 흉내낸다(x=경도, y=위도, 문자열).
_KAKAO_DOC = {
    "address_name": "제주특별자치도 서귀포시 대정읍 상모리 4165-123",
    "x": "126.293",
    "y": "33.235",
    "road_address": {"address_name": "제주특별자치도 서귀포시 대정읍 송악관광로 42"},
}


class TestGeocode:
    def test_found_returns_parsed_result(self, monkeypatch):
        _patch_key(monkeypatch)
        _patch_get(monkeypatch, FakeResponse({"documents": [_KAKAO_DOC]}))

        results = geocoding.geocode("제주 대정읍 상모리")

        assert len(results) == 1
        assert results[0].lat == 33.235
        assert results[0].lng == 126.293
        assert results[0].road_address == "제주특별자치도 서귀포시 대정읍 송악관광로 42"

    def test_road_address_none_when_kakao_omits_it(self, monkeypatch):
        _patch_key(monkeypatch)
        doc = {**_KAKAO_DOC, "road_address": None}
        _patch_get(monkeypatch, FakeResponse({"documents": [doc]}))

        results = geocoding.geocode("어딘가")

        assert results[0].road_address is None

    def test_not_found_returns_empty_list(self, monkeypatch):
        # 주소가 틀렸다는 뜻 — 예외가 아니라 빈 리스트여야 한다(라우터가 200으로 내려줌).
        _patch_key(monkeypatch)
        _patch_get(monkeypatch, FakeResponse({"documents": []}))

        assert geocoding.geocode("존재하지 않는 주소 zzz") == []

    def test_blank_address_returns_empty_without_calling(self, monkeypatch):
        _patch_key(monkeypatch)

        def _boom(*a, **k):
            raise AssertionError("빈 주소는 호출 없이 걸러야 한다")

        monkeypatch.setattr(geocoding.httpx, "get", _boom)

        assert geocoding.geocode("   ") == []

    def test_http_error_raises_geocoding_error(self, monkeypatch):
        _patch_key(monkeypatch)

        def _raise(*a, **k):
            raise httpx.ConnectError("boom")

        monkeypatch.setattr(geocoding.httpx, "get", _raise)

        with pytest.raises(geocoding.GeocodingError):
            geocoding.geocode("제주 어딘가")

    def test_kakao_5xx_raises_geocoding_error(self, monkeypatch):
        _patch_key(monkeypatch)
        _patch_get(monkeypatch, FakeResponse({}, status_code=500))

        with pytest.raises(geocoding.GeocodingError):
            geocoding.geocode("제주 어딘가")

    def test_missing_key_raises_geocoding_error(self, monkeypatch):
        _patch_key(monkeypatch, key=None)

        with pytest.raises(geocoding.GeocodingError):
            geocoding.geocode("제주 어딘가")
