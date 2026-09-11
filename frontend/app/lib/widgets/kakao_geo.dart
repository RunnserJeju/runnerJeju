// 카카오맵 SDK는 머티리얼과 겹치는 이름을 내보내므로 접두사를 붙인다.
import 'package:kakao_map_sdk/kakao_map_sdk.dart' as kakao;

import '../models/geo_point.dart';

/// 도메인 좌표 → 카카오맵 좌표. 지도 위젯 여럿이 같은 변환을 쓴다.
/// GeoPoint 모델 자체는 순수 Dart로 두어야 해서(콘솔 도구가 씀) 여기 둔다.
extension GeoPointLatLng on GeoPoint {
  kakao.LatLng toLatLng() => kakao.LatLng(latitude, longitude);
}
