import '../models/run_record.dart';
import '../network/api_client.dart';
import '../network/json.dart';

/// API 계층: 러닝 기록 관련 서버 엔드포인트.
class RunApi {
  RunApi(this._client);

  final ApiClient _client;

  /// 러닝 기록 업로드. 코스 완주 조건을 만족하면 스탬프 id가 함께 내려온다.
  Future<RunUploadResult> uploadRecord(RunRecord record) async {
    final response = await _client.dio.post('/runs', data: record.toJson());
    return RunUploadResult.fromJson(response.data as Map<String, dynamic>);
  }

  /// 내 러닝 기록 목록(최근 순). [since] 이상 [until] 미만으로 거른다.
  /// [withPath]가 false면 경로가 빠진다(달력처럼 많이 받을 때).
  Future<List<RunRecord>> fetchMyRecords({
    int limit = 20,
    DateTime? since,
    DateTime? until,
    bool withPath = true,
  }) async {
    final response = await _client.dio.get(
      '/runs',
      queryParameters: {
        'limit': limit,
        if (since != null) 'since': since.toUtc().toIso8601String(),
        if (until != null) 'until': until.toUtc().toIso8601String(),
        if (!withPath) 'with_path': false,
      },
    );

    return parseList(response.data, RunRecord.fromJson);
  }

  Future<RunRecord> fetchRecord(String id) async {
    final response = await _client.dio.get('/runs/$id');
    return RunRecord.fromJson(response.data as Map<String, dynamic>);
  }
}
