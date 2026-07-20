import 'package:geolocator/geolocator.dart';

import '../models/geo_point.dart';

/// 위치 권한 확인 결과.
enum LocationAvailability {
  ready('위치 사용 가능'),
  serviceDisabled('기기의 위치 서비스가 꺼져 있어요'),
  denied('위치 권한이 필요해요'),
  deniedForever('설정에서 위치 권한을 허용해 주세요');

  const LocationAvailability(this.message);

  final String message;

  bool get isReady => this == LocationAvailability.ready;
}

/// 비즈니스 로직 계층: GPS 권한과 위치 스트림을 앱 도메인 타입으로 감싼다.
/// UI는 geolocator 타입을 직접 알지 못한다.
class LocationService {
  /// 러닝 중 위치 수집 설정. 5m 이상 움직여야 새 점으로 인정한다.
  static const LocationSettings _trackingSettings = LocationSettings(
    accuracy: LocationAccuracy.best,
    distanceFilter: 5,
  );

  /// 권한 상태를 확인하고, 필요하면 사용자에게 요청한다.
  Future<LocationAvailability> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAvailability.serviceDisabled;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return switch (permission) {
      LocationPermission.denied => LocationAvailability.denied,
      LocationPermission.deniedForever => LocationAvailability.deniedForever,
      _ => LocationAvailability.ready,
    };
  }

  /// 현재 위치 1회 조회. 권한이 없으면 예외가 난다.
  Future<GeoPoint> currentPosition() async {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
    return _toGeoPoint(position);
  }

  /// 러닝 중 위치 스트림.
  Stream<GeoPoint> trackPosition() => Geolocator.getPositionStream(
    locationSettings: _trackingSettings,
  ).map(_toGeoPoint);

  Future<void> openAppSettings() => Geolocator.openAppSettings();

  Future<void> openLocationSettings() => Geolocator.openLocationSettings();

  static GeoPoint _toGeoPoint(Position position) => GeoPoint(
    latitude: position.latitude,
    longitude: position.longitude,
    altitude: position.altitude,
    recordedAt: position.timestamp,
  );
}
