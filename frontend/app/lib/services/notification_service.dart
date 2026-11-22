import 'package:flutter/foundation.dart';

import '../api/notification_api.dart';
import '../models/app_notification.dart';

/// 비즈니스 로직 계층: 알림함. 푸시 수신은 [PushService]가 맡는다.
class NotificationService {
  NotificationService(this._api);

  final NotificationApi _api;

  /// 안 읽은 알림 수. 홈 벨 아이콘이 듣는다.
  final ValueNotifier<int> unreadCount = ValueNotifier(0);

  Future<List<AppNotification>> fetch({DateTime? before, int limit = 30}) =>
      _api.fetch(before: before, limit: limit);

  /// 실패하면 지금 값을 둔다 — 뱃지 하나 때문에 화면을 막지 않는다.
  Future<void> refreshUnread() async {
    try {
      unreadCount.value = await _api.unreadCount();
    } catch (_) {}
  }

  Future<void> markRead(String id) async {
    await _api.markRead(id);
    await refreshUnread();
  }

  Future<void> markAllRead() async {
    await _api.markAllRead();
    unreadCount.value = 0;
  }

  /// 로그아웃 시. 다음 계정에 앞사람의 수가 남지 않게.
  void reset() => unreadCount.value = 0;
}
