import 'dart:async';
import 'dart:math' as math;

import '../models/geo_point.dart';
import '../services/location_service.dart';
import 'run_path_simulator.dart';

export 'run_path_simulator.dart' show RunSimulationProfile;

/// GPS 대신 코스 경로를 따라 걷는 가짜 [LocationService].
///
/// 따라 달리기는 "현위치가 코스 위를 움직인다"가 전부인 기능이라, 확인하려면
/// 실제로 밖에 나가서 몇 km를 달려야 한다. 화면을 한 번 고칠 때마다 그럴 수는 없다.
///
/// 좌표를 만드는 계산은 [RunPathSimulator]에 있다. 이 클래스는 그것을 위치
/// 서비스의 모양(권한 확인, 위치 스트림)으로 감싸기만 한다.
class SimulatedLocationService implements LocationService {
  SimulatedLocationService({
    required this.route,
    this.profile = RunSimulationProfile.normal,
    int? seed,
  }) : _random = math.Random(seed);

  /// 따라 달릴 경로를 그때그때 알려주는 콜백.
  ///
  /// 코스는 러닝을 시작하는 순간 정해지므로 생성자에서 받을 수 없다.
  /// [trackPosition]이 불릴 때 한 번 읽는다.
  final List<GeoPoint> Function() route;

  final RunSimulationProfile profile;
  final math.Random _random;

  /// 코스 없이 시작한 자유 러닝에서 쓸 경로의 중심(제주시청)과 반경.
  static const GeoPoint _fallbackCenter = GeoPoint(
    latitude: 33.4996,
    longitude: 126.5312,
  );
  static const double _fallbackRadiusMeters = 400;

  @override
  Future<LocationAvailability> ensurePermission() async =>
      LocationAvailability.ready;

  @override
  Future<GeoPoint> currentPosition() async {
    final start = _resolveRoute().first;
    return GeoPoint(
      latitude: start.latitude,
      longitude: start.longitude,
      altitude: start.altitude,
      recordedAt: DateTime.now(),
    );
  }

  @override
  Stream<GeoPoint> trackPosition() {
    // 시뮬레이터를 스트림마다 새로 만든다. 러닝을 다시 시작하면 자연히
    // 출발점부터 다시 걷는다.
    final simulator = newSimulator();

    late final StreamController<GeoPoint> controller;
    Timer? timer;

    controller = StreamController<GeoPoint>(
      onListen: () {
        // 첫 점은 기다리지 않고 바로 준다. 실제 GPS도 구독 직후 마지막으로 알려진
        // 위치를 한 번 내려주고, 그래야 지도가 즉시 현위치를 잡는다.
        controller.add(simulator.step());
        timer = Timer.periodic(profile.interval, (_) {
          if (controller.isClosed) return;
          controller.add(simulator.step());
        });
      },
      onCancel: () {
        timer?.cancel();
        timer = null;
      },
    );

    return controller.stream;
  }

  @override
  Future<void> openAppSettings() async {
    // 시뮬레이션에는 권한 문제가 없으므로 열 설정이 없다.
  }

  @override
  Future<void> openLocationSettings() async {}

  /// 현재 설정으로 시뮬레이터를 하나 만든다.
  /// 스트림 없이 전체 경로를 뽑아보고 싶을 때도 쓴다([RunPathSimulator.runToFinish]).
  RunPathSimulator newSimulator() => RunPathSimulator(
    route: _resolveRoute(),
    profile: profile,
    random: _random,
  );

  /// 따라 달릴 경로를 정한다. 코스가 없으면(자유 러닝) 제주시청 둘레의 원을 만든다.
  List<GeoPoint> _resolveRoute() {
    final course = route();
    if (course.length >= 2) return course;
    return circularRoute(_fallbackCenter, _fallbackRadiusMeters);
  }
}
