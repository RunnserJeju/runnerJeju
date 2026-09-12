import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
// 카카오맵 SDK는 Route, Polygon 등 머티리얼과 겹치는 이름을 내보내므로 접두사를 붙인다.
import 'package:kakao_map_sdk/kakao_map_sdk.dart' as kakao;

import '../config/app_config.dart';
import '../models/course_facility.dart';
import '../models/geo_point.dart';
import '../theme/app_theme.dart';
import '../utils/geo_utils.dart';
import '../utils/run_path_interpolator.dart';
import 'course_direction_arrow.dart';
import 'course_endpoint_marker.dart';
import 'facility_marker.dart';
import 'kakao_geo.dart';
import 'my_position_marker.dart';
import 'map_status_views.dart';

/// 카카오맵을 감싸는 러닝 전용 지도.
///
/// 앱의 나머지 부분은 카카오맵 SDK를 직접 알지 못하고 [GeoPoint]만 넘긴다.
/// 지도 SDK를 교체하더라도 이 위젯만 바꾸면 된다.
class RunMapView extends StatefulWidget {
  const RunMapView({
    super.key,
    this.coursePath = const [],
    this.parkings = const [],
    this.restrooms = const [],
    this.runPath = const [],
    this.currentPosition,
    this.initialCenter,
    this.isRunning = false,
    this.followCurrentPosition = false,
    this.onUserMovedCamera,
    this.showCourseDirection = false,
    this.isAwaitingLocation = false,
  });

  /// 따라 달릴 코스 경로. 강조색 실선으로 그린다.
  final List<GeoPoint> coursePath;

  /// 코스 주차장/화장실. 달리는 중에도 근처 시설이 보이도록 배지로 찍는다.
  /// 러닝 내내 바뀌지 않는 정적 마커라 시작할 때 한 번만 그린다.
  final List<CourseFacility> parkings;
  final List<CourseFacility> restrooms;

  /// 이미 끝난 러닝의 경로. 결과 화면처럼 정지 화면에서 쓴다.
  ///
  /// [currentPosition]이 있으면 무시된다 — 그때는 들어오는 위치로 경로를 직접
  /// 만들어 그린다([_GrowingRoute]). 같은 경로를 두 번 그리지 않기 위해서다.
  final List<GeoPoint> runPath;

  /// 지금 위치. 주면 이 위젯이 자체 렌더 루프를 돌려 마커와 경로를 함께 그린다.
  final GeoPoint? currentPosition;

  /// 최초 지도 중심. 없으면 현위치 → 코스/러닝 경로의 중심 순으로 대체하고,
  /// 그것마저 없으면 지도를 아예 만들지 않는다 — 임시 좌표로 띄웠다가 나중에
  /// 옮기면 그 이동이 화면에서 점프로 보인다([isAwaitingLocation]).
  final GeoPoint? initialCenter;

  /// 지금 기록 중인지(일시정지·종료가 아닌지). 렌더 루프를 돌릴지, 일시정지에서
  /// 재개했을 때 라이브 경로를 끊을지를 이걸로 정한다.
  final bool isRunning;

  /// true면 카메라가 현위치 마커를 따라다닌다. [isRunning]과 별개다 — 달리는
  /// 중에도 사용자가 지도를 밀면 따라가기를 멈추고, 일시정지 중에도 "내 위치로"를
  /// 누르면 다시 따라간다.
  final bool followCurrentPosition;

  /// 사용자가 손으로 카메라를 움직였다(드래그·핀치 등). 따라가는 중이었다면
  /// 화면이 이걸 받아 [followCurrentPosition]을 내린다. 코드가 옮긴 이동
  /// (러닝 시작 시 배율 당기기, 추적 자체)에는 불리지 않는다.
  final VoidCallback? onUserMovedCamera;

  /// true면 코스 선에 진행방향 화살표를 얹는다. 달리는 중에만 필요한 안내라
  /// 시작 전에는 코스 모양만 깔끔하게 보여준다.
  final bool showCourseDirection;

