import 'dart:math' as math;

import '../models/geo_point.dart';

/// 위치 샘플을 시간축에 늘어놓고 "지금 이 순간 그릴 좌표"를 만든다.
///
/// 온라인 게임이 서버 스냅샷을 버퍼링해 조금 과거를 렌더하는 방식과 같다.
/// GPS는 몇 백 ms에 한 번 띄엄띄엄 오는데 화면은 그보다 자주 도니, 최신 점으로
/// 순간이동시키면 뚝뚝 끊긴다. [delay]만큼 과거를 렌더 시각으로 잡으면 그 시각을
/// 감싸는 두 점이 항상 있어서 사이를 채울 수 있다.
///
/// 이 클래스를 따로 두는 진짜 이유는 **마커와 경로 끝이 한 좌표를 공유**하게
/// 만들기 위해서다. 경로를 새 점까지 즉시 그리고 마커만 애니메이션으로 옮기면
/// 둘의 시각이 달라져 선이 마커를 앞질러 나간다.
class RunPathInterpolator {
  final List<_Sample> _samples = [];

  /// 점 사이 간격의 지수이동평균(ms). 첫 점만 있으면 null.
  double? _intervalMillis;
  Duration? _lastAt;
  bool _hasEmittedFirst = false;

  /// 직전 프레임에 다음 점이 없어 마지막 점에 멈춰 있었는지.
  bool _stalled = false;

  /// 렌더 지연의 하한. 실 GPS 배차(≈1초)의 지터를 흡수할 만큼은 잡아야
  /// 보간이 다음 점 도착 전에 끝나 멈추는 일이 드물다.
  static const int _minDelayMillis = 500;

  /// 렌더 지연의 상한. 이보다 뒤처지면 "현위치"라고 부르기 어렵다.
  static const int _maxDelayMillis = 1500;

  /// 점 간격에 곱해 지연을 정한다. 1보다 커야 다음 점이 오기 전에 보간이 끝나지
  /// 않아서, 마커가 도착 후 멈춰 서는 구간이 생기지 않는다.
  static const double _delayFactor = 1.3;

  /// 간격 추정에 반영하는 한 번의 최대 공백(ms). 터널처럼 오래 끊긴 구간 하나가
  /// 지연 추정을 통째로 끌어올리지 않게 자른다.
  static const int _maxIntervalMillis = 1500;

  /// 간격 추정의 반영 비율. 낮을수록 천천히 따라간다.
  static const double _intervalAlpha = 0.3;

  /// 지금 쓰는 렌더 지연. 점이 자주 올수록 짧아진다.
  Duration get delay {
    final interval = _intervalMillis;
    if (interval == null) {
      return const Duration(milliseconds: _minDelayMillis);
    }

    return Duration(
      milliseconds: (interval * _delayFactor).round().clamp(
        _minDelayMillis,
        _maxDelayMillis,
      ),
    );
  }

  /// 새 위치 샘플. [at]은 렌더 시계 기준 도착 시각이다.
  void add(GeoPoint point, Duration at) {
    final previous = _lastAt;
    if (previous != null) {
      final gap = math
          .min((at - previous).inMilliseconds, _maxIntervalMillis)
          .toDouble();
      final interval = _intervalMillis;
      _intervalMillis = interval == null
          ? gap
          : interval * (1 - _intervalAlpha) + gap * _intervalAlpha;
    }

    _lastAt = at;
    _samples.add(_Sample(point, at));
  }

  void clear() {
    _samples.clear();
    _intervalMillis = null;
    _lastAt = null;
    _hasEmittedFirst = false;
    _stalled = false;
  }

  /// 렌더 시계를 [now]까지 진행시키고 이번 프레임에 그릴 것을 돌려준다.
  ///
  /// `settled`는 렌더 시각을 막 지나 확정된 점들 — 경로 본선 뒤에 붙인다.
  /// `position`은 렌더 시각의 보간 좌표 — 마커와 경로 끝이 함께 쓴다.
  /// 샘플이 하나도 없으면 null.
  RunFrame? advanceTo(Duration now) {
    if (_samples.isEmpty) return null;

    final settled = _emitFirst();
    final renderTime = now - delay;

    // 멈춰 있던 중에 새 점이 도착했다. 시각 그대로 보간하면 t가 이미 커져 있어
    // 구간 중간까지 순간이동하므로, 구간 시작 시각을 지금으로 리베이스해서
    // 멈춘 지점부터 미끄러져 따라잡는다.
    if (_stalled && _samples.length > 1 && renderTime > _samples.first.at) {
      _samples[0] = _Sample(_samples.first.point, renderTime);
    }
    _stalled = false;

    // 렌더 시각이 다음 점을 지났으면 그 점을 확정하고 보간 구간을 한 칸 민다.
    // 직전 점 하나는 보간의 시작점으로 남겨 둔다.
    while (_samples.length > 1 && _samples[1].at <= renderTime) {
      _samples.removeAt(0);
      settled.add(_samples.first.point);
    }

    final from = _samples.first;
    // 다음 점이 아직 안 왔으면 마지막 점에 머문다. 신호가 끊겼을 때 위치를
    // 지어내는 것보다 멈춰 있는 편이 정직하다.
    if (_samples.length == 1) {
      _stalled = true;
      return (settled: settled, position: from.point);
    }

    final to = _samples[1];
    final span = (to.at - from.at).inMicroseconds;
    final t = span <= 0
        ? 1.0
        : ((renderTime - from.at).inMicroseconds / span).clamp(0.0, 1.0);

    return (settled: settled, position: _lerp(from.point, to.point, t));
  }

  /// 남은 샘플을 전부 확정하고 마지막 좌표에서 끝낸다.
  /// 일시정지·종료처럼 더 이상 점이 오지 않을 때 쓴다.
  RunFrame? settleAll() {
    if (_samples.isEmpty) return null;

    final settled = _emitFirst();
    while (_samples.length > 1) {
      _samples.removeAt(0);
      settled.add(_samples.first.point);
    }

    _stalled = false;
    return (settled: settled, position: _samples.first.point);
  }

  /// 첫 점은 경로의 시작이라 렌더 시각과 무관하게 바로 확정한다.
  List<GeoPoint> _emitFirst() {
    if (_hasEmittedFirst) return [];

    _hasEmittedFirst = true;
    return [_samples.first.point];
  }

  static GeoPoint _lerp(GeoPoint a, GeoPoint b, double t) => GeoPoint(
    latitude: a.latitude + (b.latitude - a.latitude) * t,
    longitude: a.longitude + (b.longitude - a.longitude) * t,
    altitude: a.altitude == null || b.altitude == null
        ? null
        : a.altitude! + (b.altitude! - a.altitude!) * t,
  );
}

/// 한 프레임에 그릴 것. `position`은 마커와 경로 끝이 공유하는 좌표다.
typedef RunFrame = ({List<GeoPoint> settled, GeoPoint position});

class _Sample {
  const _Sample(this.point, this.at);

  final GeoPoint point;

  /// 렌더 시계 기준 도착 시각.
  final Duration at;
}
