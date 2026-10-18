import '../api/event_api.dart';
import '../exceptions/app_exception.dart';
import '../models/community_event.dart';

/// 비즈니스 로직 계층: 커뮤니티 이벤트 조회.
class EventService {
  EventService(this._eventApi);

  final EventApi _eventApi;

  Future<List<CommunityEvent>> loadEvents() async {
    try {
      return await _eventApi.fetchEvents();
    } catch (e) {
      throw AppException('이벤트를 불러오지 못했어요.', e);
    }
  }
}
