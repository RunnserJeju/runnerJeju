/// 빌드 시점에 주입되는 환경 설정.
///
/// 실행 예:
/// flutter run --dart-define=KAKAO_MAP_KEY=xxx --dart-define=KAKAO_NATIVE_APP_KEY=yyy --dart-define=API_BASE_URL=http://10.0.2.2:8000
class AppConfig {
  const AppConfig._();

  /// 카카오맵 JavaScript 앱 키. 키가 없으면 지도 위젯이 안내 화면으로 대체된다.
  static const String kakaoMapKey = String.fromEnvironment('KAKAO_MAP_KEY');

  /// 카카오 로그인 네이티브 앱 키. 카카오 개발자 콘솔에서 앱 등록 후 발급된다.
  static const String kakaoNativeAppKey = String.fromEnvironment(
    'KAKAO_NATIVE_APP_KEY',
  );

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  static bool get hasKakaoMapKey => kakaoMapKey.isNotEmpty;
  static bool get hasKakaoNativeAppKey => kakaoNativeAppKey.isNotEmpty;
}
