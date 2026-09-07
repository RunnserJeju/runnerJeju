import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/geo_point.dart';
import 'location_service.dart';

/// 앱이 아는 "가장 최신 현위치" 하나.
///
/// 지도 앱들이 하는 방식이다 — 화면이 떠 있는 동안 위치를 스트림으로 계속 받아
/// 두고, 내 위치 버튼은 새로 조회하지 않고 이 값으로 카메라만 옮긴다. 단발
/// 조회([LocationService.currentPosition])는 양쪽 플랫폼 다 스트림을 열어 첫
/// 콜백을 기다리는 구조라, Android에서 GPS만 쓰는 기기나 실내에서는 수십 초가
/// 걸리거나 영영 안 와서 버튼이 씹힌 것처럼 보였다.
///
/// 스트림은 한 번에 하나만 연다. geolocator가 플랫폼당 스트림을 하나만 두고
/// 두 번째 요청에는 설정을 무시한 채 첫 스트림을 돌려주기 때문에, 이 평상시
/// 스트림이 열린 채로 러닝이 고정확도 스트림을 요청하면 러닝이 이 설정을 받아
/// 기록이 깨진다. 그래서 러닝이 시작되면 [yieldToRun]으로 이쪽을 닫고, 러닝
/// 스트림이 받은 점을 [report]로 흘려 최신값은 계속 갱신한다.
class CurrentLocation extends ChangeNotifier with WidgetsBindingObserver {
  CurrentLocation(this._locationService);

  final LocationService _locationService;

  GeoPoint? _latest;

  /// 가장 최근에 받은 위치. 아직 한 점도 못 받았으면 null.
  GeoPoint? get latest => _latest;

  StreamSubscription<GeoPoint>? _subscription;

  /// 권한이 확인되어 스트림을 열어도 되는 상태인지.
  bool _isPermitted = false;

  /// 러닝이 스트림을 가져간 동안 true. 그동안 평상시 스트림은 열지 않는다.
  bool _isYielded = false;

  /// 앱이 화면에 떠 있는지. 뒤로 가면 스트림을 닫는다 — 포그라운드 서비스가
  /// 없는 스트림은 OS가 죽이거나 심하게 제한하므로 명시적으로 관리한다.
  /// (러닝 스트림은 자기 포그라운드 서비스가 있어 이 처리와 무관하다.)
  bool _isInForeground = true;

  /// 앱 시작 시 한 번. 권한이 **이미** 있으면 곧바로 스트림을 연다.
  ///
  /// 여기서 권한을 요청하지는 않는다. 첫 화면에서 맥락 없이 물으면 거부율이
  /// 오르고 애플 심사도 사용 시점 요청을 권한다. 아직 안 물어봤으면 지도 탭에
  /// 들어갈 때 [ensureStarted]가 묻는다.
  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);
    final availability = await _locationService.checkAvailability();
    if (availability.isReady) {
      _isPermitted = true;
      _sync();
    }
  }

  /// 권한을 (필요하면 요청해서) 확보하고 스트림을 연다. 위치가 필요한 화면이
  /// 부른다. 이미 열려 있으면 아무 일도 없다.
  Future<LocationAvailability> ensureStarted() async {
    final availability = await _locationService.ensurePermission();
    _isPermitted = availability.isReady;
    _sync();
    return availability;
  }

  /// 러닝이 위치 스트림을 가져간다. 러닝의 [LocationService.trackPosition]
  /// 구독 **전에** 불러야 한다 — 이쪽이 먼저 닫혀야 러닝 설정이 적용된다.
  void yieldToRun() {
    _isYielded = true;
    _sync();
  }

  /// 러닝이 끝나 스트림을 돌려준다. 러닝 구독이 끊긴 **뒤에** 불러야 한다.
  void reclaimFromRun() {
    _isYielded = false;
    _sync();
  }

  /// 러닝 스트림이 받은 점을 최신값으로 흘린다. 러닝 중에도 러닝 화면 밖의
  /// 위치 소비자(러닝 화면의 초기 중심 등)가 같은 값을 보게 한다.
  void report(GeoPoint point) => _update(point);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // inactive는 권한 팝업·제어 센터·전화 수신처럼 잠깐 가려진 상태라 앞에
    // 있는 것으로 친다. 여기서 닫으면 권한을 허용하는 순간마다 스트림이 껐다
    // 켜진다.
    _isInForeground =
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    _sync();
  }

  /// 지금 상태에 맞게 스트림을 열거나 닫는다. 조건이 하나라도 안 맞으면 닫는다.
  void _sync() {
    final shouldRun = _isPermitted && !_isYielded && _isInForeground;

    if (!shouldRun) {
      _subscription?.cancel();
      _subscription = null;
      return;
    }

    if (_subscription != null) return;
    _subscription = _locationService.ambientPositions().listen(
      _update,
      // 위치 서비스를 끄는 등으로 끊기면 조용히 닫는다. 다음 조건 변화(앱 복귀,
      // 화면 진입)에서 다시 열린다.
      onError: (Object _) {
        _subscription?.cancel();
        _subscription = null;
      },
      onDone: () => _subscription = null,
    );
  }

  void _update(GeoPoint point) {
    _latest = point;
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    super.dispose();
  }
}
