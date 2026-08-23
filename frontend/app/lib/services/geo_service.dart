import '../api/geo_api.dart';
import '../exceptions/app_exception.dart';

/// 주소 → 좌표 변환. 등록 화면의 "확인" 버튼이 쓴다.
///
/// 결과는 세 갈래다. 화면이 "주소를 고쳐야 하는지"와 "재시도하면 되는지"를
/// 구분할 수 있게, 이 계층에서 갈래를 명확히 나눈다:
///   - 후보 1개+ 반환   → 찾음
///   - **빈 목록 반환**  → 주소를 못 찾음(주소가 틀렸다는 뜻)
///   - AppException      → 호출 실패(네트워크/서버 — 재시도 대상)
class GeoService {
  GeoService(this._geoApi);

  final GeoApi _geoApi;

  Future<List<GeoCandidate>> geocode(String address) async {
    try {
      return await _geoApi.geocode(address);
    } catch (e) {
      throw AppException('주소를 확인하지 못했어요. 잠시 후 다시 시도해 주세요.', e);
    }
  }
}
