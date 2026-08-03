import 'dart:math' as math;

import '../models/geo_point.dart';
import '../utils/geo_utils.dart';

/// 시뮬레이션 주행의 성향.
///
/// 값을 바꿔 "GPS가 잘 잡히는 날", "신호가 지저분한 날", "코스를 벗어난 주행" 같은
/// 상황을 만든다. 실제로 달려서는 원하는 때에 재현할 수 없는 것들이다.
class RunSimulationProfile {
  const RunSimulationProfile({
    this.paceSecondsPerKm = 330,
    this.paceWobble = 0.18,
    this.lateralDriftMeters = 4,
    this.gpsNoiseMeters = 2.5,
    this.interval = const Duration(seconds: 1),
    this.speedMultiplier = 1,
  });

  /// 목표 페이스(km당 초). 330 = 5분 30초/km.
  final double paceSecondsPerKm;

  /// 페이스가 흔들리는 폭(0~1). 0.18이면 목표 페이스의 ±18% 안에서 오르내린다.
  /// 신호등, 오르막, 사람 피하기 같은 이유로 실제 페이스는 결코 일정하지 않다.
  final double paceWobble;

  /// 코스 중심선에서 좌우로 벗어나는 폭(m).
  ///
  /// 코스는 도로 중앙선을 따라 그려져 있지만 사람은 인도나 갓길로 달린다.
  /// 이 값이 크면 코스 이탈 판정을 시험할 수 있다.
  final double lateralDriftMeters;

  /// 측정 자체에 섞이는 오차(m). 위 [lateralDriftMeters]보다 빠르게 변한다.
  final double gpsNoiseMeters;

  /// 위치를 보고하는 주기. 실제 GPS도 대략 1초에 한 번 올라온다.
  final Duration interval;

  /// 시간 배속. 20이면 6km 코스를 100초 남짓에 완주한다.
  final double speedMultiplier;

  /// 평범한 주행. 코스 위를 정상적으로 따라간다.
  static const normal = RunSimulationProfile();

  /// 완주까지 빠르게 돌려보는 용도.
  ///
  /// 배속만 올리면 한 점당 이동 거리가 그만큼 벌어져서 경로가 각지고 누적 거리도
  /// 실제와 달라진다. 보고 주기를 같은 배율로 줄여 점 간격은 [normal]과 같게 둔다.
  static const timeLapse = RunSimulationProfile(
    interval: Duration(milliseconds: 50),
    speedMultiplier: 20,
  );

  /// 신호가 나쁜 날. 점이 크게 튀어서 누적 거리가 부풀어 오른다.
  static const noisyGps = RunSimulationProfile(
    lateralDriftMeters: 9,
    gpsNoiseMeters: 12,
  );

  /// 코스를 벗어난 주행. 서버 검증이 이탈을 잡아내는지 확인할 때 쓴다.
  static const offCourse = RunSimulationProfile(
    lateralDriftMeters: 60,
    gpsNoiseMeters: 4,
  );
}

/// 폴리라인 위를 목표 페이스로 걸으면서 "실제로 달린 것 같은" 관측점을 만든다.
///
/// 이 파일은 Flutter에 의존하지 않는 순수 계산만 담는다. 위치 서비스로 감싸는 일은
/// `simulated_location_service.dart`가 하고, 여기는 `dart run`으로 바로 돌려
/// 수치를 검사할 수 있어야 하기 때문이다.
///
/// 무엇을 흉내내는가
/// ----------------
/// 코스 좌표를 그대로 재생하지 않는다. 그러면 현위치가 코스 선 위에 완벽히 박혀서
/// 움직이는데, 실제로는 절대 그렇게 되지 않는다. 대신 코스를 *따라가되*
/// 매 순간 조금씩 어긋난 점을 만든다:
///
/// - 코스 폴리라인 위를 목표 페이스로 보간해 나아간다(코스의 점 간격과 무관하게).
/// - 진행 방향의 수직으로 완만히 떠다니는 오프셋을 준다(갓길 주행).
/// - 그 위에 더 빠르게 변하는 측정 오차를 얹는다(GPS 지터).
/// - 페이스도 일정하지 않게 흔든다.
///
/// 잡음을 흰 잡음으로 주지 않고 전부 평균 회귀 랜덤워크([_wander])로 만든 것은
/// 의도적이다. 매 초 독립적으로 튀게 하면 점끼리의 거리가 실제 이동 거리보다
/// 훨씬 커져서 누적 거리가 몇 배로 부풀고, 실제 GPS 오차도 몇 초 단위로는 서로
/// 상관되어 천천히 흐른다.
class RunPathSimulator {
  RunPathSimulator({
    required List<GeoPoint> route,
    this.profile = RunSimulationProfile.normal,
    math.Random? random,
  }) : _route = route,
       _random = random ?? math.Random(),
       _cumulative = _cumulativeLengths(route);

