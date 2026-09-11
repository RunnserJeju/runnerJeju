import '../models/run_stamp.dart';
import '../network/api_client.dart';
import '../network/json.dart';

/// API 계층: 완주 스탬프 관련 서버 엔드포인트.
class StampApi {
  StampApi(this._client);

  final ApiClient _client;

  /// 내가 보유한 완주 스탬프 목록.
  Future<List<RunStamp>> fetchMyStamps() async {
    final response = await _client.dio.get('/stamps');

    return parseList(response.data, RunStamp.fromJson);
  }

  Future<RunStamp> fetchStamp(String stampId) async {
    final response = await _client.dio.get('/stamps/$stampId');
    return RunStamp.fromJson(response.data as Map<String, dynamic>);
  }
}
