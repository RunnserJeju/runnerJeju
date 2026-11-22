import '../models/app_notification.dart';
import '../network/api_client.dart';
import '../network/json.dart';

/// API 계층: 기기 토큰 등록과 알림함.
class NotificationApi {
  NotificationApi(this._client);

  final ApiClient _client;

  Future<void> registerDevice({
    required String token,
    required String platform,
    required PushPermission permission,
    required String appVersion,
  }) => _client.dio.put(
    '/devices',
    data: {
      'token': token,
      'platform': platform,
      'permission': permission.wire,
      if (appVersion.isNotEmpty) 'app_version': appVersion,
    },
  );

  Future<void> unregisterDevice(String token) =>
      _client.dio.post('/devices/unregister', data: {'token': token});

  /// 최신순. 다음 쪽은 마지막 항목의 createdAt을 [before]로 넘긴다.
  Future<List<AppNotification>> fetch({DateTime? before, int limit = 30}) async {
    final response = await _client.dio.get(
      '/notifications',
      queryParameters: {
        'limit': limit,
        'before': ?before?.toUtc().toIso8601String(),
      },
    );
    return parseList(response.data, AppNotification.fromJson);
  }

  Future<int> unreadCount() async {
    final response = await _client.dio.get('/notifications/unread-count');
    return (response.data as Map<String, dynamic>)['count'] as int;
  }

  Future<void> markRead(String id) =>
      _client.dio.post('/notifications/$id/read');

  Future<void> markAllRead() => _client.dio.post('/notifications/read-all');
}
