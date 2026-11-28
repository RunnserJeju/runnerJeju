import '../network/api_client.dart';

/// API 계층: 원격 설정. 서버 routers/app_settings.py에 대응한다.
class AppSettingsApi {
  AppSettingsApi(this._client);

  final ApiClient _client;

  Future<Map<String, Object?>> fetch() async {
    final response = await _client.dio.get<Map<String, dynamic>>('/app-settings');
    return response.data ?? const {};
  }
}
