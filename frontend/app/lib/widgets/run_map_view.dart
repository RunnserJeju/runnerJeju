import 'package:flutter/material.dart';
import 'package:kakao_map_plugin/kakao_map_plugin.dart' as kakao;

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
  bool _hasFittedCourse = false;

  static const String _courseLineId = 'course-line';
  static const String _runLineId = 'run-line';
  static const String _currentPositionId = 'current-position';

  @override
  void didUpdateWidget(covariant RunMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _redraw();
  }

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.hasKakaoMapKey) {
      return const _MissingMapKeyPlaceholder();
    }

    final center = widget.initialCenter ??
        GeoUtils.centerOf(widget.coursePath) ??
        GeoUtils.centerOf(widget.runPath) ??
        RunMapView.defaultCenter;

    return kakao.KakaoMap(
      center: _toLatLng(center),
      currentLevel: 4,
      zoomControl: false,
      mapTypeControl: false,
      onMapCreated: (controller) {
        _controller = controller;
        _redraw();
      },
    );
  }

  void _redraw() {
    final controller = _controller;
    if (controller == null) return;

    _drawPolylines(controller);
    _drawCurrentPosition(controller);
    _moveCamera(controller);
  }

  void _drawPolylines(kakao.KakaoMapController controller) {
    final lines = <kakao.Polyline>[];

    if (widget.coursePath.length >= 2) {
      lines.add(
        kakao.Polyline(
          polylineId: _courseLineId,
          points: widget.coursePath.map(_toLatLng).toList(),
          strokeColor: const Color(0xFF7A8593),
          strokeWidth: 6,
          strokeOpacity: 0.75,
        ),
      );
    }

    if (widget.runPath.length >= 2) {
      lines.add(
        kakao.Polyline(
          polylineId: _runLineId,
          points: widget.runPath.map(_toLatLng).toList(),
          strokeColor: AppColors.ink,
          strokeWidth: 7,
          strokeOpacity: 1,
        ),
      );
    }

    if (lines.isEmpty) {
      controller.clearPolyline(
        polylineIds: const [_courseLineId, _runLineId],
      );
      return;
    }

    controller.addPolyline(polylines: lines);
  }

  void _drawCurrentPosition(kakao.KakaoMapController controller) {
    final position = widget.currentPosition;
    if (position == null) {
      controller.clearCircle(circleIds: const [_currentPositionId]);
      return;
    }

    controller.addCircle(
      circles: [
        kakao.Circle(
          circleId: _currentPositionId,
          center: _toLatLng(position),
          radius: 12,
          strokeWidth: 3,
          strokeColor: Colors.white,
          strokeOpacity: 1,
          fillColor: AppColors.ink,
          fillOpacity: 1,
        ),
      ],
    );
  }

  void _moveCamera(kakao.KakaoMapController controller) {
    final position = widget.currentPosition;
    if (widget.followCurrentPosition && position != null) {
      controller.panTo(_toLatLng(position));
      return;
    }

    // 코스를 처음 받아왔을 때 한 번만 전체가 보이도록 맞춘다.
    if (!_hasFittedCourse && widget.coursePath.length >= 2) {
      _hasFittedCourse = true;
      controller.fitBounds(widget.coursePath.map(_toLatLng).toList());
    }
  }

  static kakao.LatLng _toLatLng(GeoPoint point) =>
      kakao.LatLng(point.latitude, point.longitude);
}

/// 카카오맵 키 없이 빌드했을 때 지도 대신 보여주는 안내.
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
                '지도를 표시하려면 카카오맵 키가 필요해요',
                style: Theme.of(context).textTheme.titleSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              const Text(
                '--dart-define=KAKAO_MAP_KEY=발급받은_JavaScript_키',
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
