import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
// 카카오맵 SDK는 Route, Polygon 등 머티리얼과 겹치는 이름을 내보내므로 접두사를 붙인다.
import 'package:kakao_map_sdk/kakao_map_sdk.dart' as kakao;

import '../config/app_config.dart';
import '../models/geo_point.dart';
import '../theme/app_theme.dart';
import '../utils/geo_utils.dart';
import '../utils/run_path_interpolator.dart';

/// 카카오맵을 감싸는 러닝 전용 지도.
///
/// 앱의 나머지 부분은 카카오맵 SDK를 직접 알지 못하고 [GeoPoint]만 넘긴다.
/// 지도 SDK를 교체하더라도 이 위젯만 바꾸면 된다.
class RunMapView extends StatefulWidget {
  const RunMapView({
    super.key,
    this.coursePath = const [],
    this.runPath = const [],
    this.currentPosition,
    this.initialCenter,
    this.followCurrentPosition = false,
  });

  /// 따라 달릴 코스 경로. 강조색 실선으로 그린다.
  final List<GeoPoint> coursePath;

  /// 이미 끝난 러닝의 경로. 결과 화면처럼 정지 화면에서 쓴다.
  ///
  /// [currentPosition]이 있으면 무시된다 — 그때는 들어오는 위치로 경로를 직접
  /// 만들어 그린다([_GrowingRoute]). 같은 경로를 두 번 그리지 않기 위해서다.
  final List<GeoPoint> runPath;

  /// 지금 위치. 주면 이 위젯이 자체 렌더 루프를 돌려 마커와 경로를 함께 그린다.
  final GeoPoint? currentPosition;

  /// 최초 지도 중심. 없으면 경로 중심 → 제주시청 순으로 대체한다.
  final GeoPoint? initialCenter;

  /// true면 현재 위치를 따라 지도 중심을 이동한다.
  final bool followCurrentPosition;

  /// 위치를 아직 모를 때 쓰는 기본 중심(제주시청).
  static const GeoPoint defaultCenter = GeoPoint(
    latitude: 33.4996,
    longitude: 126.5312,
  );

  @override
  State<RunMapView> createState() => _RunMapViewState();
}