  /// 지금 현위치를 조회하는 중인지. 그릴 좌표가 하나도 없을 때, 곧 들어올
  /// 것인지(러닝 화면) 애초에 없는 것인지(빈 기록)를 이 값으로 가른다.
  final bool isAwaitingLocation;

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
  kakao.BaseRoute? _courseRoute;
  // 현재 위치 마커. Label(Poi)인 이유는 [_syncLivePosition]에 적어 뒀다.
  kakao.Poi? _currentPositionMarker;
  bool _isTracking = false;

  /// 지도에 실제로 올라가 있는 코스. 같은 점이 다시 들어오면 플랫폼 호출을 건너뛴다.
  List<GeoPoint>? _drawnCoursePath;

  /// 지금 그려져 있는 코스에 화살표가 얹혀 있는지. 러닝 시작/종료에 따라 바뀐다.
  bool? _drawnCourseDirection;
  kakao.RouteStyle? _plainCourseStyle;

  /// 화살표 패턴 스타일. 다중 선형(세그먼트) 전용으로 등록하므로 단일 선형에
  /// 쓰는 [_plainCourseStyle]과 섞지 않는다.
  kakao.RouteStyle? _arrowCourseStyle;

  /// 코스 시설(주차장/화장실) 배지. 정적이라 한 번만 그리고 그대로 둔다.
  final List<kakao.Poi> _facilityMarkers = [];
  List<CourseFacility>? _drawnParkings;
  List<CourseFacility>? _drawnRestrooms;
  kakao.PoiStyle? _parkingStyle;
  kakao.PoiStyle? _restroomStyle;

  /// 코스 시작/끝의 '출발'/'도착' 배지. 코스가 바뀔 때만 다시 그린다.
  final List<kakao.Poi> _endpointMarkers = [];
  List<GeoPoint>? _drawnEndpointPath;
  final Map<String, kakao.PoiStyle> _endpointStyles = {};

  /// 정지 화면에서 [RunMapView.runPath]를 그린 선들. 일시정지로 끊긴 자리마다
  /// 하나씩 나뉘므로 여러 개가 된다.
  final List<kakao.Route> _staticRunRoutes = [];
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

  bool _hasFittedStaticPath = false;
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
  // 그래야 달리는 중에 축소해서 앞길을 봐도 다음 위치 갱신에 되돌아가지 않고,
  // 따라가기를 껐다 켜도 쓰던 배율로 돌아온다.
  int _followZoomLevel = _runningZoomLevel;
  bool _isFollowing = false;

  /// 이번 러닝에서 러닝용 배율로 당긴 적이 있는지. 처음 따라갈 때 한 번만
  /// 당기고, 그 뒤 따라가기를 다시 켤 때는 [_followZoomLevel]을 그대로 쓴다.
  bool _hasAppliedRunningZoom = false;

  /// 직전 갱신에서 기록 중이었는지. false -> true로 바뀌는 순간이
  /// 러닝 시작 아니면 일시정지에서의 재개다([_syncLivePosition]).
  bool _wasRunning = false;

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

  /// 러닝 중 확대 수준. 사용자가 핀치로 바꾸면 그 값을 따른다.
  static const int _runningZoomLevel = 16;

  /// 선 굵기(dp). 코스를 조금 더 굵게 둬서, 달린 경로가 위에 얹혀도 양옆으로
  /// 코스가 비어져 나온다 — 코스를 벗어났는지 달리면서 바로 보인다.
  static const double _courseLineWidth = 10;
  static const double _runLineWidth = 9;

  /// 코스 진행방향 화살표를 찍는 간격(px). 화면 기준이라 배율과 무관하다.
  static const double _arrowSpacing = 40;

  /// 코스 선을 그릴 때 걷어낼 잔 꼭짓점의 허용 오차(m). 화살표 패턴은 선분
  /// 방향으로 눕혀 그려져서, 꼭짓점을 걸친 화살표는 선 밖으로 비어져 나온다.
  /// GPS 흔들림으로 생긴 꼭짓점을 지우면 그런 자리가 크게 줄어든다.
  static const double _courseDrawTolerance = 2;

  /// 이보다 크게 꺾이는 꼭짓점에서 코스 선을 세그먼트로 나눈다. 패턴은 세그먼트
  /// 단위로 다시 시작하므로 화살표가 그 꼭짓점을 걸치지 않는다.
  static const double _courseBendThreshold = 20;

