import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:live_activities/live_activities.dart';

import '../utils/formatters.dart';

/// 잠금화면 위젯에 미러링할 러닝 한 컷.
///
/// [RunTracker]의 값을 그대로 담는 순수 DTO다 — 문자열 포매팅은 표시 계층에서
/// [Formatters]로 하고, 여기는 원본 숫자만 나른다.
class RunWidgetData {
  const RunWidgetData({
    required this.distanceMeters,
    required this.elapsed,
    required this.paceSecondsPerKm,
    required this.paused,
  });

  final double distanceMeters;
  final Duration elapsed;

  /// km당 초. 아직 못 잰 상태면 null.
  final double? paceSecondsPerKm;

  /// 지금 일시정지(또는 위치 끊김으로 멈춤) 상태인지. 위젯 라벨이 이걸 본다.
  final bool paused;
}

/// 러닝 상태를 잠금화면에 띄우는 "위젯" 계층.
///
/// 데이터 파이프라인(위치·거리·시간)은 [RunTracker]가 이미 백그라운드에서
/// 굴린다. 이 클래스는 순수 표시 계층으로, 그 값을 화면 밖(잠금화면)으로
/// 미러링만 한다 — tracker/위치/서버 코드는 건드리지 않는다.
///
/// - Android: 갱신되는 상시(ongoing) 알림. 잠금화면에 거리·시간·페이스를 띄운다.
/// - iOS: Live Activity(ActivityKit). 잠금화면 + Dynamic Island에 같은 값을 띄운다
///   (iOS 16.1+ 에서만 동작하고, 미만이면 조용히 no-op).
class RunLiveWidget {
  RunLiveWidget();

  // ── 공통(throttle) ────────────────────────────────────────────────
  bool _active = false;

  /// 마지막으로 위젯을 갱신한 시각. tracker는 위치마다도 notify하므로
  /// (초당 여러 번) 과잉 갱신을 막으려고 ~1초로 throttle한다.
  DateTime? _lastPush;
  bool? _lastPaused;
  static const Duration _minInterval = Duration(seconds: 1);

  // ── Android: flutter_local_notifications ─────────────────────────
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// 하나의 알림을 계속 갱신한다 — 매 틱 새 알림을 쌓지 않도록 id를 고정한다.
  static const int _notificationId = 7001;
  static const String _channelId = 'run_live_widget';
  bool _androidInitialized = false;

  // ── iOS: Live Activity(ActivityKit) ──────────────────────────────
  final LiveActivities _liveActivities = LiveActivities();

  /// Runner ↔ Widget Extension 이 공유하는 App Group. Xcode에서 두 타겟 모두에
  /// 같은 값으로 등록해야 데이터가 위젯까지 넘어간다(ios/RunLiveActivity/README 참고).
  static const String _appGroupId = 'group.com.runnersjeju.runnersJeju';
  bool _iosInitialized = false;
  bool _iosSupported = false;

  /// 진행 중인 Live Activity id. update/end에 쓴다.
  String? _activityId;

  /// 러닝 시작 시 1회. 채널·권한 준비 후 위젯을 띄운다.
  Future<void> start(RunWidgetData data) async {
    _active = true;
    _lastPush = null;
    _lastPaused = null;
    if (Platform.isAndroid) {
      await _androidEnsureInit();
      await _androidPush(data, force: true);
    } else if (Platform.isIOS) {
      await _iosStart(data);
    }
  }

  /// 매 틱 호출. throttle에 걸리면 조용히 건너뛴다.
  Future<void> update(RunWidgetData data) async {
    if (!_active) return;

    final now = DateTime.now();
    final last = _lastPush;
    // 상태(일시정지↔재개)가 바뀌면 라벨이 즉시 바뀌어야 하니 throttle을 건너뛴다.
    final statusChanged = _lastPaused != data.paused;
    if (!statusChanged && last != null && now.difference(last) < _minInterval) {
      return;
    }
    _lastPush = now;
    _lastPaused = data.paused;

    if (Platform.isAndroid) {
      await _androidPush(data);
    } else if (Platform.isIOS) {
      await _iosUpdate(data);
    }
  }

  /// 러닝 종료·화면 이탈 시. 잠금화면에 위젯이 남지 않게 반드시 부른다.
  Future<void> stop() async {
    _active = false;
    _lastPush = null;
    _lastPaused = null;
    if (Platform.isAndroid) {
      await _plugin.cancel(id: _notificationId);
    } else if (Platform.isIOS) {
      await _iosStop();
    }
  }