  final List<GeoPoint> _route;
  final RunSimulationProfile profile;
  final math.Random _random;

  /// `_cumulative[i]` = 경로 시작점부터 `_route[i]`까지의 거리(m).
  final List<double> _cumulative;

  /// 지금까지 코스 위를 나아간 거리(m). 관측점이 아니라 "진짜" 위치다.
  double _traveled = 0;

  // 아래 값들은 전부 평균 회귀 랜덤워크로 천천히 흐른다.
  double _lateral = 0;
  double _noiseAcross = 0;
  double _noiseAlong = 0;
  double _paceFactor = 0;

  double get totalMeters => _cumulative.last;

  /// 코스 끝에 닿았는지. 닿은 뒤에는 제자리에서 흔들리기만 한다.
  /// 도착점 반경 안에 머물러야 완주 판정(`RunTracker.hasReachedCourseGoal`)을
  /// 확인할 수 있어서, 관측 자체를 멈추지는 않는다.
  bool get isFinished => _traveled >= totalMeters;

  /// 관측점 하나를 만든다. 호출할 때마다 [RunSimulationProfile.interval]만큼
  /// 시간이 흐른 것으로 친다.
  GeoPoint step() {
    _advance();

    final anchor = _positionAt(_traveled);
    final offsets = _offsetMeters();

    final latPerMeter = 1 / metersPerLatDegree;
    final lngPerMeter = 1 / metersPerLngDegree(anchor.latitude);

    return GeoPoint(
      latitude: anchor.latitude + offsets.north * latPerMeter,
      longitude: anchor.longitude + offsets.east * lngPerMeter,
      altitude: anchor.altitude,
      recordedAt: DateTime.now(),
    );
  }

  /// 시간을 기다리지 않고 코스 끝까지의 관측점을 한 번에 만든다.
  ///
  /// 실제 주기로 돌리면 6km 코스에 30분이 걸려서, 시뮬레이션이 코스를 제대로
  /// 따라가는지 수치로 확인할 때 쓴다. 주기를 줄여 빨리 끝내는 방식은 쓸 수 없다
  /// — 주기가 곧 점 간격이라 측정 대상 자체가 달라진다.
  ///
  /// [maxSamples]는 경로가 끝나지 않는 경우를 대비한 안전장치다.
  List<GeoPoint> runToFinish({int maxSamples = 100000}) {
    final samples = <GeoPoint>[];
    while (samples.length < maxSamples) {
      samples.add(step());
      if (isFinished) break;
    }
    return samples;
  }

  /// 이번 주기에 코스 위를 얼마나 나아갔는지 반영한다.
  void _advance() {
    if (isFinished) return;

    _paceFactor = _wander(_paceFactor, profile.paceWobble);

    // paceSecondsPerKm는 "1km에 몇 초"라서 속도는 그 역수다.
    final baseSpeed = 1000 / profile.paceSecondsPerKm;
    final speed = baseSpeed * (1 + _paceFactor) * profile.speedMultiplier;

    _traveled += speed * (profile.interval.inMilliseconds / 1000);
    if (_traveled > totalMeters) _traveled = totalMeters;
  }