/// 러닝 중 지도를 그리는 방식
/// ==========================
///
/// 갱신 경로가 둘이고, 도는 속도가 다르다.
///
/// - **이벤트 구동**([_redraw]): 위젯 프로퍼티가 바뀔 때. 코스·카메라·정지 경로처럼
///   자주 바뀌지 않는 것들을 맡는다.
/// - **렌더 루프**([_onTick]): [_frameInterval]마다. 현위치 마커와 자라는 경로의
///   끝을 맡는다.
///
/// 예전에는 둘이 섞여 있었다. 새 위치가 오면 경로는 그 점까지 즉시 그리고, 마커만
/// 네이티브 애니메이션(`Poi.move(p, 900)`)으로 옮겼다. 그래서 마커는 구조적으로
/// 항상 선 끝보다 뒤에 있었고, 위치가 애니메이션보다 자주 오면(시뮬레이션 배속,
/// 촘촘한 distanceFilter) 애니메이션이 끝날 기회조차 없어 격차가 계속 벌어졌다.
///
/// 지금은 시계가 하나다. [RunPathInterpolator]가 렌더 시각의 좌표 하나를 주고,
/// 마커와 경로 끝이 같은 프레임에서 그 좌표를 함께 받는다. 둘이 어긋나는 것이
/// 구조적으로 불가능하다.
class _RunMapViewState extends State<RunMapView>
    with SingleTickerProviderStateMixin {
  kakao.KakaoMapController? _controller;

  // 오버레이는 ID가 아니라 객체 참조로 다룬다. 매번 지우고 다시 그리는 대신
  // changePoint/move로 제자리 갱신해야 러닝 중 깜빡임이 없다.
  kakao.Route? _courseRoute;
  // 현재 위치 마커. Label(Poi)인 이유는 [_syncLivePosition]에 적어 뒀다.
  kakao.Poi? _currentPositionMarker;
  bool _isTracking = false;

  /// 지도에 실제로 올라가 있는 코스. 같은 점이 다시 들어오면 플랫폼 호출을 건너뛴다.
  List<GeoPoint>? _drawnCoursePath;

  /// 정지 화면에서 [RunMapView.runPath]를 그린 선.
  kakao.Route? _staticRunRoute;
  List<GeoPoint>? _drawnStaticRunPath;

  /// 러닝 중 자라는 경로.
  _GrowingRoute? _liveRoute;

  /// 위치 샘플 버퍼 겸 보간기.
  final RunPathInterpolator _interpolator = RunPathInterpolator();

  /// 렌더 시계. 샘플 도착 시각과 프레임 시각이 모두 이 하나를 본다.
  final Stopwatch _renderClock = Stopwatch();
  Ticker? _ticker;
  Duration _lastFrameAt = Duration.zero;

  /// 보간기에 마지막으로 넣은 위치. 같은 점이 다시 오면 넘기지 않는다.
  GeoPoint? _lastSample;

  /// 지금 화면에 그려져 있는 좌표. 마커와 경로 끝이 공유한다.
  GeoPoint? _renderedPosition;

  // 아직 지도에 반영하지 못한 프레임. 플랫폼 호출이 진행 중일 때 여기 쌓였다가
  // [_flushFrame]의 루프가 이어서 처리한다. 좌표는 최신 것만 의미가 있어서
  // 덮어쓰지만, 확정된 점은 경로에 빠짐없이 들어가야 하므로 모아 둔다.
  final List<GeoPoint> _pendingSettled = [];
  GeoPoint? _pendingPosition;

  bool _isRendering = false;

  /// 마지막으로 돈 [_runFrames]. 라이브 오버레이를 지우기 전에 이걸 기다린다.
  Future<void>? _renderIdle;

  bool _hasFittedCourse = false;
  bool _disposed = false;

  // 러닝 중 카메라에 지정할 배율.
  //
  // 매번 명시적인 값을 넘겨야 한다. CameraUpdate.newCenterPosition의 zoomLevel을
  // 비우면 SDK가 -1을 보내는데, iOS 네이티브(CameraTypeConverter.swift:28)는
  // "키가 없을 때"만 현재 배율로 대체하고 -1은 그대로 배율로 써버린다. 그러면
  // 지도가 최소 배율(전국)로 빠진다.
  //
  // 그래서 배율을 여기서 직접 들고 있는다. 러닝을 시작할 때 _runningZoomLevel로
  // 맞추고, 사용자가 손으로 확대/축소하면 onCameraMoveEnd로 그 값을 받아 따른다.
  // 그래야 달리는 중에 축소해서 앞길을 봐도 다음 위치 갱신에 되돌아가지 않는다.
  int _followZoomLevel = _runningZoomLevel;
  bool _isFollowing = false;

  // 네이티브 키 인증에 실패하면 지도는 아무것도 그리지 않은 채 빈 화면으로 남는다.
  // 그대로 두면 키 문제인지, 좌표 문제인지, 빌드 문제인지 구분할 수 없어서
  // 오류를 붙잡아 원인과 조치를 화면에 띄운다.
  Object? _mapError;
  String? _keyHash;

  // 이벤트 구동 갱신도 전부 비동기 플랫폼 호출이라, 이전 호출이 끝나기 전에 다음
  // 호출이 들어올 수 있다. 갱신을 직렬화하고, 진행 중에 들어온 요청은 마지막
  // 상태로 한 번만 다시 그린다.
  bool _isRedrawing = false;
  bool _needsRedraw = false;

  /// 지도 초기 확대 수준. 값이 클수록 확대된다.
  static const int _initialZoomLevel = 16;

  /// 러닝 중 확대 수준. 코스 전체가 아니라 발밑 몇 십 미터를 보는 화면이라
  /// 초기값보다 더 당긴다.
  static const int _runningZoomLevel = 18;

  /// 현재 위치 마커의 화면 크기(dp). 지도 배율과 무관하게 일정하다.
  static const int _currentPositionMarkerSize = 28;

  /// 지도 갱신 주기(≈30Hz).
  ///
  /// 화면의 60fps를 전부 플랫폼으로 넘길 이유는 없다. 러닝 속도(3m/s)에서
  /// 33ms는 0.1m라 눈에는 연속이고, 플랫폼 호출은 절반이 된다.
  static const Duration _frameInterval = Duration(milliseconds: 33);

  /// 코스 전체를 화면에 맞출 때 가장자리에 두는 여백(px).
  static const int _fitPadding = 48;

  late final kakao.RouteStyle _courseStyle = kakao.RouteStyle(
    AppColors.accent,
    6,
  );
  late final kakao.RouteStyle _runStyle = kakao.RouteStyle(AppColors.ink, 7);
  // [진단중] 플러그인 포크의 diag/ios-image-format 브랜치와 함께 쓴다.
  // iOS에서 아이콘을 넣으면 지도 엔진이 "unsupport png pixel format: 7"로 죽는데,
  // 그 원인이 플러그인의 이미지 리사이즈인지 확인하는 중이다.
  // 진단이 끝나면 텍스트 마커로 되돌리거나, 원인을 고치고 이대로 둔다.
  late final kakao.PoiStyle _currentPositionStyle = kakao.PoiStyle(
    // 기본 앵커는 아래쪽 끝(핀 모양 기준)이라, 마커를 좌표 중심에 놓으려면 옮겨야 한다.
    anchor: const kakao.KPoint(0.5, 0.5),
    icon: kakao.KImage.fromAsset(
      'assets/circleMarker.png',
      _currentPositionMarkerSize,
      _currentPositionMarkerSize,
    ),
  );

  @override
  void didUpdateWidget(covariant RunMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 러닝 화면은 경과 시간 때문에 1초마다 rebuild된다. 지도에 넣을 값이 그대로면
    // 다시 그리지 않는다 — 그리기는 전부 플랫폼 왕복이라, 변화 없이 매초 돌리면
    // 뒤따르는 카메라 이동까지 밀려서 현위치 추적이 끊긴다.
    if (_hasMapInputChanged(oldWidget)) _redraw();
  }

  bool _hasMapInputChanged(RunMapView old) =>
      old.followCurrentPosition != widget.followCurrentPosition ||
      !identical(_lastSample, widget.currentPosition) ||
      !_isSamePath(old.coursePath, widget.coursePath) ||
      !_isSamePath(old.runPath, widget.runPath);

  /// 경로는 뒤에 점이 붙기만 하므로 길이와 마지막 점만 보면 같은지 알 수 있다.
  /// (GeoPoint는 값 비교를 정의하지 않아 identical로 본다 — 점이 추가되면
  /// 반드시 새 인스턴스라 이걸로 충분하다.)
  static bool _isSamePath(List<GeoPoint> a, List<GeoPoint> b) {
    if (a.length != b.length) return false;
    return a.isEmpty || identical(a.last, b.last);
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.hasKakaoNativeAppKey) {
      return const _MissingMapKeyPlaceholder();
    }

    final error = _mapError;
    if (error != null) {
      return _MapErrorView(error: error, keyHash: _keyHash);
    }

    final center = widget.initialCenter ??
        GeoUtils.centerOf(widget.coursePath) ??
        GeoUtils.centerOf(widget.runPath) ??
        RunMapView.defaultCenter;

    return kakao.KakaoMap(
      option: kakao.KakaoMapOption(
        position: _toLatLng(center),
        zoomLevel: _initialZoomLevel,
      ),
      onMapReady: (controller) {
        _controller = controller;
        _redraw();
      },
      // 사용자가 손으로 바꾼 배율을 러닝 중 카메라 추적에 이어서 쓴다.
      // 우리가 옮긴 경우에도 불리지만, 방금 지정한 값이 그대로 돌아올 뿐이다.
      onCameraMoveEnd: (cameraPosition, _) =>
          _followZoomLevel = cameraPosition.zoomLevel,
      onMapError: _handleMapError,
    );
  }

  Future<void> _handleMapError(Error error) async {
    // 인증 실패는 대개 키 해시 미등록이라, 콘솔에 넣어야 할 값을 같이 보여준다.
    String? hashKey;
    try {
      hashKey = await kakao.KakaoMapSdk.instance.hashKey();
    } catch (_) {
      // 키 해시를 못 가져와도 오류 자체는 보여줘야 한다.
    }

    if (_disposed || !mounted) return;
    setState(() {
      _mapError = error;
      _keyHash = hashKey;
    });
  }

  // ---------------------------------------------------------------------------
  // 이벤트 구동 갱신
  // ---------------------------------------------------------------------------

  Future<void> _redraw() async {
    if (_controller == null || _disposed) return;

    if (_isRedrawing) {
      _needsRedraw = true;
      return;
    }

    _isRedrawing = true;
    try {
      do {
        _needsRedraw = false;
        final controller = _controller;
        if (controller == null || _disposed) return;

        // 순서가 중요하다. 현위치와 카메라는 점 하나만 보내면 되지만 코스는
        // 점이 쌓일수록 무거워진다. 가벼운 쪽을 앞에 둔다.
        await _syncLivePosition(controller);
        await _moveCamera(controller);
        await _drawCourse(controller);
        await _drawStaticRunPath(controller);
      } while (_needsRedraw && !_disposed);
    } finally {
      _isRedrawing = false;
    }
  }

  /// 새 위치를 보간기에 넣고, 마커를 만들고, 렌더 루프를 켠다.
  ///
  /// 마커를 실제로 **옮기지는 않는다**. 그건 [_flushFrame]이 경로 끝과 함께
  /// 한다 — 둘이 같은 프레임에서 같은 좌표를 받아야 어긋나지 않는다.
  ///
  /// 마커가 도형(Shape)이 아니라 Label(Poi)인 이유는 TrackingController가 추적할
  /// 수 있는 대상이 Poi뿐이기 때문이다(도형은 안 된다). 도형 원(CirclePoint)은
  /// 애초에 쓸 수도 없다 — kakao_map_sdk 1.2.6에서 넘기면 iOS가 크래시한다.
  /// _BaseDotPoint.toMessageable()이 payload에 "type"을 빼먹는데
  /// 네이티브(ShapeControllerHandler.swift:97)가 `position["type"]!`로 강제
  /// 언래핑한다.
  Future<void> _syncLivePosition(kakao.KakaoMapController controller) async {
    final position = widget.currentPosition;

    if (position == null) {
      await _clearLive(controller);
      return;
    }

    // 위치는 프로퍼티로 한 점씩 들어온다. 한 프레임 안에 두 점이 오면 뒤엣것만
    // 보이지만, 위치는 아무리 빨라야 1m마다(≈300ms) 오고 프레임은 16ms라
    // 실제로는 겹치지 않는다. 백그라운드 기록을 넣으면(Info.plist 참고) 화면이
    // 멈춘 동안 점이 쌓이므로, 그때는 여기서 밀린 점을 받아와야 한다.
    if (!identical(_lastSample, position)) {
      _lastSample = position;
      if (!_renderClock.isRunning) _renderClock.start();
      _interpolator.add(position, _renderClock.elapsed);
    }

    if (_currentPositionMarker == null) {
      _currentPositionMarker = await controller.labelLayer.addPoi(
        _toLatLng(position),
        style: _currentPositionStyle,
        text: '●',
      );
      _renderedPosition = position;
    }

    _liveRoute ??= _GrowingRoute(controller.routeLayer, _runStyle, _runZOrder);

    if (widget.followCurrentPosition) {
      _startRenderLoop();
      return;
    }

    // 일시정지·종료. 더 이상 점이 오지 않으니 남은 보간분을 끝까지 그리고 멈춘다.
    _stopRenderLoop();
    _stageFrame(_interpolator.settleAll());
  }

  /// 러닝이 초기화됐다(현위치가 사라졌다). 라이브 렌더에 딸린 것을 전부 되돌린다.
  Future<void> _clearLive(kakao.KakaoMapController controller) async {
    if (_lastSample == null && _liveRoute == null) return;

    // 루프를 먼저 세우고, 진행 중인 프레임이 끝나기를 기다린 뒤에 지운다.
    // 안 그러면 방금 지운 마커·선을 그 프레임이 이어서 건드린다.
    _stopRenderLoop();
    await _renderIdle;

    _renderClock
      ..stop()
      ..reset();
    _interpolator.clear();
    _pendingSettled.clear();
    _pendingPosition = null;
    _lastSample = null;
    _renderedPosition = null;

    final marker = _currentPositionMarker;
    if (marker != null) {
      await _stopTracking(controller);
      await marker.remove();
      _currentPositionMarker = null;
    }

    await _liveRoute?.clear();
    _liveRoute = null;
  }

  Future<void> _drawCourse(kakao.KakaoMapController controller) async {
    // 코스는 러닝 내내 바뀌지 않는다. 매 갱신마다 전체 점을 다시 보내면
    // 코스가 길수록 그대로 낭비다.
    final points = widget.coursePath;
    if (_drawnCoursePath != null && _isSamePath(_drawnCoursePath!, points)) {
      return;
    }

    _courseRoute = await _syncRoute(
      controller,
      existing: _courseRoute,
      points: points,
      style: _courseStyle,
      zOrder: _courseZOrder,
    );
    _drawnCoursePath = points;
  }

  /// 정지 화면의 경로. 라이브 위치가 있으면 [_GrowingRoute]가 대신 그리므로
  /// 여기서는 지운다.
  Future<void> _drawStaticRunPath(kakao.KakaoMapController controller) async {
    final points = widget.currentPosition == null
        ? widget.runPath
        : const <GeoPoint>[];

    if (_drawnStaticRunPath != null &&
        _isSamePath(_drawnStaticRunPath!, points)) {
      return;
    }

    _staticRunRoute = await _syncRoute(
      controller,
      existing: _staticRunRoute,
      points: points,
      style: _runStyle,
      zOrder: _runZOrder,
    );
    _drawnStaticRunPath = points;
  }

  /// 선 하나를 현재 [points] 상태에 맞춘다. 점이 부족하면 지우고, 이미 있으면
  /// 제자리 갱신하고, 없으면 새로 그린다. 갱신된 객체(또는 null)를 돌려준다.
  Future<kakao.Route?> _syncRoute(
    kakao.KakaoMapController controller, {
    required kakao.Route? existing,
    required List<GeoPoint> points,
    required kakao.RouteStyle style,
    required int zOrder,
  }) async {
    // 선이 되려면 점이 둘 이상 필요하다.
    if (points.length < 2) {
      if (existing != null) {
        await controller.routeLayer.removeRoute(existing);
      }
      return null;
    }

    final latLngs = points.map(_toLatLng).toList();
    if (existing == null) {
      return controller.routeLayer.addRoute(latLngs, style, zOrder: zOrder);
    }

    await existing.changePoint(latLngs);
    return existing;
  }

  Future<void> _moveCamera(kakao.KakaoMapController controller) async {
    final position = widget.currentPosition;
    if (widget.followCurrentPosition && position != null) {
      // 러닝이 막 시작됐으면 코스 전체를 보던 배율에서 러닝용 배율로 당긴다.
      // 위치 갱신마다 카메라를 옮기지는 않는다 — 그건 TrackingController가 한다.
      if (!_isFollowing) {
        _isFollowing = true;
        _followZoomLevel = _runningZoomLevel;
        await controller.moveCamera(
          kakao.CameraUpdate.newCenterPosition(
            _toLatLng(position),
            zoomLevel: _followZoomLevel,
          ),
        );
      }

      await _startTracking(controller);
      return;
    }

    // 러닝이 끝났으면 다음 러닝에서 다시 당길 수 있게 되돌린다.
    _isFollowing = false;
    await _stopTracking(controller);

    // 코스를 처음 받아왔을 때 한 번만 전체가 보이도록 맞춘다.
    if (!_hasFittedCourse && widget.coursePath.length >= 2) {
      _hasFittedCourse = true;
      await controller.moveCamera(
        kakao.CameraUpdate.fitMapPoints(
          widget.coursePath.map(_toLatLng).toList(),
          padding: _fitPadding,
        ),
      );
    }
  }

  /// 카메라가 현위치 마커를 따라다니게 한다.
  ///
  /// 우리가 프레임마다 moveCamera를 부르는 것과 결과는 같아 보이지만, 이동을
  /// 네이티브가 마커와 같은 타임라인으로 처리해서 카메라와 마커가 따로 놀지
  /// 않는다. 회전 추적(setTrackingRotate)은 켜지 않는다 — 마커가 원형이라 방향이
  /// 없고, 지도가 돌면 코스 폴리라인만 읽기 어려워진다.
  Future<void> _startTracking(kakao.KakaoMapController controller) async {
    final marker = _currentPositionMarker;
    if (_isTracking || marker == null) return;

    controller.tracking.poi = marker;
    await controller.tracking.start();
    _isTracking = true;
  }

  Future<void> _stopTracking(kakao.KakaoMapController controller) async {
    if (!_isTracking) return;

    await controller.tracking.stop();
    controller.tracking.poi = null;
    _isTracking = false;
  }

  // ---------------------------------------------------------------------------
  // 렌더 루프
  // ---------------------------------------------------------------------------

  void _startRenderLoop() {
    // SingleTickerProviderStateMixin은 Ticker를 하나만 허용한다. 껐다 켤 때
    // 새로 만들지 않고 같은 것을 start/stop한다.
    final ticker = _ticker ??= createTicker(_onTick);
    if (!ticker.isActive) ticker.start();
  }

  void _stopRenderLoop() {
    _ticker?.stop();
    _lastFrameAt = Duration.zero;
  }

  void _onTick(Duration _) {
    if (_disposed) return;

    // Ticker가 주는 시각이 아니라 렌더 시계를 본다. 샘플 도착 시각과 같은
    // 축이어야 보간이 맞는다.
    final now = _renderClock.elapsed;
    if (now - _lastFrameAt < _frameInterval) return;
    _lastFrameAt = now;

    _stageFrame(_interpolator.advanceTo(now));
  }

  void _stageFrame(RunFrame? frame) {
    if (frame == null || _disposed) return;

    _pendingSettled.addAll(frame.settled);
    _pendingPosition = frame.position;
    _flushFrame();
  }

  /// 마커와 경로 끝을 **같은 좌표로 함께** 옮긴다. 이 위젯의 핵심이다.
  ///
  /// 플랫폼 호출이 진행 중이면 바로 돌아온다. 쌓인 것은 아래 루프가 다음 바퀴에
  /// 처리하므로 확정된 점을 잃지 않는다.
  void _flushFrame() {
    if (_isRendering) return;
    _renderIdle = _runFrames();
  }

  Future<void> _runFrames() async {
    _isRendering = true;
    try {
      while (!_disposed) {
        final live = _liveRoute;
        final marker = _currentPositionMarker;
        final position = _pendingPosition;
        if (live == null || marker == null || position == null) break;

        // 움직이지도, 확정된 점이 늘지도 않았으면 보낼 것이 없다.
        // 일시정지처럼 멈춰 있는 동안 플랫폼 호출이 계속 나가지 않게 한다.
        if (_pendingSettled.isEmpty &&
            _isSameCoordinate(_renderedPosition, position)) {
          break;
        }

        final settled = List.of(_pendingSettled);
        _pendingSettled.clear();

        // 마커 → 경로 순서. 마커가 카메라 추적 대상이라 먼저 자리를 잡는 편이
        // 화면 흔들림이 적다.
        await marker.move(_toLatLng(position));
        if (settled.isNotEmpty) await live.append(settled);
        await live.moveTip(position);

        _renderedPosition = position;
      }
    } finally {
      _isRendering = false;
    }
  }

  static bool _isSameCoordinate(GeoPoint? a, GeoPoint? b) =>
      a != null &&
      b != null &&
      a.latitude == b.latitude &&
      a.longitude == b.longitude;

  static kakao.LatLng _toLatLng(GeoPoint point) =>
      kakao.LatLng(point.latitude, point.longitude);

  // 달린 경로가 코스 위에 오도록 쌓는 순서를 고정한다.
  static const int _courseZOrder = 10000;
  static const int _runZOrder = 10001;
}

