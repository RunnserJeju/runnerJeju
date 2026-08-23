"""주소 → 좌표 변환(지오코딩). Kakao 로컬 API를 감싼다.

코스 등록 시 관리자가 입력한 주차장/화장실 주소를 좌표로 바꿔 저장하기 위한
모듈이다. 등록 화면의 "확인" 버튼이 `routers/geo.py`를 거쳐 이 함수를 호출한다.

Kakao REST API 키는 카카오 로그인이 쓰는 것과 같은 앱의 "REST API 키"다(지도
네이티브 앱 키와는 다른 값). `infra/.env`의 KAKAO_REST_API_KEY로만 존재해야
하고 앱(클라이언트)에는 넣지 않는다 — 그래서 이 호출을 프론트가 아니라 서버가 한다.

호출 결과는 세 갈래로 갈린다. 호출한 쪽(라우터)이 이 셋을 구분해 다른 응답을 준다:
  - 찾음        → GeocodeResult 1개 이상
  - 못 찾음     → 빈 리스트 (주소가 틀렸다는 뜻 — 사용자가 주소를 고쳐야 한다)
  - 호출 실패   → GeocodingError (네트워크/키 문제 — 재시도로 풀린다)
"""

import os
from dataclasses import dataclass

import httpx

KAKAO_REST_API_KEY = os.environ.get("KAKAO_REST_API_KEY")

# 주소 검색(도로명/지번 모두 지원). 좌표→주소나 키워드 검색은 다른 엔드포인트다.
KAKAO_LOCAL_ADDRESS_URL = "https://dapi.kakao.com/v2/local/search/address.json"


class GeocodingError(RuntimeError):
    """지오코딩 호출 자체가 실패했을 때(키 미설정, 네트워크, 카카오 5xx 등).

    '주소를 못 찾음'과는 구분된다 — 그쪽은 빈 리스트로 돌려준다.
    """


@dataclass
class GeocodeResult:
    """주소 후보 하나. 카카오는 한 질의에 여러 후보를 줄 수 있다."""

    # 지번 주소(카카오 address_name). 항상 채워진다.
    address: str
    # 도로명 주소. 카카오가 매칭한 경우에만 있고, 지번만 있는 곳은 None이다.
    road_address: str | None
    lat: float
    lng: float


def _to_result(document: dict) -> GeocodeResult:
    # 카카오 응답의 x=경도, y=위도(문자열로 온다). road_address는 null일 수 있다.
    road = document.get("road_address") or {}
    return GeocodeResult(
        address=document.get("address_name", ""),
        road_address=road.get("address_name"),
        lat=float(document["y"]),
        lng=float(document["x"]),
    )


def geocode(address: str) -> list[GeocodeResult]:
    """주소를 좌표 후보 목록으로 바꾼다. 못 찾으면 빈 리스트."""
    if not KAKAO_REST_API_KEY:
        raise GeocodingError(
            "KAKAO_REST_API_KEY가 설정되지 않았어요. infra/.env에 넣어주세요."
        )

    query = address.strip()
    if not query:
        return []

    try:
        response = httpx.get(
            KAKAO_LOCAL_ADDRESS_URL,
            params={"query": query},
            headers={"Authorization": f"KakaoAK {KAKAO_REST_API_KEY}"},
            timeout=5.0,
        )
        response.raise_for_status()
    except httpx.HTTPError as exc:
        raise GeocodingError("주소 좌표 변환에 실패했어요.") from exc

    documents = response.json().get("documents", [])
    return [_to_result(document) for document in documents]