  /// 코스 중심선 기준 오프셋을 진북/진동 성분(m)으로 만든다.
  ({double north, double east}) _offsetMeters() {
    _lateral = _wander(_lateral, profile.lateralDriftMeters);
    // 측정 오차는 코스와 무관한 방향으로 튀므로 진행 방향 성분도 따로 흔든다.
    _noiseAcross = _wander(_noiseAcross, profile.gpsNoiseMeters);
    _noiseAlong = _wander(_noiseAlong, profile.gpsNoiseMeters);

    final heading = _headingAt(_traveled);

    // heading은 단위벡터다. 수직(왼쪽) 방향은 (-east, north).
    final across = _lateral + _noiseAcross;
    return (
      north: -heading.east * across + heading.north * _noiseAlong,
      east: heading.north * across + heading.east * _noiseAlong,
    );
  }

  /// 시작점에서 [meters]만큼 간 지점의 좌표. 코스 점 사이는 선형 보간한다.
  ///
  /// 코스 점 간격은 수십 m라 그대로 재생하면 현위치가 뚝뚝 끊겨 움직인다.
  /// 보간해야 실제 GPS처럼 매끄럽게 흐른다.
  GeoPoint _positionAt(double meters) {
    final index = _segmentIndexAt(meters);
    final start = _route[index];
    final end = _route[index + 1];

    final segmentLength = _cumulative[index + 1] - _cumulative[index];
    final t = segmentLength <= 0
        ? 0.0
        : ((meters - _cumulative[index]) / segmentLength).clamp(0.0, 1.0);

    return GeoPoint(
      latitude: _lerp(start.latitude, end.latitude, t),
      longitude: _lerp(start.longitude, end.longitude, t),
      altitude: start.altitude == null || end.altitude == null
          ? null
          : _lerp(start.altitude!, end.altitude!, t),
    );
  }

  /// [meters] 지점에서 코스가 향하는 방향(단위벡터, 진북/진동 성분).
  ({double north, double east}) _headingAt(double meters) {
    final index = _segmentIndexAt(meters);
    final start = _route[index];
    final end = _route[index + 1];

    final north = (end.latitude - start.latitude) * metersPerLatDegree;
    final east =
        (end.longitude - start.longitude) * metersPerLngDegree(start.latitude);

    final length = math.sqrt(north * north + east * east);
    // 같은 좌표가 연달아 있으면 방향을 정할 수 없다. 임의로 북쪽을 쓴다.
    if (length == 0) return (north: 1, east: 0);

    return (north: north / length, east: east / length);
  }

  /// [meters]가 속한 구간의 시작점 인덱스.
  int _segmentIndexAt(double meters) {
    for (var i = 1; i < _cumulative.length; i++) {
      if (_cumulative[i] >= meters) return i - 1;
    }
    return _route.length - 2;
  }

  /// 평균 회귀 랜덤워크 한 걸음.
  ///
  /// 값은 대체로 ±[maxAbs] 안에 머물고, 벗어나면 잘라낸다.
  double _wander(double current, double maxAbs) {
    const reversion = 0.85;
    final kick = (_random.nextDouble() * 2 - 1) * maxAbs * 0.4;
    return (current * reversion + kick).clamp(-maxAbs, maxAbs);
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  static List<double> _cumulativeLengths(List<GeoPoint> route) {
    final result = <double>[0];
    for (var i = 1; i < route.length; i++) {
      result.add(
        result[i - 1] + GeoUtils.distanceBetween(route[i - 1], route[i]),
      );
    }
    return result;
  }
}

/// 코스 없이 시작한 자유 러닝에서 쓸 원형 경로.
List<GeoPoint> circularRoute(GeoPoint center, double radiusMeters) {
  const steps = 72;
  final latPerMeter = 1 / metersPerLatDegree;
  final lngPerMeter = 1 / metersPerLngDegree(center.latitude);

  return [
    for (var i = 0; i <= steps; i++)
      GeoPoint(
        latitude:
            center.latitude +
            math.sin(2 * math.pi * i / steps) * radiusMeters * latPerMeter,
        longitude:
            center.longitude +
            math.cos(2 * math.pi * i / steps) * radiusMeters * lngPerMeter,
      ),
  ];
}

/// 위도 1도의 길이(m). 위도와 무관하게 거의 일정하다.
const double metersPerLatDegree = 111320;

/// 경도 1도의 길이(m). 극으로 갈수록 짧아진다.
double metersPerLngDegree(double latitude) =>
    metersPerLatDegree * math.cos(latitude * math.pi / 180);
