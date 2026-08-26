"""주소 → 좌표 변환 프록시. 코스 등록 화면의 "확인" 버튼이 호출한다. (운영자 전용)

Kakao REST 키를 앱에 노출하지 않으려고 서버가 대신 호출한다(app/geocoding.py 참고).
코스 등록과 마찬가지로 관리자 전용이라 /admin 아래에 둔다.
"""

from fastapi import APIRouter, HTTPException, Query

from app import geocoding
from app.schemas import GeocodeResponse

router = APIRouter(tags=["geo"])


@router.get("/geo/geocode", response_model=GeocodeResponse)
def geocode_address(
    address: str = Query(..., min_length=1, description="변환할 도로명/지번 주소"),
):
    """주소를 좌표 후보 목록으로 바꾼다. (관리자 전용 — 라우터 레벨에서 강제)

    응답은 세 갈래다. 클라이언트가 "주소를 고쳐야 하는지"와 "재시도하면 되는지"를
    구분할 수 있어야 하기 때문이다:
      - 200 + results 1개 이상 → 찾음
      - 200 + results 빈 배열   → 주소를 못 찾음(주소가 틀렸다는 뜻)
      - 502                     → 호출 실패(네트워크/키 문제 — 재시도 대상)
    """
    try:
        results = geocoding.geocode(address)
    except geocoding.GeocodingError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    return GeocodeResponse(results=results)
