import '../models/community_event.dart';
import '../network/api_client.dart';
import '../network/json.dart';

/// API 계층: 커뮤니티 이벤트.
class EventApi {
  EventApi(this._client);

  final ApiClient _client;

  Future<List<CommunityEvent>> fetchEvents() async {
    final response = await _client.dio.get('/events');
    return parseList(response.data, CommunityEvent.fromJson);
  }
}
