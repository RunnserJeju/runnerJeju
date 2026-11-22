import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';

import '../api/notification_api.dart';
import '../models/app_notification.dart';
import 'local_notifications.dart';
import 'notification_service.dart';
import 'user_log_service.dart';

/// 눌린 알림 한 건. [link]는 `app:stamps` 같은 화면 키, [id]는 읽음 처리용.
typedef PushTap = ({String? link, String? id});

/// 푸시(FCM) 연결: 권한, 기기 토큰 등록, 수신, 눌렀을 때 넘겨주기.
///
/// 로그인한 동안만 돈다 — AppShell이 [start]하고 로그아웃이 [stop]한다. 화면은 모른다:
/// 눌린 알림은 [onTap]으로 넘기고, 권한은 [permission]으로 알린다.
class PushService with WidgetsBindingObserver {
  PushService(this._api, this._notifications, this._userLog);

  final NotificationApi _api;
  final NotificationService _notifications;
  final UserLogService _userLog;

  /// OS 알림 권한. 마이페이지의 "알림이 꺼져 있어요" 안내가 듣는다.
  final ValueNotifier<PushPermission> permission = ValueNotifier(
    PushPermission.notDetermined,
  );

  /// 알림을 눌렀을 때. AppShell이 건다. 걸리기 전에 눌린 건(종료 상태에서 눌러 실행)은
  /// 걸리는 순간 넘어간다.
  void Function(PushTap tap)? get onTap => _onTap;
  set onTap(void Function(PushTap tap)? handler) {
    _onTap = handler;
    final pending = _pendingTap;
    if (handler != null && pending != null) {
      _pendingTap = null;
      handler(pending);
    }
  }

  void Function(PushTap tap)? _onTap;
  PushTap? _pendingTap;

  bool _started = false;
  String? _token;

  /// 서버에 마지막으로 알린 (토큰, 권한). 같으면 다시 보내지 않는다.
  (String, PushPermission)? _synced;
  final List<StreamSubscription<Object?>> _subscriptions = [];

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  /// 로그인 뒤 한 번. 아직 묻지 않았으면 OS 권한 창을 띄운다(한 번 답하면 다시 안 뜬다).
  Future<void> start() async {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    try {
      await ensureLocalNotifications();
      onLocalNotificationTap = _onLocalTap;
      // iOS는 앱이 켜져 있어도 OS가 배너를 띄우게 한다. Android는 [_onForeground]가 띄운다.
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      _subscriptions
        ..add(FirebaseMessaging.onMessage.listen(_onForeground))
        ..add(FirebaseMessaging.onMessageOpenedApp.listen(_onOpened))
        ..add(_messaging.onTokenRefresh.listen(_onToken));

      final launched = await _messaging.getInitialMessage();
      if (launched != null) _onOpened(launched);

      var settings = await _messaging.getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.notDetermined) {
        settings = await _messaging.requestPermission();
      }
      permission.value = _toPermission(settings.authorizationStatus);

      _token = await _messaging.getToken();
      await _sync();
    } catch (e) {
      // 푸시가 안 돼도 앱은 쓴다(시뮬레이터, Play 서비스 없는 기기 등).
      debugPrint('push start failed: $e');
    }
    unawaited(_notifications.refreshUnread());
  }

  /// 로그아웃 직전(토큰이 아직 살아 있을 때). 이 기기로 앞사람의 알림이 가지 않게 한다.
  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    onLocalNotificationTap = null;
    _onTap = null;
    _pendingTap = null;
    _synced = null;
    _notifications.reset();
    final token = _token;
    if (token == null) return;
    try {
      await _api.unregisterDevice(token);
    } catch (_) {
      // 못 지워도 다음 로그인이 토큰의 주인을 바꾼다.
    }
  }

  /// 설정 앱의 이 앱 화면. 한 번 거부하면 OS 창이 다시 안 떠서 여기서만 켤 수 있다.
  Future<bool> openSettings() => Geolocator.openAppSettings();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 설정 앱에서 권한을 바꾸고 돌아왔을 수 있다.
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshPermission());
      unawaited(_notifications.refreshUnread());
    }
  }

  Future<void> _refreshPermission() async {
    try {
      final settings = await _messaging.getNotificationSettings();
      permission.value = _toPermission(settings.authorizationStatus);
      await _sync();
    } catch (_) {}
  }

  void _onToken(String token) {
    _token = token;
    unawaited(_sync());
  }

  Future<void> _sync() async {
    final token = _token;
    if (token == null || !_started) return;
    final next = (token, permission.value);
    if (next == _synced) return;
    try {
      await _api.registerDevice(
        token: token,
        platform: _userLog.platform,
        permission: permission.value,
        appVersion: _userLog.appVersion,
      );
      _synced = next;
    } catch (_) {
      // 다음 실행·복귀 때 다시 보낸다.
    }
  }

  void _onForeground(RemoteMessage message) {
    unawaited(_notifications.refreshUnread());
    final notification = message.notification;
    if (!Platform.isAndroid || notification == null) return;
    unawaited(
      localNotifications.show(
        id: message.hashCode,
        title: notification.title,
        body: notification.body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            pushChannel.id,
            pushChannel.name,
            channelDescription: pushChannel.description,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        payload: jsonEncode(message.data),
      ),
    );
  }

  void _onOpened(RemoteMessage message) => _deliver(message.data);

  void _onLocalTap(String? payload) {
    if (payload == null) return;
    try {
      _deliver(jsonDecode(payload) as Map<String, dynamic>);
    } catch (_) {}
  }

  void _deliver(Map<String, dynamic> data) {
    final PushTap tap = (
      link: data['link'] as String?,
      id: data['notification_id'] as String?,
    );
    open(tap);
  }

  /// 알림 한 건을 연다. 알림함에서 눌렀을 때도 이 길로 보내 푸시를 눌렀을 때와 똑같이 움직인다.
  void open(PushTap tap) {
    final handler = _onTap;
    if (handler == null) {
      _pendingTap = tap;
    } else {
      handler(tap);
    }
  }

  static PushPermission _toPermission(AuthorizationStatus status) =>
      switch (status) {
        AuthorizationStatus.authorized ||
        AuthorizationStatus.provisional => PushPermission.authorized,
        AuthorizationStatus.denied => PushPermission.denied,
        _ => PushPermission.notDetermined,
      };
}
