import 'package:url_launcher/url_launcher.dart';

import '../models/geo_point.dart';

/// 카카오맵 앱(없으면 모바일 웹)으로 길찾기를 띄운다.
///
/// 앱 내에서 길을 안내하지는 않는다 — 코스 시작점까지 데려다주는 건 지도 앱이
/// 훨씬 잘하는 일이고, [kakao_map_sdk]는 지도를 그리기만 할 뿐 경로 탐색도,
/// 외부 앱 실행도 제공하지 않는다.
class KakaoMapLauncher {
  const KakaoMapLauncher();

  /// 앱 스킴과 모바일 웹 주소는 파라미터가 같다. 그래서 쿼리를 한 번만 만들고
  /// 앞부분만 갈아 끼운다.
  static const String _appScheme = 'kakaomap://route';
  static const String _webScheme = 'https://m.map.kakao.com/scheme/route';

  /// [from]에서 [to]까지 도보 길찾기를 연다. 실제로 열렸으면 true.
  ///
  /// 카카오맵이 깔려 있으면 앱으로, 아니면 모바일 웹으로 간다. 커스텀 스킴은
  /// 처리할 앱이 없을 때 브라우저로 넘어가 주지 않고 그냥 실패하므로, 열리는지
  /// 먼저 물어보고 갈라야 한다.
  Future<bool> openWalkingRoute({
    required GeoPoint from,
    required GeoPoint to,
  }) async {
    final query = '?sp=${_coord(from)}&ep=${_coord(to)}&by=FOOT';

    final app = Uri.parse('$_appScheme$query');
    if (await canLaunchUrl(app)) {
      // 앱이 있는데 실패했다면 iOS 시스템 팝업에서 취소한 것이다. 웹으로
      // 넘기면 웹이 다시 앱을 띄워 취소가 무시된 것처럼 보인다(#64).
      // 사용자가 거절한 것이므로 '열지 못함' 메시지도 내지 않게 true.
      await launchUrl(app);
      return true;
    }

    // 웹은 반드시 외부 브라우저로 띄운다. 인앱 웹뷰로 열면 카카오맵 웹이
    // "앱으로 보기"를 걸어도 돌아올 곳이 없다.
    return launchUrl(
      Uri.parse('$_webScheme$query'),
      mode: LaunchMode.externalApplication,
    );
  }

  /// [point]에 [name] 핀을 꽂은 카카오맵을 연다. 출발지(현위치)를 몰라 길찾기를
  /// 못 할 때 쓴다 — 카카오맵에서 "길찾기"를 누르면 거기서 현위치를 잡아 준다.
  Future<bool> openPlace({required String name, required GeoPoint point}) {
    final label = Uri.encodeComponent(name.replaceAll(',', ' '));
    return launchUrl(
      Uri.parse('https://map.kakao.com/link/map/$label,${_coord(point)}'),
      mode: LaunchMode.externalApplication,
    );
  }

  static String _coord(GeoPoint point) =>
      '${point.latitude},${point.longitude}';
}
