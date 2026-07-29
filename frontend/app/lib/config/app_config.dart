/// 빌드 시점에 주입되는 환경 설정.
///
/// 실행 예:
/// flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
class AppConfig {
  const AppConfig._();

  //default Natvie App Key
  static const String kakaoNativeAppKey = 'b996f6761bcc8585602205c0912bc007';

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  static bool get hasKakaoNativeAppKey => kakaoNativeAppKey.isNotEmpty;
}