/// 러닝 중 자라는 경로. 확정 구간과 현위치까지의 꼬리를 나눠 그린다.
///
/// 카카오 SDK는 선을 고칠 때 전체 점을 다시 보낸다([kakao.Route.changePoint]).
/// 경로를 선 하나로 그리면 갱신 비용이 지금까지 달린 거리에 비례하고, 그걸
/// 프레임마다 하면 러닝이 길어질수록 갱신이 눈에 띄게 밀린다.
///
/// 그래서 확정 구간은 [_chunkSize]개씩 끊어 별도의 선으로 두고, 점이 확정될 때
/// **마지막 청크만** 다시 보낸다. 프레임마다 움직이는 것은 2점짜리 [_tail]뿐이라
/// 비용이 경로 길이와 무관하다. 스타일과 zOrder가 같아 화면에서는 한 줄로 보인다.
class _GrowingRoute {
  _GrowingRoute(this._layer, this._style, this._zOrder);

  final kakao.RouteController _layer;
  final kakao.RouteStyle _style;
  final int _zOrder;

  /// 한 청크에 담는 점 수. 갱신 1회에 보내는 점 수의 상한이기도 하다.
  static const int _chunkSize = 128;

  final List<kakao.Route> _chunks = [];

  /// 지금 자라고 있는 청크와 그 점들. 아직 2점이 안 되면 [_open]은 null이다.
  kakao.Route? _open;
  List<kakao.LatLng> _openPoints = [];

