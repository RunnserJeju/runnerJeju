import '../models/community_event.dart';
import '../network/api_client.dart';
import '../network/conditional.dart';
import '../network/json.dart';

/// API 계층: 커뮤니티 이벤트.
class EventApi {
  EventApi(this._client);

  final ApiClient _client;

  Future<Conditional<List<CommunityEvent>>> fetchEvents({String? etag}) =>
      _client.getConditional(
        '/events',
        etag: etag,
        parse: (data) => parseList(data, CommunityEvent.fromJson),
      );
}
