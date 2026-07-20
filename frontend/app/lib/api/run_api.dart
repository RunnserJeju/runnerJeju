import '../models/run_record.dart';
import '../network/api_client.dart';

/// API 계층: 러닝 기록 관련 서버 엔드포인트.
class RunApi {
  RunApi(this._client);

  final ApiClient _client;

  /// 러닝 기록 업로드. 코스 완주 조건을 만족하면 스탬프 id가 함께 내려온다.
  Future<RunUploadResult> uploadRecord(RunRecord record) async {
    final response = await _client.dio.post('/runs', data: record.toJson());
    return RunUploadResult.fromJson(response.data as Map<String, dynamic>);
  }

  /// 내 러닝 기록 목록.
  Future<List<RunRecord>> fetchMyRecords({int limit = 20}) async {
    final response = await _client.dio.get(
      '/runs',
      queryParameters: {'limit': limit},
    );

    return (response.data as List)
        .map((e) => RunRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
