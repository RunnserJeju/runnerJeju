import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'current_location.dart';

/// 폰이 향한 방향(진북 기준, 0~360도). 러닝 지도의 현위치 삼각형이 쓴다.
///
/// 값은 네이티브가 OS 센서 융합으로 구해 보낸다(android HeadingStreamHandler.kt,
/// ios HeadingStreamHandler.swift). 여기서는 믿을 만한 값만 골라 평활한다.
/// 방향을 모르면 [heading]이 null이고, 지도는 삼각형을 숨긴다.
class HeadingService with WidgetsBindingObserver {
  HeadingService(this._currentLocation);

  final CurrentLocation _currentLocation;

  static const EventChannel _channel = EventChannel('runners_jeju/heading');

  /// 평활된 방향(도). 모르면 null.
  final ValueNotifier<double?> heading = ValueNotifier(null);

  /// 추정 오차가 이보다 크면 버린다. 삼각형이 30° 넘게 틀리면 없느니만 못하다.
  static const double _maxAccuracyDegrees = 30;

  /// 평활 시간상수. 걸음마다 흔들리는 값은 누르고, 몸을 돌리면 0.5초 안에 따라온다.
  static const double _smoothingSeconds = 0.15;

  /// 믿을 만한 값이 이만큼 끊기면 삼각형을 숨긴다. 한두 샘플 튀는 것으로
  /// 깜빡이지 않게 둔다.
  static const Duration _staleAfter = Duration(milliseconds: 1500);

  StreamSubscription<dynamic>? _subscription;
  bool _active = false;
  bool _hasLocation = false;

  // 각도를 그대로 평균하면 359°와 1°가 180°가 된다. 단위벡터 성분으로 평활한다.
  double? _x;
  double? _y;
  Duration? _lastSampleAt;
  final Stopwatch _clock = Stopwatch();
  Timer? _staleTimer;

  /// 러닝 화면에 들어올 때. 백그라운드에서는 알아서 멈췄다가 돌아오면 다시 켠다.
  void start() {
    if (_active) return;
    _active = true;
    WidgetsBinding.instance.addObserver(this);
    _listen();
  }

  void stop() {
    if (!_active) return;
    _active = false;
    WidgetsBinding.instance.removeObserver(this);
    _currentLocation.removeListener(_onLocation);
    _cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_active) return;
    if (state == AppLifecycleState.resumed) {
      if (_subscription == null) _listen();
    } else if (state == AppLifecycleState.paused) {
      _cancel();
    }
  }

  void _listen() {
    // 편각(자북→진북)은 위치로 구한다(안드로이드). 위치를 모르면 일단 켜 두고,
    // 첫 위치가 오면 한 번 다시 연다.
    final latest = _currentLocation.latest;
    _hasLocation = latest != null;
    if (!_hasLocation) _currentLocation.addListener(_onLocation);

    _clock
      ..reset()
      ..start();
    _subscription = _channel
        .receiveBroadcastStream({
          if (latest != null) 'lat': latest.latitude,
          if (latest != null) 'lng': latest.longitude,
        })
        .listen(
          _onEvent,
          // 센서가 없는 기기. 방향 없이(원만) 그린다.
          onError: (Object _) => _cancel(),
          cancelOnError: true,
        );
  }

  void _onLocation() {
    if (_hasLocation || _currentLocation.latest == null) return;
    _currentLocation.removeListener(_onLocation);
    if (_subscription == null) return;
    _cancel();
    _listen();
  }

  void _cancel() {
    _subscription?.cancel();
    _subscription = null;
    _staleTimer?.cancel();
    _staleTimer = null;
    _x = null;
    _y = null;
    _lastSampleAt = null;
    heading.value = null;
  }

  void _onEvent(dynamic event) {
    if (event is! Map) return;
    final degrees = (event['heading'] as num?)?.toDouble();
    final accuracy = (event['accuracy'] as num?)?.toDouble() ?? -1;
    final calibrated = event['calibrated'] == true;
    if (degrees == null || !_isReliable(accuracy, calibrated)) return;

    final now = _clock.elapsed;
    final radians = degrees * math.pi / 180;
    final x = math.sin(radians);
    final y = math.cos(radians);

    final last = _lastSampleAt;
    if (_x == null || last == null || now - last > _staleAfter) {
      _x = x;
      _y = y;
    } else {
      final dt = (now - last).inMicroseconds / 1e6;
      final alpha = 1 - math.exp(-dt / _smoothingSeconds);
      _x = _x! + (x - _x!) * alpha;
      _y = _y! + (y - _y!) * alpha;
    }
    _lastSampleAt = now;

    final value = math.atan2(_x!, _y!) * 180 / math.pi;
    heading.value = (value + 360) % 360;

    _staleTimer?.cancel();
    _staleTimer = Timer(_staleAfter, () => heading.value = null);
  }

  /// 오차를 알면 오차로, 모르면(-1) 센서 보정 상태로 판정한다.
  static bool _isReliable(double accuracy, bool calibrated) {
    if (accuracy >= 0) return accuracy <= _maxAccuracyDegrees;
    return calibrated;
  }
}
