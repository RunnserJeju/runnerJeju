import '../models/run_verification.dart';
import '../network/api_client.dart';

/// API 계층: 경로 검증 엔드포인트.
///
/// 클라이언트는 항상 FastAPI에만 요청한다. 실제 GPX 비교 연산이 별도 검증 서버로
/// 옮겨가더라도 FastAPI가 그 앞단을 유지하므로 이 API 계약은 그대로다.
class VerificationApi {
  VerificationApi(this._client);

  final ApiClient _client;

  /// 검증 요청. 즉시 끝나지 않을 수 있으므로 pending 상태가 돌아올 수 있다.
  Future<RunVerification> requestVerification({
    required String runId,
    required String courseId,
  }) async {
    final response = await _client.dio.post(
      '/runs/$runId/verification',
      data: {'course_id': courseId},
    );

    return RunVerification.fromJson(response.data as Map<String, dynamic>);
  }

  /// 진행 중인 검증의 현재 상태 조회(폴링용).
  Future<RunVerification> fetchVerification(String verificationId) async {
    final response = await _client.dio.get('/verifications/$verificationId');
    return RunVerification.fromJson(response.data as Map<String, dynamic>);
  }
}
