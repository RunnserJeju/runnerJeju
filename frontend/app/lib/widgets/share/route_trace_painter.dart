import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/geo_point.dart';
import '../../utils/geo_utils.dart';
import '../../utils/map_projection.dart';

/// 달린 경로를 선 하나로 그린다(route trace).
///
/// 카카오맵 위젯을 그대로 쓰지 못하는 이유는 기술적이다 — 네이티브 플랫폼
/// 뷰라서 [RepaintBoundary]로 캡처하면 빈 화면이 나온다. 그래서 배경으로는
/// 정적 지도 **이미지**를 깔고(`GET /maps/static`), 경로는 여기서 직접 그린다.
///
/// [projection]을 주면 그 지도 이미지의 기준에 맞춰 경로를 놓는다. 없으면
/// 경로만 박스에 꽉 차게 배치한다 — 지도를 받아오지 못했을 때의 모습이다.
///
/// 캔버스 좌표는 카드의 설계 좌표(1080×1920 기준)를 그대로 받는다. 카드 전체가
/// [FittedBox]로 축소되므로 [strokeWidth] 같은 값을 화면 크기에 맞춰 조정할
/// 필요가 없다.
class RouteTracePainter extends CustomPainter {
  RouteTracePainter({
    required this.path,
    required this.color,
    required this.dotFill,
    this.projection,
  });

  final List<GeoPoint> path;

  /// 경로선과 시작점 링의 색.
  final Color color;

  /// 시작점 링 안쪽을 메우는 색. 카드 배경색을 주면 링으로 보인다.
  final Color dotFill;

  /// 뒤에 깔린 지도 이미지의 투영. 주면 경로를 **지도에 맞춰** 놓는다.
  ///
  /// 없으면 경로만 박스에 꽉 차게 배치한다(지도 없이 쓸 때). 지도가 있는데도
  /// 자기 기준으로 배치하면 경로가 실제 도로와 따로 놀아, 지도를 깐 의미가
  /// 사라진다.
  final MapProjection? projection;

  /// 선 굵기. 카드 설계 좌표(1080px 폭) 기준이다.
  static const double strokeWidth = 14;

  /// 경로가 박스 가장자리에 닿지 않도록 두는 여유. [projection]이 있으면
  /// 배치를 지도가 정하므로 쓰이지 않는다.
  static const double _padding = 30;

  /// 그림용으로 걷어낼 잔 꼭짓점의 허용 오차(m).
  ///
  /// GPS 경로는 직선 도로에서도 몇 m씩 흔들린 점이 촘촘히 찍혀 있다. 그대로
  /// 그리면 선이 잘게 떨려서 1080px로 키웠을 때 지저분하다. 지도(2m)보다 크게
  /// 잡는 이유는 카드의 경로 박스가 지도보다 훨씬 작아서다 — 이 축척에서는
  /// 5m 흔들림이 1px도 되지 않는다.
  static const double _simplifyTolerance = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final projected = _project(size);
    if (projected.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    for (final segment in projected) {
      // 점이 하나뿐인 조각은 선이 되지 않는다. 재개하자마자 끝난 구간이 그렇다.
      // 그래도 달린 자리이므로 점으로 찍어 남긴다.
      if (segment.length == 1) {
        canvas.drawCircle(
          segment.first,
          strokeWidth / 2,
          Paint()..color = color,
        );
        continue;
      }

      final line = Path()..moveTo(segment.first.dx, segment.first.dy);
      for (final p in segment.skip(1)) {
        line.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(line, paint);
    }

    _drawStartDot(canvas, projected.first.first);
  }

  /// 출발점 표시.
  ///
  /// 코스는 전부 왕복이거나 순환이라 시작점과 끝점이 거의 같은 자리에 온다.
  /// 그래서 '출발'과 '도착'을 따로 찍지 않는다 — 두 배지가 겹쳐서 하나로
  /// 보이거나, 붙어 있어서 어느 쪽이 어느 쪽인지 알 수 없게 된다.
  void _drawStartDot(Canvas canvas, Offset at) {
    final radius = strokeWidth * 1.5;
    canvas.drawCircle(at, radius, Paint()..color = dotFill);
    canvas.drawCircle(
      at,
      radius,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth * 0.9
        ..isAntiAlias = true,
    );
  }

  /// 위경도를 캔버스 좌표로 옮긴다. 끊긴 구간마다 조각이 하나씩 나온다.
  ///
  /// 경도는 위도에 따라 실제 거리가 달라지므로 `cos(lat)`으로 줄인다. 이걸
  /// 빼먹으면 제주(위도 33°) 경로가 동서로 20% 늘어나 실제로 달린 모양과
  /// 달라진다. 가로세로비는 유지한다 — 박스를 채우려고 늘리면 경로가 왜곡돼서
  /// "내가 뛴 모양"이 아니게 된다.
  List<List<Offset>> _project(Size size) {
    final map = projection;
    if (map != null) {
      return [
        for (final segment in GeoUtils.splitAtBreaks(path))
          if (segment.isNotEmpty)
            [
              for (final p in GeoUtils.simplify(segment, _simplifyTolerance))
                () {
                  final px = map.toPixel(p);
                  return Offset(px.dx, px.dy);
                }(),
            ],
      ];
    }

    final bounds = GeoUtils.boundsOf(path);
    if (bounds == null) return const [];

    final cosLat = math.cos(
      (bounds.southWest.latitude + bounds.northEast.latitude) /
          2 *
          math.pi /
          180,
    );

    final spanX = (bounds.northEast.longitude - bounds.southWest.longitude) *
        cosLat;
    final spanY = bounds.northEast.latitude - bounds.southWest.latitude;

    final boxWidth = math.max(size.width - _padding * 2, 1.0);
    final boxHeight = math.max(size.height - _padding * 2, 1.0);

    // 한 점에 머문 기록(spanX/spanY가 0)은 확대 배율이 무한이 된다. 그때는
    // 배율을 0으로 둬서 모든 점이 박스 중앙에 모이게 한다.
    final scale = (spanX <= 0 && spanY <= 0)
        ? 0.0
        : math.min(
            spanX <= 0 ? double.infinity : boxWidth / spanX,
            spanY <= 0 ? double.infinity : boxHeight / spanY,
          );

    final offsetX = (size.width - spanX * scale) / 2;
    final offsetY = (size.height - spanY * scale) / 2;

    Offset toCanvas(GeoPoint p) => Offset(
      offsetX +
          (p.longitude - bounds.southWest.longitude) * cosLat * scale,
      // 북쪽이 위로 가도록 위도를 뒤집는다.
      offsetY + (bounds.northEast.latitude - p.latitude) * scale,
    );

    return [
      for (final segment in GeoUtils.splitAtBreaks(path))
        if (segment.isNotEmpty)
          [
            for (final p in GeoUtils.simplify(segment, _simplifyTolerance))
              toCanvas(p),
          ],
    ];
  }

  @override
  bool shouldRepaint(RouteTracePainter old) =>
      old.path != path ||
      old.projection != projection ||
      old.color != color ||
      old.dotFill != dotFill;
}
