import '../models/user_log.dart';
import '../network/api_client.dart';

/// API 계층: 행동 로그 전송. 서버 routers/user_logs.write_user_log에 대응한다.
class UserLogApi {
  UserLogApi(this._client);

  final ApiClient _client;

  /// 로그 묶음을 한 번에 보낸다(서버 상한 100건). 성공은 204, 검증 실패는 422.
  Future<void> writeUserLog(List<UserLog> logs) async {
    await _client.dio.post(
      '/user-logs',
      data: {
        'logs': [for (final log in logs) log.toJson()],
      },
    );
  }
}
