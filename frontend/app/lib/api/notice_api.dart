import '../models/notice.dart';
import '../network/api_client.dart';

/// API 계층: 공지사항 관련 서버 엔드포인트.
class NoticeApi {
  NoticeApi(this._client);

  final ApiClient _client;

  Future<List<Notice>> fetchNotices() async {
    final response = await _client.dio.get('/notices');

    return (response.data as List)
        .map((e) => Notice.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Notice> createNotice({required String title, required String body}) async {
    final response = await _client.dio.post(
      '/notices',
      data: {'title': title, 'body': body},
    );
    return Notice.fromJson(response.data as Map<String, dynamic>);
  }
}
