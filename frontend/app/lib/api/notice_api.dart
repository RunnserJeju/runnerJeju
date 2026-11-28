import '../models/notice.dart';
import '../network/api_client.dart';
import '../network/conditional.dart';
import '../network/json.dart';

/// API 계층: 공지사항 관련 서버 엔드포인트.
class NoticeApi {
  NoticeApi(this._client);

  final ApiClient _client;

  Future<Conditional<List<Notice>>> fetchNotices({String? etag}) =>
      _client.getConditional(
        '/notices',
        etag: etag,
        parse: (data) => parseList(data, Notice.fromJson),
      );
}
