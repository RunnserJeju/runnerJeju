import '../api/event_api.dart';
import '../exceptions/app_exception.dart';
import '../models/community_event.dart';
import 'cached_resource.dart';

/// 비즈니스 로직 계층: 커뮤니티 이벤트 조회.
class EventService {
  EventService(this._eventApi);

  final EventApi _eventApi;

  late final _events = CachedResource<List<CommunityEvent>>(
    (etag) => _eventApi.fetchEvents(etag: etag),
  );

  Future<List<CommunityEvent>> loadEvents({bool refresh = false}) async {
    try {
      return List.of(await _events.get(refresh: refresh));
    } catch (e) {
      throw AppException('이벤트를 불러오지 못했어요.', e);
    }
  }
}
