import 'dart:ui' as ui;

import 'package:flutter/material.dart';
// 카카오맵 SDK는 Route, Polygon 등 머티리얼과 겹치는 이름을 내보내므로 접두사를 붙인다.
import 'package:kakao_map_sdk/kakao_map_sdk.dart' as kakao;

import '../config/app_config.dart';
import '../models/geo_point.dart';
import '../models/running_course.dart';
import '../theme/app_theme.dart';
import 'map_status_views.dart';

/// '러닝' 탭이 쓰는 지도. 코스마다 라벨을 찍고, 라벨을 누르면 알려준다.
///
/// [RunMapView]와 따로 두는 이유는 도는 속도가 다르기 때문이다. 저쪽은 러닝 중
/// 초당 30번 도는 렌더 루프가 핵심이라 마커 하나를 제자리에서 옮기는 데 구조를
/// 다 걸었고, 여기는 움직이지 않는 라벨 수십 개와 탭 처리가 전부다. 한 위젯에
/// 합치면 양쪽 다 읽기 어려워진다.
class CourseMapView extends StatefulWidget {
  const CourseMapView({
    super.key,
    required this.courses,
    this.selectedCourseId,
    this.selectedPath = const [],
    this.myPosition,
    this.onCourseTap,
    this.onMapTap,
    this.controller,
    this.initialCenter,
  });

  /// 지도에 라벨로 찍을 코스들. [RunningCourse.startPoint]가 없는 코스는 빠진다.
  final List<RunningCourse> courses;

  /// 지금 선택된 코스. 라벨을 강조색으로 바꿔 그린다.
  final String? selectedCourseId;

  /// 선택된 코스의 경로. 상세를 받아오기 전에는 비어 있고, 받아오면 실선으로 그린다.
  final List<GeoPoint> selectedPath;

  /// 내 현재 위치. 있으면 점으로 찍는다.
  final GeoPoint? myPosition;

  final ValueChanged<RunningCourse>? onCourseTap;

  /// 라벨이 아닌 지도 바닥을 눌렀을 때. 선택을 푸는 데 쓴다.
  final VoidCallback? onMapTap;

  /// 카메라를 밖에서 움직이기 위한 손잡이.
  final CourseMapController? controller;

  /// 지도를 처음 띄울 중심. 주면 코스 전체를 맞추는 대신 이 자리에서 시작한다.
  ///
  /// 지도를 다시 만들 때 쓴다 — 러닝 화면에 갔다 오면 이 위젯은 새로 태어나므로,
  /// 주지 않으면 코스를 확대해 보던 사람이 제주 전체 화면으로 돌아온다.
  /// 지도가 만들어질 때 한 번만 읽는다.
  final GeoPoint? initialCenter;

  /// 코스를 아직 하나도 못 받았을 때 보여줄 중심(제주도 한가운데).
  static const GeoPoint jejuCenter = GeoPoint(
    latitude: 33.3846,
    longitude: 126.5535,
  );

  @override
  State<CourseMapView> createState() => _CourseMapViewState();
}

/// [CourseMapView]의 카메라를 화면 쪽에서 조작하는 손잡이.
///
/// 지도가 "무엇을 그릴지"는 프로퍼티로 내려가지만, "지금 여기를 비춰라"는 한 번
/// 일어나고 마는 사건이라 프로퍼티로 표현하면 같은 값이 다시 들어왔을 때
/// 움직여야 하는지 알 수 없다. 그래서 명령만 이쪽으로 뺀다.
class CourseMapController {
  _CourseMapViewState? _state;

  /// [point]가 화면 중앙에 오도록 옮긴다.
  Future<void> moveTo(GeoPoint point, {int? zoomLevel}) async =>
      _state?.moveTo(point, zoomLevel: zoomLevel);

  /// 지금 찍혀 있는 코스가 모두 보이도록 맞춘다.
  Future<void> fitCourses() async => _state?.fitCourses();
}

class _CourseMapViewState extends State<CourseMapView> {
  kakao.KakaoMapController? _controller;

  /// 지도에 올라가 있는 라벨. 코스 id로 찾는다.
  final Map<String, kakao.Poi> _markers = {};

  /// 마지막으로 그린 강조 라벨. 선택이 바뀌면 이것만 원래대로 되돌린다.
  String? _highlightedCourseId;

