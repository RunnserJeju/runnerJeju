import 'package:flutter/material.dart';
// 카카오맵 SDK는 Route, Polygon 등 머티리얼과 겹치는 이름을 내보내므로 접두사를 붙인다.
import 'package:kakao_map_sdk/kakao_map_sdk.dart' as kakao;

import '../config/app_config.dart';
import '../models/geo_point.dart';
import '../theme/app_theme.dart';
import '../utils/geo_utils.dart';

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

  /// 따라 달릴 코스 경로. 회색 실선으로 그린다.
  final List<GeoPoint> coursePath;

  /// 사용자가 실제로 달린 경로. 강조색 실선으로 그린다.
  final List<GeoPoint> runPath;

  /// 현재 위치. 원형 마커로 표시한다.
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

class _RunMapViewState extends State<RunMapView> {
  kakao.KakaoMapController? _controller;

  // 오버레이는 ID가 아니라 객체 참조로 다룬다. 매번 지우고 다시 그리는 대신
  // changePoint/changePosition으로 제자리 갱신해야 러닝 중 깜빡임이 없다.
  kakao.Route? _courseRoute;
  kakao.Route? _runRoute;
  // addPolygonShape는 Polygon<CirclePoint>가 아니라 Polygon을 반환하므로 그대로 받는다.
  kakao.Polygon? _currentPositionMarker;

  bool _hasFittedCourse = false;
  bool _disposed = false;

  // 네이티브 키 인증에 실패하면 지도는 아무것도 그리지 않은 채 빈 화면으로 남는다.
  // 그대로 두면 키 문제인지, 좌표 문제인지, 빌드 문제인지 구분할 수 없어서
  // 오류를 붙잡아 원인과 조치를 화면에 띄운다.
  Object? _mapError;
  String? _keyHash;

  // 오버레이 갱신은 전부 비동기 플랫폼 호출이라, 러닝 중 위치 갱신이 몰리면
  // 이전 호출이 끝나기 전에 다음 호출이 들어온다. 그대로 두면 두 호출이 모두
  // "아직 선이 없다"고 판단해 같은 경로를 두 번 그린다. 갱신을 직렬화하고,
  // 진행 중에 들어온 요청은 마지막 상태로 한 번만 다시 그린다.
  bool _isRedrawing = false;
  bool _needsRedraw = false;

  /// 지도 초기 확대 수준. 값이 클수록 확대된다.
  static const int _initialZoomLevel = 16;

  /// 현재 위치 마커의 반지름(m).
  static const double _currentPositionRadius = 12;

  /// 코스 전체를 화면에 맞출 때 가장자리에 두는 여백(px).
  static const int _fitPadding = 48;

  late final kakao.RouteStyle _courseStyle = kakao.RouteStyle(
    const Color(0xBF7A8593), // 75% 불투명 회색
    6,
  );
  late final kakao.RouteStyle _runStyle = kakao.RouteStyle(AppColors.ink, 7);
  late final kakao.PolygonStyle _currentPositionStyle = kakao.PolygonStyle(
    AppColors.ink,
    strokeWidth: 3,
    strokeColor: Colors.white,
  );

  @override
  void didUpdateWidget(covariant RunMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _redraw();
  }

  @override
  void dispose() {
    _disposed = true;
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

        await _drawCourse(controller);
        await _drawRunPath(controller);
        await _drawCurrentPosition(controller);
        await _moveCamera(controller);
      } while (_needsRedraw && !_disposed);
    } finally {
      _isRedrawing = false;
    }
  }

  Future<void> _drawCourse(kakao.KakaoMapController controller) async {
    _courseRoute = await _syncRoute(
      controller,
      existing: _courseRoute,
      points: widget.coursePath,
      style: _courseStyle,
      zOrder: _courseZOrder,
    );
  }

  Future<void> _drawRunPath(kakao.KakaoMapController controller) async {
    _runRoute = await _syncRoute(
      controller,
      existing: _runRoute,
      points: widget.runPath,
      style: _runStyle,
      zOrder: _runZOrder,
    );
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

  Future<void> _drawCurrentPosition(kakao.KakaoMapController controller) async {
    final position = widget.currentPosition;

    if (position == null) {
      final existing = _currentPositionMarker;
      if (existing != null) {
        await existing.remove();
        _currentPositionMarker = null;
      }
      return;
    }

    final point = kakao.CirclePoint(
      _currentPositionRadius,
      _toLatLng(position),
    );

    final existing = _currentPositionMarker;
    if (existing == null) {
      _currentPositionMarker = await controller.shapeLayer.addPolygonShape(
        point,
        _currentPositionStyle,
      );
      return;
    }

    await existing.changePosition(point);
  }

  Future<void> _moveCamera(kakao.KakaoMapController controller) async {
    final position = widget.currentPosition;
    if (widget.followCurrentPosition && position != null) {
      await controller.moveCamera(
        kakao.CameraUpdate.newCenterPosition(_toLatLng(position)),
      );
      return;
    }

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

  static kakao.LatLng _toLatLng(GeoPoint point) =>
      kakao.LatLng(point.latitude, point.longitude);

  // 달린 경로가 코스 위에 오도록 쌓는 순서를 고정한다.
  static const int _courseZOrder = 10000;
  static const int _runZOrder = 10001;
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