  /// 지도 갱신 주기(≈30Hz).
  ///
  /// 화면의 60fps를 전부 플랫폼으로 넘길 이유는 없다. 러닝 속도(3m/s)에서
  /// 33ms는 0.1m라 눈에는 연속이고, 플랫폼 호출은 절반이 된다.
  static const Duration _frameInterval = Duration(milliseconds: 33);

  /// 경로 전체를 화면에 맞출 때 가장자리에 두는 여백(px).
  static const int _fitPadding = 48;

  late final kakao.RouteStyle _runStyle = kakao.RouteStyle(
    AppColors.ink,
    _runLineWidth,
  );
  kakao.PoiStyle? _currentPositionStyle;

  Future<kakao.PoiStyle> _ensureCurrentPositionStyle() async =>
      _currentPositionStyle ??= kakao.PoiStyle(
        // 기본 앵커는 아래쪽 끝(핀 모양 기준)이라, 마커를 좌표 중심에 놓으려면 옮겨야 한다.
        anchor: const kakao.KPoint(0.5, 0.5),
        icon: await buildMyPositionMarker(),
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
      old.isRunning != widget.isRunning ||
      old.followCurrentPosition != widget.followCurrentPosition ||
      old.showCourseDirection != widget.showCourseDirection ||
      !identical(_lastSample, widget.currentPosition) ||
      !_isSamePath(old.coursePath, widget.coursePath) ||
      !_isSamePath(old.runPath, widget.runPath) ||
      !identical(old.parkings, widget.parkings) ||
      !identical(old.restrooms, widget.restrooms);

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
      return const MissingMapKeyPlaceholder();
    }

    final error = _mapError;
    if (error != null) {
      return MapErrorView(error: error, keyHash: _keyHash);
    }

    // 중심을 모르는 채로는 지도를 만들지 않는다. KakaoMapOption.position은 최초
    // 생성 때 한 번만 읽히므로, 아무 데나 띄워 놓고 좌표가 도착한 뒤 옮기면
    // 그 이동이 그대로 카메라 점프로 보인다(예전의 제주시청 → 현위치 튐).
    final center =
        widget.initialCenter ??
        widget.currentPosition ??
        GeoUtils.centerOf(widget.coursePath) ??
        GeoUtils.centerOf(widget.runPath);
    if (center == null) {
      return widget.isAwaitingLocation
          ? const MapLoadingView()
          : const MapEmptyView();
    }