  kakao.Route? _selectedRoute;
  List<GeoPoint>? _drawnSelectedPath;

  kakao.Poi? _myPositionMarker;

  kakao.PoiStyle? _courseStyle;
  kakao.PoiStyle? _selectedCourseStyle;
  late final kakao.PoiStyle _myPositionStyle = kakao.PoiStyle(
    // 기본 앵커는 아래쪽 끝(핀 모양 기준)이라, 점을 좌표 중심에 놓으려면 옮긴다.
    anchor: const kakao.KPoint(0.5, 0.5),
    icon: kakao.KImage.fromAsset(
      'assets/circleMarker.png',
      _myPositionSize,
      _myPositionSize,
    ),
  );
  late final kakao.RouteStyle _routeStyle = kakao.RouteStyle(
    AppColors.accent,
    6,
  );

  /// 코스를 처음 받았을 때 한 번만 전체가 보이도록 맞춘다. 그 뒤로는 사용자가
  /// 옮긴 화면을 목록이 갱신될 때마다 되돌리지 않는다.
  bool _hasFittedCourses = false;

  bool _disposed = false;

  // 갱신은 전부 비동기 플랫폼 호출이라 이전 호출이 끝나기 전에 다음 호출이 들어올
  // 수 있다. 직렬화하고, 진행 중에 들어온 요청은 마지막 상태로 한 번만 다시 그린다.
  bool _isRedrawing = false;
  bool _needsRedraw = false;

  Object? _mapError;
  String? _keyHash;

  /// 코스가 아직 없을 때의 배율. 제주도 전체가 한눈에 들어온다.
  static const int _islandZoomLevel = 10;

  /// 내 위치 점의 화면 크기(dp).
  static const int _myPositionSize = 14;

  /// 코스 전체를 화면에 맞출 때 가장자리에 두는 여백(px).
  static const int _fitPadding = 72;

