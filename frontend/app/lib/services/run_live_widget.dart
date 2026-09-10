import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
///   (iOS 16.2+ 에서만 동작하고, 미만이면 조용히 no-op).
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
  /// ios/Runner/RunLiveActivityChannel.swift 와 짝. 값은 ActivityKit의
  /// ContentState 로 넘어가고 시스템이 위젯 프로세스에 전달한다 — App Group 같은
  /// 공유 저장소나 별도 capability 가 필요 없다.
  static const MethodChannel _iosChannel = MethodChannel(
    'com.runnersjeju.runnersJeju/run_live_activity',
  );

  /// Live Activity 가 떠 있는지. start 가 성공하면 켜지고 stop 에서 꺼진다.
  bool _iosStarted = false;

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
    _iosStarted = false;
    try {
      // 지원 여부(iOS 16.2+ · 사용자가 설정에서 끄지 않음)는 매번 다시 본다 —
      // 앱을 켜 둔 채 설정에서 바꿀 수 있어서 캐시하면 어긋난다.
      final supported =
          await _iosChannel.invokeMethod<bool>('isSupported') ?? false;
      if (!supported) return;
      // 네이티브가 이전 러닝의 활동을 걷고 새로 만든다. 앱이 죽으면 네이티브가
      // willTerminate 에서 활동도 걷는다 — 유령 위젯 방지.
      _iosStarted =
          await _iosChannel.invokeMethod<bool>('start', _iosData(data)) ??
          false;
    } catch (_) {
      _iosStarted = false;
    }
  }

  Future<void> _iosUpdate(RunWidgetData data) async {
    if (!_iosStarted) return;
    try {
      await _iosChannel.invokeMethod<void>('update', _iosData(data));
    } catch (_) {}
  }

  Future<void> _iosStop() async {
    _iosStarted = false;
    try {
      // 시작에 실패했더라도 혹시 남은 활동까지 확실히 걷는다.
      await _iosChannel.invokeMethod<void>('stop');
    } catch (_) {}
  }

  /// ContentState 필드. 키 이름은 ios/Runner/RunActivityAttributes.swift 와
  /// 같아야 한다.
  Map<String, dynamic> _iosData(RunWidgetData data) => {
    'distanceKm': Formatters.distanceKm(data.distanceMeters),
    'time': Formatters.duration(data.elapsed),
    'pace': Formatters.pace(data.paceSecondsPerKm),
    'paused': data.paused,
  };
}
