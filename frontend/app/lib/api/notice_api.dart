import '../models/notice.dart';
import '../network/api_client.dart';
import '../network/json.dart';

/// API 계층: 공지사항 관련 서버 엔드포인트.
class NoticeApi {
  NoticeApi(this._client);

  final ApiClient _client;

  Future<List<Notice>> fetchNotices() async {
    final response = await _client.dio.get('/notices');

    return parseList(response.data, Notice.fromJson);
  }
}