  /// 확정 구간 끝에서 현위치까지를 잇는 2점짜리 선.
  kakao.Route? _tail;
  bool _isTailVisible = false;

  /// 확정 구간의 끝점. 꼬리가 여기서 출발한다.
  GeoPoint? _lastPoint;

  /// 확정된 점들을 경로 뒤에 붙인다.
  Future<void> append(List<GeoPoint> points) async {
    for (final point in points) {
      _openPoints.add(_toLatLng(point));
      _lastPoint = point;

      if (_openPoints.length < _chunkSize) continue;

      await _syncOpen();
      // 다음 청크는 이번 청크의 끝점에서 시작한다. 안 그러면 경계에 빈틈이 생긴다.
      _openPoints = [_openPoints.last];
      _open = null;
    }

    await _syncOpen();
  }

  /// 확정 구간 끝에서 [position]까지를 잇는다. 프레임마다 불린다.
  Future<void> moveTip(GeoPoint position) async {
    final anchor = _lastPoint;
    if (anchor == null) return;

    // 확정 끝점과 현위치가 같은 좌표면 그릴 선이 없다. 출발 직후와 멈춰 있는
    // 동안에 생기는데, 길이 0짜리 선을 남겨 두면 굵기만큼 점이 찍힌다.
    if (anchor.latitude == position.latitude &&
        anchor.longitude == position.longitude) {
      if (_isTailVisible) {
        _isTailVisible = false;
        await _tail?.hide();
      }
      return;
    }

    final points = [_toLatLng(anchor), _toLatLng(position)];
    final tail = _tail;
    if (tail == null) {
      _tail = await _layer.addRoute(points, _style, zOrder: _zOrder);
      _isTailVisible = true;
      return;
    }

    await tail.changePoint(points);
    if (!_isTailVisible) {
      _isTailVisible = true;
      await tail.show();
    }
  }