    return kakao.KakaoMap(
      option: kakao.KakaoMapOption(
        position: center.toLatLng(),
        zoomLevel: _initialZoomLevel,
      ),
      onMapReady: (controller) {
        _controller = controller;
        _redraw();
      },
      // 손가락 제스처만 사용자 이동으로 본다. moveCamera나 추적이 옮긴 경우는
      // SDK가 unknown을 준다.
      onCameraMoveStart: (gestureType) {
        if (gestureType != kakao.GestureType.unknown) {
          widget.onUserMovedCamera?.call();
        }
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
        await _drawCourseEndpoints(controller);
        await _drawFacilities(controller);
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

    // 일시정지 동안에는 isRunning이 false다. 다시 true가 되었다면 재개한
    // 것이고, 멈춰 있는 동안의 이동은 달린 것이 아니므로 선을 이으면 안 된다.
    // 지금까지 그린 선은 그 자리에 그대로 두고 여기서 끊는다.
    // (러닝을 막 시작한 경우에도 지나가지만 끊을 선이 없어 아무 일도 없다.)
    final isResuming = widget.isRunning && !_wasRunning;
    _wasRunning = widget.isRunning;
    if (isResuming) await _breakLiveRoute();

    // 위치는 프로퍼티로 한 점씩 들어온다. 한 프레임 안에 두 점이 오면 뒤엣것만
    // 보이지만, 위치는 아무리 빨라야 매초 오고 프레임은 [_frameInterval]이라
    // 실제로는 겹치지 않는다.
    //
    // 예외가 백그라운드다. 화면이 꺼지면 iOS가 Flutter 프레임을 멈춰 이 위젯은
    // 점을 못 받지만, 위치 스트림은 계속 돌아 tracker.path에는 점이 쌓인다
    // (Info.plist의 UIBackgroundModes 참고). 복귀하면 최신 점 하나만 들어오는데,
    // 그대로 이으면 화면 끈 지점→켠 지점이 직선이 된다. 그 사이 확정 점들을 실제
    // 경로대로 먼저 이어 그리고([_fillLiveGap]), 보간기는 최신 점에서 다시 시작한다.
    if (!identical(_lastSample, position)) {
      final previousSample = _lastSample;
      _lastSample = position;
      if (!_renderClock.isRunning) _renderClock.start();

      if (previousSample != null &&
          _hasBackgroundGap(previousSample, position)) {
        await _fillLiveGap(previousSample, position);
      }
      _interpolator.add(position, _renderClock.elapsed);
    }

    if (_currentPositionMarker == null) {
      final style = await _ensureCurrentPositionStyle();
      if (_disposed) return;
      _currentPositionMarker = await controller.labelLayer.addPoi(
        position.toLatLng(),
        style: style,
      );
      _renderedPosition = position;
    }

    _liveRoute ??= _GrowingRoute(controller.routeLayer, _runStyle, _runZOrder);

    if (widget.isRunning) {
      _startRenderLoop();
      return;
    }

    // 일시정지·종료. 더 이상 점이 오지 않으니 남은 보간분을 끝까지 그리고 멈춘다.
    _stopRenderLoop();
    _stageFrame(_interpolator.settleAll());
  }

  /// 라이브 경로를 여기서 끊는다. 그려 둔 선은 남기고, 다음 점부터 새 선이 된다.
  ///
  /// 보간기까지 비우는 이유는, 남겨 두면 끊기기 전 마지막 점과 재개 후 첫 점
  /// 사이를 "이동 중"으로 보고 그 사이를 채워 그리기 때문이다.
  ///
  /// [_lastSample]은 비우지 않는다. 재개 직후 위젯이 들고 있는 currentPosition은
  /// 아직 멈추기 전 마지막 점이라, 비우면 그 점이 새 구간의 첫 점으로 다시 들어가
  /// 멈춘 자리와 재개한 자리가 선으로 이어진다. 남겨 두면 같은 점이라 걸러진다.
  Future<void> _breakLiveRoute() async {
    final live = _liveRoute;
    if (live == null) return;

    // 일시정지 때 흘려보낸 점들이 아직 그려지는 중일 수 있다. 그 점들은 끊기기
    // 전 구간에 속하므로, 다 그려진 뒤에 끊어야 새 구간으로 넘어가지 않는다.
    await _renderIdle;
    if (_disposed || !identical(_liveRoute, live)) return;

    _interpolator.clear();
    _pendingSettled.clear();
    _pendingPosition = null;
    _renderedPosition = null;

    await live.breakHere();
  }

  /// 정상 위치 갱신은 매초 온다. 두 샘플 시각이 이보다 한참 벌어졌으면
  /// 그 사이 화면 프레임이 멈춰 있었다는 뜻(대개 백그라운드)이라, 놓친 구간을
  /// 채워야 한다.
  static const Duration _backgroundGapThreshold = Duration(seconds: 3);

  bool _hasBackgroundGap(GeoPoint previous, GeoPoint current) {
    final from = previous.recordedAt;
    final to = current.recordedAt;
    if (from == null || to == null) return false;
    return to.difference(from) > _backgroundGapThreshold;
  }

  /// 화면이 멈춰 있던 동안 tracker.path에 쌓인 확정 점들([from]과 [to] 사이)을
  /// 라이브 경로에 실제 순서대로 이어 그린다. 직선 대신 진짜 경로가 남는다.
  ///
  /// 이어 그린 뒤 보간기를 비우는 게 요점이다. 안 그러면 곧이어 들어가는 최신 점을
  /// 보간기가 [from]에서부터 이어 [from]→[to]를 다시 직선으로 긋는다. 비워 두면
  /// 최신 점이 방금 그린 마지막 점에서 자연스럽게 이어진다.
  Future<void> _fillLiveGap(GeoPoint from, GeoPoint to) async {
    final live = _liveRoute;
    if (live == null) return;

    final fromAt = from.recordedAt;
    final toAt = to.recordedAt;
    if (fromAt == null || toAt == null) return;

    // 이미 위젯에 들어와 있는 tracker.path에서 두 샘플 사이 구간만 고른다
    // (새 데이터를 만들지 않는다). 정상 갱신이면 사이에 낀 점이 없어 비어 있다.
    final gap = <GeoPoint>[
      for (final point in widget.runPath)
        if (point.recordedAt case final at?)
          if (at.isAfter(fromAt) && at.isBefore(toAt)) point,
    ];
    if (gap.isEmpty) return;

    // 렌더 루프가 오버레이를 만지는 중이면 끝나길 기다린 뒤 잇는다
    // ([_breakLiveRoute]와 같은 이유 — 그 사이 러닝이 초기화되면 손 뗀다).
    await _renderIdle;
    if (_disposed || !identical(_liveRoute, live)) return;

    await live.append(gap);
    _interpolator.clear();
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
    _wasRunning = false;
    _hasAppliedRunningZoom = false;

    final marker = _currentPositionMarker;
    if (marker != null) {
      _stopTracking(controller);
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
    final withArrows = widget.showCourseDirection;
    if (_drawnCoursePath != null &&
        _isSamePath(_drawnCoursePath!, points) &&
        _drawnCourseDirection == withArrows) {
      return;
    }

    final style = await _ensureCourseStyle(withArrows);
    if (style == null || _disposed) return;

    // 단일 선형과 다중 선형은 제자리 갱신이 서로 호환되지 않아 통째로 바꾼다.
    // 코스는 러닝 시작·종료에만 다시 그리므로 비용은 무시할 만하다.
    final existing = _courseRoute;
    if (existing != null) {
      await controller.routeLayer.removeRoute(existing);
      _courseRoute = null;
    }

    final drawable = GeoUtils.simplify(points, _courseDrawTolerance);
    if (drawable.length < 2) {
      _drawnCoursePath = points;
      _drawnCourseDirection = withArrows;
      return;
    }

    if (withArrows) {
      final option = kakao.MultipleRouteOption([style], zOrder: _courseZOrder);
      for (final piece in GeoUtils.splitAtBends(
        drawable,
        _courseBendThreshold,
      )) {
        option.addRouteWithIndex(piece.map((p) => p.toLatLng()).toList(), 0);
      }
      _courseRoute = await controller.routeLayer.addMultipleRoute(option);
    } else {
      _courseRoute = await controller.routeLayer.addRoute(
        drawable.map((p) => p.toLatLng()).toList(),
        style,
        zOrder: _courseZOrder,
      );
    }
    if (_disposed) {
      await _courseRoute?.remove();
      _courseRoute = null;
      return;
    }
    _drawnCoursePath = points;
    _drawnCourseDirection = withArrows;
  }

  /// 코스 선 스타일. 화살표 유무로 둘을 따로 만들어 두고 갈아 끼운다.
  ///
  /// 하나를 고쳐 쓰지 않는 이유: 스타일은 지도에 처음 쓰일 때 한 번만 네이티브에
  /// 등록되고, 같은 id로 다시 등록하면 iOS·안드로이드 모두 건너뛴다 — 나중에
  /// pattern 필드를 고쳐 봐야 화면에 반영되지 않는다.
  Future<kakao.RouteStyle?> _ensureCourseStyle(bool withArrows) async {
    if (!withArrows) {
      return _plainCourseStyle ??= kakao.RouteStyle(
        AppColors.accent,
        _courseLineWidth,
      );
    }

    if (_arrowCourseStyle != null) return _arrowCourseStyle;
    final arrow = await buildCourseDirectionArrow();
    if (_disposed) return null;
    return _arrowCourseStyle = kakao.RouteStyle(
      AppColors.accent,
      _courseLineWidth,
      pattern: kakao.RoutePattern(arrow, _arrowSpacing),
    );
  }

  /// 코스 시작/끝점에 '출발'/'도착' 배지를 찍는다. 시작과 끝이 사실상 같은
  /// 순환 코스에는 '출발·도착' 하나만 찍는다.
  Future<void> _drawCourseEndpoints(kakao.KakaoMapController controller) async {
    final points = widget.coursePath;
    if (_drawnEndpointPath != null &&
        _isSamePath(_drawnEndpointPath!, points)) {
      return;
    }

    for (final marker in _endpointMarkers) {
      await marker.remove();
      if (_disposed) return;
    }
    _endpointMarkers.clear();

    if (points.length >= 2) {
      final isLoop =
          GeoUtils.distanceBetween(points.first, points.last) <=
          loopEndpointThresholdMeters;

      Future<void> place(GeoPoint point, kakao.PoiStyle? style) async {
        if (style == null || _disposed) return;
        final poi = await controller.labelLayer.addPoi(
          point.toLatLng(),
          style: style,
        );
        if (_disposed) {
          await poi.remove();
          return;
        }
        _endpointMarkers.add(poi);
      }

      if (isLoop) {
        await place(
          points.first,
          await _ensureEndpointStyle(startEndpointColor, loopEndpointLabel),
        );
      } else {
        // 출발을 나중에 찍어, 짧은 코스에서 겹치면 출발이 위에 오게 한다.
        await place(
          points.last,
          await _ensureEndpointStyle(finishEndpointColor, finishEndpointLabel),
        );
        if (_disposed) return;
        await place(
          points.first,
          await _ensureEndpointStyle(startEndpointColor, startEndpointLabel),
        );
      }
      if (_disposed) return;
    }

    _drawnEndpointPath = points;
  }

  Future<kakao.PoiStyle?> _ensureEndpointStyle(
    Color color,
    String label,
  ) async {
    final cached = _endpointStyles[label];
    if (cached != null) return cached;

    final icon = await buildCourseEndpointChip(color, label);
    if (_disposed) return null;
    return _endpointStyles[label] = kakao.PoiStyle(
      anchor: const kakao.KPoint(0.5, 0.5),
      icon: icon,
    );
  }

  /// 코스 주차장(파란 'P')·화장실(초록 'WC') 배지를 좌표에 찍는다. 러닝 중 안
  /// 바뀌는 정적 마커라 처음 한 번만 그린다(CourseMapView와 같은 배지를 쓴다).
  Future<void> _drawFacilities(kakao.KakaoMapController controller) async {
    if (identical(_drawnParkings, widget.parkings) &&
        identical(_drawnRestrooms, widget.restrooms)) {
      return;
    }

    for (final marker in _facilityMarkers) {
      await marker.remove();
      if (_disposed) return;
    }
    _facilityMarkers.clear();

    // 찍을 시설이 없으면 배지 이미지를 만들 이유도 없다.
    if (widget.parkings.isEmpty && widget.restrooms.isEmpty) {
      _drawnParkings = widget.parkings;
      _drawnRestrooms = widget.restrooms;
      return;
    }

    final parkingStyle = await _ensureParkingStyle();
    final restroomStyle = await _ensureRestroomStyle();
    if (parkingStyle == null || restroomStyle == null || _disposed) return;

    Future<void> place(CourseFacility facility, kakao.PoiStyle style) async {
      final poi = await controller.labelLayer.addPoi(
        kakao.LatLng(facility.lat, facility.lng),
        style: style,
      );
      if (_disposed) {
        await poi.remove();
        return;
      }
      _facilityMarkers.add(poi);
    }

    for (final facility in widget.parkings) {
      await place(facility, parkingStyle);
      if (_disposed) return;
    }
    for (final facility in widget.restrooms) {
      await place(facility, restroomStyle);
      if (_disposed) return;
    }

    _drawnParkings = widget.parkings;
    _drawnRestrooms = widget.restrooms;
  }

  Future<kakao.PoiStyle?> _ensureParkingStyle() async {
    if (_parkingStyle != null) return _parkingStyle;
    final icon = await buildFacilityBadge(parkingBadgeColor, parkingBadgeLabel);
    if (_disposed) return null;
    return _parkingStyle = kakao.PoiStyle(
      anchor: const kakao.KPoint(0.5, 0.5),
      icon: icon,
    );
  }

  Future<kakao.PoiStyle?> _ensureRestroomStyle() async {
    if (_restroomStyle != null) return _restroomStyle;
    final icon = await buildFacilityBadge(
      restroomBadgeColor,
      restroomBadgeLabel,
    );
    if (_disposed) return null;
    return _restroomStyle = kakao.PoiStyle(
      anchor: const kakao.KPoint(0.5, 0.5),
      icon: icon,
    );
  }

  /// 정지 화면의 경로. 라이브 위치가 있으면 [_GrowingRoute]가 대신 그리므로
  /// 여기서는 지운다.
  ///
  /// 일시정지로 끊긴 자리에서 선을 나눠 그린다([GeoPoint.startsNewSegment]).
  /// 이어 그리면 멈춰 있는 동안 이동한 구간이 달린 길처럼 보이는데, 거리에도
  /// 서버 검증에도 안 들어가는 구간이라 기록과 그림이 어긋난다.
  ///
  /// 코스와 달리 여기서는 선을 제자리 갱신하지 않고 지웠다 다시 그린다. 정지
  /// 화면의 경로는 화면을 열 때 한 번 정해지고 끝이라 아낄 갱신이 없다.
  Future<void> _drawStaticRunPath(kakao.KakaoMapController controller) async {
    final points = widget.currentPosition == null
        ? widget.runPath
        : const <GeoPoint>[];

    if (_drawnStaticRunPath != null &&
        _isSamePath(_drawnStaticRunPath!, points)) {
      return;
    }
    _drawnStaticRunPath = points;

    for (final route in _staticRunRoutes) {
      await controller.routeLayer.removeRoute(route);
    }
    _staticRunRoutes.clear();

    for (final segment in _splitAtBreaks(points)) {
      // 선이 되려면 점이 둘 이상 필요하다. 재개하자마자 끝난 구간은 건너뛴다.
      if (segment.length < 2) continue;

      _staticRunRoutes.add(
        await controller.routeLayer.addRoute(
          segment.map((p) => p.toLatLng()).toList(),
          _runStyle,
          zOrder: _runZOrder,
        ),
      );
    }
  }

  /// 기록이 끊긴 자리에서 경로를 나눈다.
  static List<List<GeoPoint>> _splitAtBreaks(List<GeoPoint> points) {
    final segments = <List<GeoPoint>>[];
    var current = <GeoPoint>[];

    for (final point in points) {
      if (point.startsNewSegment && current.isNotEmpty) {
        segments.add(current);
        current = [];
      }
      current.add(point);
    }

    if (current.isNotEmpty) segments.add(current);
    return segments;
  }

  Future<void> _moveCamera(kakao.KakaoMapController controller) async {
    final position = widget.currentPosition;
    if (widget.followCurrentPosition && position != null) {
      // 따라가기를 (다시) 켜는 순간 현위치로 옮긴다. 러닝 첫 시작이면 코스
      // 전체를 보던 배율에서 러닝용 배율로 당기고, 껐다 켠 것이면 쓰던 배율
      // 그대로다. 위치 갱신마다 옮기지는 않는다 — 그건 TrackingController가 한다.
      if (!_isFollowing) {
        _isFollowing = true;
        if (!_hasAppliedRunningZoom) {
          _hasAppliedRunningZoom = true;
          _followZoomLevel = _runningZoomLevel;
        }
        await controller.moveCamera(
          kakao.CameraUpdate.newCenterPosition(
            position.toLatLng(),
            zoomLevel: _followZoomLevel,
          ),
        );
      }

      _startTracking(controller);
      return;
    }

    // 따라가기가 꺼졌다(사용자가 지도를 밀었거나 러닝이 끝났다).
    _isFollowing = false;
    _stopTracking(controller);

    // 그릴 것을 처음 받았을 때 한 번만 전체가 보이도록 맞춘다.
    //
    // 코스뿐 아니라 **달린 경로도** 대상이다. 예전에는 코스만 봐서, 코스 없이
    // 달린 기록을 보여주는 결과 화면([RunResultScreen])은 초기 배율(16)에
    // 경로 한가운데만 잡힌 채 그대로 있었다. 6km를 달렸으면 화면에는 400m쯤이
    // 보이고 경로는 사방으로 삐져나갔다.
    //
    // 라이브 위치가 있는 동안에는 하지 않는다. 러닝 중에는 현위치를 따라가야
    // 하고, 일시정지했다고 카메라가 갑자기 전체 경로로 물러나면 곤란하다.
    if (!_hasFittedStaticPath && widget.currentPosition == null) {
      final points = [...widget.coursePath, ...widget.runPath];
      if (points.length >= 2) {
        _hasFittedStaticPath = true;
        await controller.moveCamera(
          kakao.CameraUpdate.fitMapPoints(
            points.map((p) => p.toLatLng()).toList(),
            padding: _fitPadding,
          ),
        );
      }
    }
  }

  /// 카메라가 현위치 마커를 따라다니게 한다.
  ///
  /// 우리가 프레임마다 moveCamera를 부르는 것과 결과는 같아 보이지만, 이동을
  /// 네이티브가 마커와 같은 타임라인으로 처리해서 카메라와 마커가 따로 놀지
  /// 않는다. 회전 추적(setTrackingRotate)은 켜지 않는다 — 마커가 원형이라 방향이
  /// 없고, 지도가 돌면 코스 폴리라인만 읽기 어려워진다.
  ///
  /// 시작·정지를 **기다리지 않는다.** 두 호출이 돌려주는 값은 늘 null이라
  /// 기다려서 얻는 정보가 없고(추적이 실제로 걸렸는지는 알려주지 않는다),
  /// 안드로이드 네이티브는 아예 응답을 돌려주지 않아 기다리면 [_redraw]가
  /// 그 자리에서 영영 멈춘다 — 그러면 이후 코스·정지경로 갱신과 일시정지
  /// 처리까지 통째로 죽는다.
  ///
  /// 같은 채널로 나가는 메시지는 순서가 보장되므로, 정지 요청은 뒤이어 나가는
  /// 마커 삭제([_clearLive])보다 반드시 먼저 네이티브에 닿는다.
  void _startTracking(kakao.KakaoMapController controller) {
    final marker = _currentPositionMarker;
    if (_isTracking || marker == null) return;

    controller.tracking.poi = marker;
    unawaited(controller.tracking.start());
    _isTracking = true;
  }

  void _stopTracking(kakao.KakaoMapController controller) {
    if (!_isTracking) return;

    unawaited(controller.tracking.stop());
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
        //
        // 애니메이션 시간은 주지 않는다. 부드러움은 보간기가 프레임마다 연속
        // 좌표를 주는 것으로 이미 보장되고, 여기에 애니메이션을 얹으면 즉시
        // 움직이는 경로 끝보다 마커가 항상 그만큼 뒤처진다.
        //
        // 호출 사이마다 상태를 다시 본다. await 동안 화면이 사라지거나 러닝이
        // 초기화되면 이미 걷어낸 오버레이를 이어서 건드리게 된다.
        await marker.move(position.toLatLng());
        if (!_isLiveCurrent(live, marker)) break;
        if (settled.isNotEmpty) await live.append(settled);
        if (!_isLiveCurrent(live, marker)) break;

        await live.moveTip(position);
        _renderedPosition = position;
      }
    } finally {
      _isRendering = false;
    }
  }

