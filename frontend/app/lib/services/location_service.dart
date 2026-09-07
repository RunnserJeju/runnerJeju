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
enum LocationInterruption {
  serviceDisabled('기기의 위치 서비스가 꺼져서 기록을 멈췄어요'),
  permissionRevoked('위치 권한이 사라져서 기록을 멈췄어요'),
  lost('위치 신호가 끊겨서 기록을 멈췄어요');

  const LocationInterruption(this.message);

  final String message;
}


class LocationService {
  /// 러닝 중 위치 수집 설정. 1m 이상 움직이면 바로 새 점을 받는다.
  /// 플랫폼별로 갈라야 백그라운드 수집이 유지된다 — 공통 [LocationSettings]만 쓰면 앱을 내리거나 화면을 끄는 순간 스트림이 멈춘다.
  /// - Android: [AndroidSettings.foregroundNotificationConfig]가 포그라운드
  ///   서비스를 띄워 OS가 서비스를 죽이지 않게 한다(상시 알림 동반)
  /// - iOS: [AppleSettings.allowBackgroundLocationUpdates]로 백그라운드 콜백을
  ///   유지한다("앱 사용 중" 권한 + Info.plist의 UIBackgroundModes=location 전제).
  
  static const int minMeter = 1;

  static LocationSettings get _trackingSettings {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: minMeter,
        // 기본값은 5초다(geolocator LocationOptions). iOS는 매초 주는데 Android만
        // 5초면 5m 게이트를 넘는 점이 드문드문 들어와 초반 페이스가 계단처럼 튄다.
        intervalDuration: const Duration(seconds: 1),
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
        distanceFilter: minMeter,
        allowBackgroundLocationUpdates: true, // 백그라운드에서도 콜백 유지.
        showBackgroundLocationIndicator: true, // 상단 파란 표시줄.
        pauseLocationUpdatesAutomatically: false, // iOS가 임의로 멈추지 않게.
        activityType: ActivityType.fitness,
      );
    }
    //else?
    return const LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: minMeter,
    );
  }

  /// 평상시(러닝 밖) 위치 스트림 설정. [CurrentLocation]이 쓴다.
  ///
  /// 정확도는 러닝과 같은 GPS급이다. 지도 화면의 내 위치 점과 코스 시작점까지의
  /// 거리 판정(100m 문턱)에 쓰이는데, Wi-Fi급(100m 안팎)이면 그 판정이 흔들린다.
  /// 대신 10m 단위로만 받아 러닝(1m)보다 훨씬 성기고, 포그라운드 서비스나
  /// 백그라운드 갱신은 걸지 않는다 — 앱이 뒤로 가면 닫히는 게 맞다.
  static const int _ambientMeters = 10;

  static LocationSettings get _ambientSettings {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: _ambientMeters,
        intervalDuration: const Duration(seconds: 2),
      );
    }
    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: _ambientMeters,
        activityType: ActivityType.fitness,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: _ambientMeters,
    );
  }

  /// 권한 상태만 본다. 사용자에게 요청하지는 않는다.
  Future<LocationAvailability> checkAvailability() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAvailability.serviceDisabled;
    }
    return _toAvailability(await Geolocator.checkPermission());
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

    return _toAvailability(permission);
  }

  static LocationAvailability _toAvailability(LocationPermission permission) =>
      switch (permission) {
        LocationPermission.denied => LocationAvailability.denied,
        LocationPermission.deniedForever => LocationAvailability.deniedForever,
        _ => LocationAvailability.ready,
      };

  /// 현재 위치 1회 조회. 권한이 없으면 예외가 난다.
  ///
  /// [timeLimit]을 주면 그 안에 좌표를 못 잡을 때 TimeoutException을 낸다.
  /// 사용자를 기다리게 해 놓고 조회하는 자리(러닝 시작 직전)에서 쓴다 — 실내처럼
  /// 위성이 안 잡히는 곳에서 getCurrentPosition은 한없이 기다릴 수 있다.
  Future<GeoPoint> currentPosition({Duration? timeLimit}) async {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: timeLimit,
      ),
    );
    return _toGeoPoint(position);
  }

  /// 평상시 위치 스트림. 설정은 [_ambientSettings] 참고.
  ///
  /// [trackPosition]과 동시에 열 수 없다. geolocator는 플랫폼당 스트림을 하나만
  /// 두고, 열린 채로 다시 요청하면 새 설정을 무시하고 그 스트림을 돌려준다.
  /// 교대는 [CurrentLocation]이 맡는다.
  Stream<GeoPoint> ambientPositions() => Geolocator.getPositionStream(
    locationSettings: _ambientSettings,
  ).map(_toGeoPoint);

  /// 러닝 중 위치 스트림.
  ///
  /// 이 스트림은 러닝 도중에도 얼마든지 에러를 낼 수 있다 — 대표적으로 달리는 중에 기기의 위치 서비스를 끄는 경우.
  /// 구독하는 쪽은 반드시 `onError`를 달아야 한다.
  /// ([interruptionFrom]으로 사유를 읽을 수 있다).
  Stream<GeoPoint> trackPosition() => Geolocator.getPositionStream(
    locationSettings: _trackingSettings,
  ).map(_toGeoPoint);

  /// [trackPosition]이 낸 에러를 앱이 쓰는 사유로 바꾼다.
  /// geolocator 타입을 아는 곳을 이 파일 안에 묶어 두려고 여기 둔다 — 구독하는 쪽(RunTracker)은 받은 에러를 그대로 넘기기만 한다.
  LocationInterruption interruptionFrom(Object error) => switch (error) {
    LocationServiceDisabledException() => LocationInterruption.serviceDisabled,
    PermissionDeniedException() => LocationInterruption.permissionRevoked,
    _ => LocationInterruption.lost,
  };

  Future<void> openAppSettings() => Geolocator.openAppSettings();

  Future<void> openLocationSettings() => Geolocator.openLocationSettings();

  // position.altitude는 일부러 버린다. 러닝 기록에서 고도를 쓰는 곳이 없다.
  //
  // speed는 모르면 null로 넘긴다. geolocator는 속도를 못 잰 점(iOS의 무효 속도,
  // Android hasSpeed()=false)에 0.0을 채워 주는데, 그걸 그대로 두면 "서 있다"와
  // "모른다"가 구분되지 않아 달리는 중에도 거리가 안 쌓이는 점이 생긴다.
  // 속도가 실제로 측정된 점은 speedAccuracy가 양수다.
  static GeoPoint _toGeoPoint(Position position) => GeoPoint(
    latitude:   position.latitude,
    longitude:  position.longitude,
    recordedAt: position.timestamp,
    accuracy:   position.accuracy,
    speed:      position.speedAccuracy > 0 ? position.speed : null,
  );
}