  static const int _routeZOrder = 9000;

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
  }

  @override
  void didUpdateWidget(covariant CourseMapView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.controller, widget.controller)) {
      if (oldWidget.controller?._state == this) oldWidget.controller?._state = null;
      widget.controller?._state = this;
    }

    if (_hasMapInputChanged(oldWidget)) _redraw();
  }

  bool _hasMapInputChanged(CourseMapView old) =>
      old.selectedCourseId != widget.selectedCourseId ||
      old.myPosition != widget.myPosition ||
      !_isSameCourseList(old.courses, widget.courses) ||
      !identical(old.selectedPath, widget.selectedPath);

  /// 목록이 바뀌었는지. 코스는 서버에서 통째로 다시 받으므로 id 구성만 본다.
  static bool _isSameCourseList(List<RunningCourse> a, List<RunningCourse> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    if (widget.controller?._state == this) widget.controller?._state = null;
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

    return kakao.KakaoMap(
      option: kakao.KakaoMapOption(
        position: _toLatLng(widget.initialCenter ?? CourseMapView.jejuCenter),
        zoomLevel: widget.initialCenter == null
            ? _islandZoomLevel
            : _focusZoomLevel,
      ),
      onMapReady: (controller) {
        _controller = controller;
        _redraw();
      },
      // 라벨을 뺀 지도 바닥만 받는다. onMapClick은 라벨을 눌러도 함께 불려서
      // 방금 고른 코스를 곧바로 다시 지우게 된다.
      onTerrainClick: (_, _) => widget.onMapTap?.call(),
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
  // 카메라 (CourseMapController가 부른다)
  // ---------------------------------------------------------------------------

  Future<void> moveTo(GeoPoint point, {int? zoomLevel}) async {
    final controller = _controller;
    if (controller == null || _disposed) return;

    await controller.moveCamera(
      kakao.CameraUpdate.newCenterPosition(
        _toLatLng(point),
        // 배율을 비우면 SDK가 -1을 보내고 iOS 네이티브가 그걸 그대로 배율로 써서
        // 지도가 최소 배율로 빠진다. 항상 명시적인 값을 넘긴다.
        zoomLevel: zoomLevel ?? _focusZoomLevel,
      ),
      animation: const kakao.CameraAnimation(350),
    );
  }

  Future<void> fitCourses() async {
    final controller = _controller;
    if (controller == null || _disposed) return;

    final points = _markerPoints();
    if (points.isEmpty) return;

    // 점이 하나뿐이면 맞출 영역이 없다. 그 점을 가운데 두는 것으로 갈음한다.
    if (points.length == 1) {
      await moveTo(points.single);
      return;
    }

    await controller.moveCamera(
      kakao.CameraUpdate.fitMapPoints(
        points.map(_toLatLng).toList(),
        padding: _fitPadding,
      ),
      animation: const kakao.CameraAnimation(350),
    );
  }

  /// 코스 하나를 골랐을 때의 배율. 주변 지형이 같이 보이는 정도로 둔다.
  static const int _focusZoomLevel = 14;

  List<GeoPoint> _markerPoints() => [
    for (final course in widget.courses)
      if (course.startPoint != null) course.startPoint!,
  ];

  // ---------------------------------------------------------------------------
  // 그리기
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

        await _syncMarkers(controller);
        await _syncHighlight();
        await _syncSelectedRoute(controller);
        await _syncMyPosition(controller);
        await _fitOnFirstLoad();
      } while (_needsRedraw && !_disposed);
    } finally {
      _isRedrawing = false;
    }
  }

  /// 목록과 지도의 라벨을 맞춘다. 남아 있는 라벨은 건드리지 않는다 — 검색어를
  /// 지웠을 때 화면에 있던 코스가 깜빡이지 않게 하려는 것이다.
  Future<void> _syncMarkers(kakao.KakaoMapController controller) async {
    final style = await _ensureCourseStyle();
    if (style == null || _disposed) return;

    final wanted = {
      for (final course in widget.courses)
        if (course.startPoint != null) course.id: course,
    };

    for (final id in _markers.keys.toList()) {
      if (wanted.containsKey(id)) continue;

      await _markers.remove(id)?.remove();
      if (_highlightedCourseId == id) _highlightedCourseId = null;
      if (_disposed) return;
    }

    for (final course in wanted.values) {
      if (_markers.containsKey(course.id)) continue;

      final marker = await controller.labelLayer.addPoi(
        _toLatLng(course.startPoint!),
        style: style,
        text: course.name,
        onClick: () => widget.onCourseTap?.call(course),
      );
      if (_disposed) {
        await marker.remove();
        return;
      }
      _markers[course.id] = marker;
    }
  }

  /// 선택된 라벨만 강조색 큰 핀으로 바꾼다.
  Future<void> _syncHighlight() async {
    final selected = widget.selectedCourseId;
    if (_highlightedCourseId == selected) return;

    final base = await _ensureCourseStyle();
    final highlight = await _ensureSelectedCourseStyle();
    if (base == null || highlight == null || _disposed) return;

    final previous = _markers[_highlightedCourseId];
    if (previous != null) await previous.changeStyles(base);
    if (_disposed) return;

    final next = selected == null ? null : _markers[selected];
    if (next != null) await next.changeStyles(highlight);
    if (_disposed) return;

    // 강조에 실패한 코스를 기억해 두면 다음 선택 때 되돌릴 라벨을 놓친다.
    _highlightedCourseId = next == null ? null : selected;
  }

  Future<void> _syncSelectedRoute(kakao.KakaoMapController controller) async {
    final points = widget.selectedPath;
    if (_drawnSelectedPath != null &&
        identical(_drawnSelectedPath, points)) {
      return;
    }

    final existing = _selectedRoute;

    // 선이 되려면 점이 둘 이상 필요하다.
    if (points.length < 2) {
      if (existing != null) {
        await controller.routeLayer.removeRoute(existing);
        _selectedRoute = null;
      }
      _drawnSelectedPath = points;
      return;
    }

    final latLngs = points.map(_toLatLng).toList();
    if (existing == null) {
      _selectedRoute = await controller.routeLayer.addRoute(
        latLngs,
        _routeStyle,
        zOrder: _routeZOrder,
      );
    } else {
      await existing.changePoint(latLngs);
    }
    _drawnSelectedPath = points;
  }

  Future<void> _syncMyPosition(kakao.KakaoMapController controller) async {
    final position = widget.myPosition;

    if (position == null) {
      final marker = _myPositionMarker;
      if (marker != null) {
        _myPositionMarker = null;
        await marker.remove();
      }
      return;
    }

    final marker = _myPositionMarker;
    if (marker == null) {
      final created = await controller.labelLayer.addPoi(
        _toLatLng(position),
        style: _myPositionStyle,
      );
      if (_disposed) {
        await created.remove();
        return;
      }
      _myPositionMarker = created;
      return;
    }

    await marker.move(_toLatLng(position));
  }

  Future<void> _fitOnFirstLoad() async {
    if (_hasFittedCourses || _markers.isEmpty) return;
    _hasFittedCourses = true;

    // 처음 볼 자리를 밖에서 정해 줬으면 그 자리를 그대로 둔다.
    if (widget.initialCenter != null) return;

    await fitCourses();
  }

  // ---------------------------------------------------------------------------
  // 라벨 모양
  // ---------------------------------------------------------------------------

  Future<kakao.PoiStyle?> _ensureCourseStyle() async {
    if (_courseStyle != null) return _courseStyle;

    final icon = await _buildPinImage(AppColors.ink, _pinWidth, _pinHeight);
    if (_disposed) return null;

    return _courseStyle = kakao.PoiStyle(
      // 핀 끝이 좌표 위에 놓이도록 아래쪽 가운데를 기준으로 잡는다.
      anchor: const kakao.KPoint(0.5, 1.0),
      icon: icon,
      textStyle: const [
        // 지도 위 글씨라 흰 외곽선을 둘러야 바다·초록 지형 어디서든 읽힌다.
        kakao.PoiTextStyle(
          size: 13,
          color: AppColors.ink,
          stroke: 3,
          strokeColor: Colors.white,
        ),
      ],
    );
  }

  Future<kakao.PoiStyle?> _ensureSelectedCourseStyle() async {
    if (_selectedCourseStyle != null) return _selectedCourseStyle;

    final icon = await _buildPinImage(
      AppColors.accent,
      _selectedPinWidth,
      _selectedPinHeight,
    );
    if (_disposed) return null;

    return _selectedCourseStyle = kakao.PoiStyle(
      anchor: const kakao.KPoint(0.5, 1.0),
      icon: icon,
      textStyle: const [
        kakao.PoiTextStyle(
          size: 14,
          color: AppColors.ink,
          stroke: 3,
          strokeColor: Colors.white,
        ),
      ],
    );
  }

  static const int _pinWidth = 26;
  static const int _pinHeight = 34;
  static const int _selectedPinWidth = 32;
  static const int _selectedPinHeight = 42;

  /// 핀을 그려 지도에 넘길 이미지로 만든다.
  ///
  /// 에셋 PNG 대신 그리는 이유는 색이 둘(기본/선택)이고 크기도 둘이라, 파일로
  /// 두면 같은 모양을 네 벌 관리하게 되기 때문이다. 앱 색을 바꾸면 여기만 따라온다.
  ///
  /// [width]·[height]는 화면 크기(dp)이고, 비트맵은 그보다 [_pinPixelRatio]배
  /// 크게 그린다. 그래야 고밀도 화면에서 가장자리가 뭉개지지 않는다.
  static Future<kakao.KImage> _buildPinImage(
    Color color,
    int width,
    int height,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(_pinPixelRatio);

    final w = width.toDouble();
    final h = height.toDouble();
    final radius = w / 2 - _pinBorder;
    final center = Offset(w / 2, radius + _pinBorder);

    // 머리(원)와 꼬리(삼각형)를 합쳐 하나의 외곽선으로 만든다. 따로 그리면
    // 겹치는 자리에 흰 테두리가 가로질러 그어진다.
    final head = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    final tail = Path()
      ..moveTo(center.dx - radius * 0.62, center.dy + radius * 0.55)
      ..lineTo(center.dx, h - _pinBorder / 2)
      ..lineTo(center.dx + radius * 0.62, center.dy + radius * 0.55)
      ..close();
    final pin = Path.combine(ui.PathOperation.union, head, tail);

    canvas.drawPath(pin, Paint()..color = color);
    canvas.drawPath(
      pin,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = _pinBorder,
    );
    canvas.drawCircle(
      center,
      radius * 0.34,
      Paint()..color = Colors.white,
    );

    final image = await recorder.endRecording().toImage(
      (w * _pinPixelRatio).round(),
      (h * _pinPixelRatio).round(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();

    return kakao.KImage.fromData(
      data!.buffer.asUint8List(),
      width,
      height,
    );
  }

  static const double _pinBorder = 2;
  static const double _pinPixelRatio = 3;

  static kakao.LatLng _toLatLng(GeoPoint point) =>
      kakao.LatLng(point.latitude, point.longitude);
}