  Future<void> clear() async {
    for (final chunk in _chunks) {
      await _layer.removeRoute(chunk);
    }
    _chunks.clear();

    final tail = _tail;
    if (tail != null) {
      await _layer.removeRoute(tail);
      _tail = null;
    }

    _open = null;
    _openPoints = [];
    _lastPoint = null;
    _isTailVisible = false;
  }

  Future<void> _syncOpen() async {
    // 선이 되려면 점이 둘 이상 필요하다. 하나뿐인 동안은 꼬리가 대신 그린다.
    if (_openPoints.length < 2) return;

    final open = _open;
    if (open == null) {
      final route = await _layer.addRoute(
        List.of(_openPoints),
        _style,
        zOrder: _zOrder,
      );
      _open = route;
      _chunks.add(route);
      return;
    }

    await open.changePoint(List.of(_openPoints));
  }

  static kakao.LatLng _toLatLng(GeoPoint point) =>
      kakao.LatLng(point.latitude, point.longitude);
}

/// 카카오 앱 키 없이 빌드했을 때 지도 대신 보여주는 안내.
class _MissingMapKeyPlaceholder extends StatelessWidget {
  const _MissingMapKeyPlaceholder();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFE8EBEF),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.map_outlined, size: 40, color: Color(0xFF7A8593)),
              const SizedBox(height: 12),
              Text(
                '지도를 표시하려면 카카오 앱 키가 필요해요',
                style: Theme.of(context).textTheme.titleSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              const Text(
                'config/app_config.dart의 kakaoNativeAppKey가 비어 있어요',
                style: TextStyle(fontSize: 11, color: Color(0xFF5B6472)),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 지도 SDK가 오류를 낸 경우 빈 화면 대신 원인과 조치를 보여준다.
class _MapErrorView extends StatelessWidget {
  const _MapErrorView({required this.error, this.keyHash});

  final Object error;

  /// 안드로이드에서 이 앱이 실제로 쓰는 키 해시. 인증 실패는 대개 이 값이
  /// 콘솔에 등록되지 않아서 나므로, 바로 복사해 등록할 수 있게 보여준다.
  final String? keyHash;

  @override
  Widget build(BuildContext context) {
    final hash = keyHash;

    return ColoredBox(
      color: const Color(0xFFE8EBEF),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 40,
                color: Color(0xFF7A8593),
              ),
              const SizedBox(height: 12),
              Text(
                '지도를 불러오지 못했어요',
                style: Theme.of(context).textTheme.titleSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _reason,
                style: const TextStyle(fontSize: 12, color: Color(0xFF5B6472)),
                textAlign: TextAlign.center,
              ),
              if (hash != null) ...[
                const SizedBox(height: 16),
                const Text(
                  '이 앱의 키 해시',
                  style: TextStyle(fontSize: 11, color: Color(0xFF5B6472)),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  hash,
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: Color(0xFF2B3138),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 16),
              Text(
                '$error',
                style: const TextStyle(fontSize: 10, color: Color(0xFF8A929E)),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 오류를 "무엇을 해야 하는지"가 드러나는 문장으로 바꾼다.
  String get _reason {
    final e = error;

    if (e is kakao.KakaoAuthError) {
      return switch (e.code) {
        400 => '요청에 필요한 정보가 빠졌어요.',
        401 => '앱 키가 올바르지 않아요.\nAppConfig.kakaoNativeAppKey를 확인해 주세요.',
        403 => '이 앱에 카카오맵 사용 권한이 없어요.\n콘솔에서 카카오맵 약관 동의와 '
            '플랫폼 등록(패키지명·키 해시)을 확인해 주세요.',
        429 => '카카오맵 사용량을 초과했어요.\n잠시 후 다시 시도해 주세요.',
        499 => '네트워크에 연결하지 못했어요.',
        _ => e.message ?? '알 수 없는 인증 오류예요.',
      };
    }

    if (e is kakao.KakaoMapError) {
      return e.message ?? e.className;
    }

    return '$e';
  }
}