  // ── Android 구현 ─────────────────────────────────────────────────

  Future<void> _androidEnsureInit() async {
    if (_androidInitialized) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      settings: const InitializationSettings(android: androidInit),
    );

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    // Android 13(API 33)+ 는 알림 표시에 런타임 권한이 필요하다. 거부돼도
    // 러닝 자체는 정상 동작하므로 결과를 강제하지 않는다.
    await android?.requestNotificationsPermission();

    _androidInitialized = true;
  }

  Future<void> _androidPush(RunWidgetData data, {bool force = false}) async {
    if (!_active && !force) return;

    final title = data.paused ? '러닝 일시정지' : '러닝 중';
    final body = _body(data);

    const details = AndroidNotificationDetails(
      _channelId,
      '러닝 상태',
      channelDescription: '러닝 중 거리·시간·페이스를 잠금화면에 표시해요',
      // 소리·헤드업 없이 조용히 갱신되게 낮은 중요도로 둔다.
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true, // 스와이프로 지워지지 않는다.
      autoCancel: false,
      onlyAlertOnce: true, // 갱신마다 소리·진동 없이.
      playSound: false,
      enableVibration: false,
      showWhen: false,
      // 잠금화면에 내용까지 노출한다(민감 정보 아님).
      visibility: NotificationVisibility.public,
      category: AndroidNotificationCategory.status,
    );

    await _plugin.show(
      id: _notificationId,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(android: details),
    );
  }

  /// "5.23 km · 32:41 · 5'42\"" — 화면과 같은 포맷을 재사용한다.
  String _body(RunWidgetData data) =>
      '${Formatters.distanceKm(data.distanceMeters)} km'
      ' · ${Formatters.duration(data.elapsed)}'
      ' · ${Formatters.pace(data.paceSecondsPerKm)}';

  // ── iOS 구현 ─────────────────────────────────────────────────────

  Future<void> _iosStart(RunWidgetData data) async {
    if (!await _iosEnsureInit()) return;

    // 이전 러닝의 활동이 남아 있으면 걷어내고 새로 만든다.
    try {
      await _liveActivities.endAllActivities();
    } catch (_) {}

    try {
      _activityId = await _liveActivities.createActivity(
        DateTime.now().millisecondsSinceEpoch.toString(),
        _iosData(data),
        // 앱이 죽으면 시스템이 활동도 걷게 한다 — 유령 위젯 방지.
        removeWhenAppIsKilled: true,
        // 푸시로 원격 갱신하지 않는다 — 앱에서 직접 update한다. true(기본)면
        // Push Notifications capability가 필요하고, 없으면 Activity.request가
        // ActivityKit.ActivityInput error 0으로 실패한다.
        iOSEnableRemoteUpdates: false,
      );
    } catch (_) {
      _activityId = null;
    }
  }

  Future<void> _iosUpdate(RunWidgetData data) async {
    final id = _activityId;
    if (id == null) return;
    try {
      await _liveActivities.updateActivity(id, _iosData(data));
    } catch (_) {}
  }

  Future<void> _iosStop() async {
    final id = _activityId;
    _activityId = null;
    try {
      // id가 있으면 그것만, 없더라도 혹시 남은 활동까지 확실히 걷는다.
      if (id != null) {
        await _liveActivities.endActivity(id);
      } else {
        await _liveActivities.endAllActivities();
      }
    } catch (_) {}
  }

  /// App Group을 붙이고 Live Activity 지원 여부를 확인한다.
  /// 지원 안 함(iOS<16.1 · 사용자가 끔)이면 false — 이후 호출은 전부 no-op.
  Future<bool> _iosEnsureInit() async {
    if (_iosInitialized) return _iosSupported;
    try {
      await _liveActivities.init(appGroupId: _appGroupId);
      _iosSupported = await _liveActivities.areActivitiesEnabled();
    } catch (_) {
      _iosSupported = false;
    }
    _iosInitialized = true;
    return _iosSupported;
  }

  /// Widget Extension이 읽을 키/값. UserDefaults(App Group)로 넘어가므로
  /// 문자열 위주로 담는다(SwiftUI가 prefixedKey로 읽음 — ios/RunLiveActivity 참고).
  Map<String, dynamic> _iosData(RunWidgetData data) => {
    'distanceKm': Formatters.distanceKm(data.distanceMeters),
    'time': Formatters.duration(data.elapsed),
    'pace': Formatters.pace(data.paceSecondsPerKm),
    'paused': data.paused,
  };
}