  /// 프레임을 시작할 때 잡아 둔 오버레이가 아직 화면에 살아 있는지.
  bool _isLiveCurrent(_GrowingRoute live, kakao.Poi marker) =>
      !_disposed &&
      identical(_liveRoute, live) &&
      identical(_currentPositionMarker, marker);

  static bool _isSameCoordinate(GeoPoint? a, GeoPoint? b) =>
      a != null &&
      b != null &&
      a.latitude == b.latitude &&
      a.longitude == b.longitude;

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
      _openPoints.add(point.toLatLng());
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
    if (_RunMapViewState._isSameCoordinate(anchor, position)) {
      if (_isTailVisible) {
        _isTailVisible = false;
        await _tail?.hide();
      }
      return;
    }

    final points = [anchor.toLatLng(), position.toLatLng()];
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

  /// 여기서 선을 끊는다. 지금까지 그린 것은 그대로 두고, 다음에 들어오는 점부터
  /// 새 선으로 이어 그린다.
  ///
  /// 끊긴 자리에서 [_chunks]를 비우지 않는 것이 요점이다 — 그려 둔 선은 화면에
  /// 남아야 하고, [clear]가 나중에 한꺼번에 걷어간다.
  Future<void> breakHere() async {
    // 꼬리는 확정 구간 끝에서 현위치까지를 잇는 임시선이라, 끊긴 자리에서는
    // 이을 곳이 없다. 감춰 두면 다음 구간에서 그대로 다시 쓴다.
    if (_isTailVisible) {
      _isTailVisible = false;
      await _tail?.hide();
    }

    _open = null;
    _openPoints = [];
    _lastPoint = null;
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
}
