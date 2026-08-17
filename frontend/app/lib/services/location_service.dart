import 'dart:io' show Platform;

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

/// 러닝 중 위치 수집이 끊긴 이유.
///
/// [LocationAvailability]와 나눠 둔 이유는 시점이 다르기 때문이다. 저쪽은 러닝을
/// **시작하기 전에** 물어보는 것이라 "설정을 열어 주세요"로 끝나지만, 이쪽은 이미
/// 달리고 있는 사람에게 "기록이 여기서 멈췄다"를 알리는 말이다.
enum LocationInterruption {
  serviceDisabled('기기의 위치 서비스가 꺼져서 기록을 멈췄어요'),
  permissionRevoked('위치 권한이 사라져서 기록을 멈췄어요'),
  lost('위치 신호가 끊겨서 기록을 멈췄어요');

  const LocationInterruption(this.message);

  final String message;
}

/// 비즈니스 로직 계층: GPS 권한과 위치 스트림을 앱 도메인 타입으로 감싼다.
/// UI는 geolocator 타입을 직접 알지 못한다.
class LocationService {
  /// 러닝 중 위치 수집 설정. 1m 이상 움직이면 바로 새 점을 받는다.
  ///
  /// 화면 갱신용 해상도다. 이 값이 크면 현위치 마커가 그만큼 띄엄띄엄 움직인다.
  /// 대신 1m 간격은 GPS 지터를 그대로 물고 오므로, 거리·커버리지 누적은
  /// [RunTracker]가 따로 5m 게이트를 걸어 거른다.
  ///
  /// 플랫폼별로 갈라야 백그라운드 수집이 유지된다 — 공통 [LocationSettings]만
  /// 쓰면 앱을 내리거나 화면을 끄는 순간 스트림이 멈춘다.
  /// - Android: [AndroidSettings.foregroundNotificationConfig]가 포그라운드
  ///   서비스를 띄워 OS가 서비스를 죽이지 않게 한다(상시 알림 동반).
  /// - iOS: [AppleSettings.allowBackgroundLocationUpdates]로 백그라운드 콜백을
  ///   유지한다("앱 사용 중" 권한 + Info.plist의 UIBackgroundModes=location 전제).
  ///
  /// 근거는 docs/background-tracking.md 참고.
  static LocationSettings get _trackingSettings {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 1,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: '러닝 기록 중',
          notificationText: '경로와 거리를 기록하고 있어요',
          enableWakeLock: true, // 화면이 꺼져도 CPU를 깨워 위치 콜백을 받는다.
        ),
      );
    }
    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 1,
        allowBackgroundLocationUpdates: true, // 백그라운드에서도 콜백 유지.
        showBackgroundLocationIndicator: true, // 상단 파란 표시줄.
        pauseLocationUpdatesAutomatically: false, // iOS가 임의로 멈추지 않게.
        activityType: ActivityType.fitness,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 1,
    );
  }

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
  ///
  /// 이 스트림은 러닝 도중에도 에러를 낸다 — 대표적으로 달리는 중에 기기의 위치
  /// 서비스를 끄는 경우다. 구독하는 쪽은 반드시 `onError`를 달아야 한다
  /// ([interruptionFrom]으로 사유를 읽을 수 있다).
  Stream<GeoPoint> trackPosition() => Geolocator.getPositionStream(
    locationSettings: _trackingSettings,
  ).map(_toGeoPoint);

  /// [trackPosition]이 낸 에러를 앱이 쓰는 사유로 바꾼다.
  ///
  /// geolocator 타입을 아는 곳을 이 파일 안에 묶어 두려고 여기 둔다 — 구독하는
  /// 쪽(RunTracker)은 받은 에러를 그대로 넘기기만 한다.
  LocationInterruption interruptionFrom(Object error) => switch (error) {
    LocationServiceDisabledException() => LocationInterruption.serviceDisabled,
    PermissionDeniedException() => LocationInterruption.permissionRevoked,
    _ => LocationInterruption.lost,
  };

  Future<void> openAppSettings() => Geolocator.openAppSettings();

  Future<void> openLocationSettings() => Geolocator.openLocationSettings();

  static GeoPoint _toGeoPoint(Position position) => GeoPoint(
    latitude: position.latitude,
    longitude: position.longitude,
    altitude: position.altitude,
    recordedAt: position.timestamp,
  );
}
