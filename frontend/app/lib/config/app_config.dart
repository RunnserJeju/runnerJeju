import 'package:flutter/foundation.dart';

/// 빌드 시점에 주입되는 환경 설정.
///
/// 배포 서버 등 다른 곳을 보게 하려면 주입한다:
/// flutter run --dart-define=API_BASE_URL=https://api.example.com
class AppConfig {
  const AppConfig._();

  //default Natvie App Key
  static const String kakaoNativeAppKey = 'b996f6761bcc8585602205c0912bc007';

  /// 서버 주소. --dart-define=API_BASE_URL 로 덮어쓸 수 있고, 없으면 플랫폼별
  /// 로컬 개발 서버를 가리킨다.
  static String get apiBaseUrl {
    const injected = String.fromEnvironment('API_BASE_URL');
    if (injected.isNotEmpty) return injected;

    // 안드로이드 에뮬레이터만 호스트를 10.0.2.2라는 별도 주소로 본다.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }

    // iOS 시뮬레이터 등 나머지는 호스트 네트워크를 그대로 쓴다(루프백).
    return 'http://127.0.0.1:8000';
  }

  static bool get hasKakaoNativeAppKey => kakaoNativeAppKey.isNotEmpty;
}
