import 'dart:io' show Platform;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 앱이 직접 띄우는 알림(Android)의 공용 초기화. 러닝 상시 알림과 푸시 배너가 같이 쓴다.
///
/// 플러그인은 초기화를 한 번만 받는다 — 두 곳이 따로 부르면 나중 것이 탭 콜백을 덮는다.
final FlutterLocalNotificationsPlugin localNotifications =
    FlutterLocalNotificationsPlugin();

/// 서버가 보내는 푸시의 채널. AndroidManifest의 기본 채널, 서버 app/fcm.py와 같은 id.
const AndroidNotificationChannel pushChannel = AndroidNotificationChannel(
  'default',
  '알림',
  description: '스탬프·쿠폰·이벤트 소식',
  importance: Importance.high,
);

/// 앱이 띄운 알림을 눌렀을 때. payload는 띄울 때 넣은 문자열.
void Function(String? payload)? onLocalNotificationTap;

Future<void>? _initialized;

Future<void> ensureLocalNotifications() => _initialized ??= _initialize();

Future<void> _initialize() async {
  if (!Platform.isAndroid) return;
  await localNotifications.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
    onDidReceiveNotificationResponse: (response) =>
        onLocalNotificationTap?.call(response.payload),
  );
  await localNotifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(pushChannel);
}
