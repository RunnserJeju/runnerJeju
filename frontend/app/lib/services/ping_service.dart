import '../api/ping_api.dart';

class ConnectionCheckResult {
  ConnectionCheckResult.success(this.message) : isSuccess = true;

  ConnectionCheckResult.failure(this.message) : isSuccess = false;

  final bool isSuccess;
  final String message;
}

/// 비즈니스 로직 계층: API 계층을 감싸서 UI가 이해할 수 있는 결과로 바꿔준다.
class PingService {
  PingService(this._pingApi);

  final PingApi _pingApi;

  Future<ConnectionCheckResult> checkServerConnection() async {
    try {
      final response = await _pingApi.ping();
      return ConnectionCheckResult.success(response.message);
    } catch (e) {
      return ConnectionCheckResult.failure('연결 실패: $e');
    }
  }
}
