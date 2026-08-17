import 'package:flutter/foundation.dart';

/// 빌드 시점에 주입되는 환경 설정.
///
/// 배포 서버 등 다른 곳을 보게 하려면 주입한다:
/// flutter run --dart-define=API_BASE_URL=https://api.example.com
class AppConfig {
  const AppConfig._();

  //default Natvie App Key
  static const String kakaoNativeAppKey = 'b996f6761bcc8585602205c0912bc007';

  // 구글 클라우드 콘솔의 iOS 클라이언트 ID. Android는 패키지명+SHA-1로 콘솔이
  // 자동 매칭하므로 코드에 값이 필요 없다.
  static const String googleIosClientId =
      '425895001003-bac1rahppdlslvi732j1ptqt94fokp5a.apps.googleusercontent.com';

  // 구글 클라우드 콘솔의 "웹 애플리케이션" 클라이언트 ID. iOS/Android 양쪽 모두
  // serverClientId로 이 값을 넘겨서 idToken의 aud가 플랫폼과 무관하게 이 값
  // 하나로 고정되게 한다 — 서버(GOOGLE_CLIENT_ID)도 같은 값을 검증에 쓴다.
  static const String googleServerClientId =
      '425895001003-ih0unh7qark9fa1sadp45g78cobjftob.apps.googleusercontent.com';

  /// 운영 API 서버(Cloud Run, 서울). debug가 아닌 빌드(release·profile)가 본다.
  static const String prodApiBaseUrl =
      'https://runners-jeju-api-1090471391353.asia-northeast3.run.app';

  /// 서버 주소.
  ///
  /// debug가 아니면 운영을, debug면 로컬을 본다. --dart-define=API_BASE_URL 로
  /// 덮어쓸 수 있지만(스테이징 등), 개발 빌드로 운영에 붙는 건 막는다 — 테스트
  /// 계정·러닝 기록이 운영 DB에 섞이는 걸 방지한다.
  static String get apiBaseUrl {
    const injected = String.fromEnvironment('API_BASE_URL');

    if (!kDebugMode) {
      return injected.isNotEmpty ? injected : prodApiBaseUrl;
    }

    if (injected.isNotEmpty) {
      if (injected == prodApiBaseUrl) {
        throw StateError('debug 빌드로는 운영 서버에 붙을 수 없어요 ($injected).');
      }
      return injected;
    }

    // 안드로이드 에뮬레이터만 호스트를 10.0.2.2라는 별도 주소로 본다.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }

    // iOS 시뮬레이터 등 나머지는 호스트 네트워크를 그대로 쓴다(루프백).
    return 'http://127.0.0.1:8000';
  }

  static bool get hasKakaoNativeAppKey => kakaoNativeAppKey.isNotEmpty;
}
