import 'package:flutter/material.dart';

import '../../models/geo_point.dart';
import '../../services/jeju_basemap.dart';
import '../../utils/map_projection.dart';

/// 공유 카드 배경의 제주 지형.
///
/// 지도 타일을 받아 쓰지 못해 직접 그린다(사유는 [JejuBasemap] 참고).
/// 골목과 등산로까지 그린다 — 큰길만 있으면 지도가 텅 비어 "어디를 달렸는지"를
/// 말해 주지 못한다. 오름 코스에서는 등산로가 곧 달린 길이다.
///
/// 좌표 → 픽셀 변환은 [projection]이 맡는다. 경로를 그리는
/// `RouteTracePainter`가 같은 투영을 쓰므로 둘이 어긋날 수 없다.
///
/// 제주 전체 도로가 3만 5천 개라 그릴 때마다 전부 변환하면 느려진다. 그래서
/// 화면이 덮는 위경도 범위를 한 번 구해 두고([MapProjection.visibleBounds])
/// 선마다 미리 담아 둔 경계 상자와 견줘 걸러 낸다. 숫자 네 번 비교로 끝나고,
/// 실제로 변환하는 건 화면에 걸친 것뿐이다.
class JejuBasemapPainter extends CustomPainter {
  const JejuBasemapPainter({
    required this.basemap,
    required this.projection,
    required this.palette,
    this.route = const [],
  });

  final JejuBasemap basemap;
  final MapProjection projection;
  final BasemapPalette palette;

  /// 이 위에 그려질 러닝 경로.
  ///
  /// 라벨을 피해 놓기 위해서만 쓴다 — 경로는 이 페인터가 그리지 않는다.
  /// 경로가 글자를 가로지르면 글자가 잘린 것처럼 보여서, 겹치는 이름은 뺀다.
  final List<GeoPoint> route;

  /// 라벨을 최대 몇 개까지 얹을지. 더 넣으면 글자가 서로 붙어 읽히지 않는다.
  static const int _maxLabels = 5;

  /// 라벨끼리 이만큼(px)은 떨어뜨린다.
  static const double _labelSpacing = 60;

  /// 경로선에서 이만큼(px) 안쪽에 걸리는 이름은 놓지 않는다.
  ///
  /// 넉넉히 잡으면 경로가 화면을 채우는 순환 코스에서 이름이 **전부** 사라진다.
  /// 글자에 할로가 있어 살짝 스치는 정도는 읽히므로, 실제로 가로지르는 경우만
  /// 뺀다.
  static const double _routeClearance = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.clipRect(bounds);
    canvas.drawRect(bounds, Paint()..color = palette.sea);

    final visible = projection.visibleBounds();

    _fillLand(canvas, visible);

    // 좁은 길부터 깔고 큰길을 위에 얹는다. 그래야 교차로에서 큰길이 끊겨
    // 보이지 않는다.
    _strokeRoads(
      canvas,
      basemap.minorRoads,
      visible,
      palette.minorRoad,
      palette.minorRoadWidth,
    );
    _strokeRoads(
      canvas,
      basemap.midRoads,
      visible,
      palette.midRoad,
      palette.midRoadWidth,
    );
    _strokeRoads(
      canvas,
      basemap.majorRoads,
      visible,
      palette.majorRoad,
      palette.majorRoadWidth,
    );

    _strokeCoastline(canvas, visible);
    _drawLabels(canvas, size);
  }

  /// 뭍을 칠한다.
  ///
  /// 해안선은 이미 닫힌 고리로 들어온다(빌드 단계에서 이어 붙였다). 그래서
  /// 바다를 깔고 고리 안쪽을 칠하기만 하면 된다.
  void _fillLand(Canvas canvas, _Bounds visible) {
    final land = Paint()..color = palette.land;

    for (final ring in basemap.coastline) {
      if (!ring.intersects(visible)) continue;
      canvas.drawPath(_pathOf(ring, close: true), land);
    }
  }

  void _strokeCoastline(Canvas canvas, _Bounds visible) {
    final paint = Paint()
      ..color = palette.coastline
      ..style = PaintingStyle.stroke
      ..strokeWidth = palette.coastlineWidth
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    for (final ring in basemap.coastline) {
      if (!ring.intersects(visible)) continue;
      canvas.drawPath(_pathOf(ring, close: true), paint);
    }
  }

  void _strokeRoads(
    Canvas canvas,
    List<BasemapWay> roads,
    _Bounds visible,
    Color color,
    double width,
  ) {
    // 한 Path에 모아 한 번에 그린다. 선마다 drawPath를 부르면 호출 비용이
    // 그림 비용보다 커진다.
    final path = Path();
    var any = false;
    for (final road in roads) {
      if (!road.intersects(visible)) continue;
      _addTo(path, road);
      any = true;
    }
    if (!any) return;

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
  }

  Path _pathOf(BasemapWay way, {bool close = false}) {
    final path = Path();
    _addTo(path, way);
    if (close) path.close();
    return path;
  }

  void _addTo(Path path, BasemapWay way) {
    final points = way.points;
    final first = projection.toPixel(_point(points[0], points[1]));
    path.moveTo(first.dx, first.dy);
    for (var i = 2; i < points.length; i += 2) {
      final p = projection.toPixel(_point(points[i], points[i + 1]));
      path.lineTo(p.dx, p.dy);
    }
  }

  /// 화면 안에 들어온 이름만, 서로 겹치지 않게 얹는다.
  void _drawLabels(Canvas canvas, Size size) {
    final candidates = <({Offset at, TextPainter text, BasemapLabel label})>[];

    for (final label in basemap.labels) {
      final p = projection.toPixel(_point(label.latitude, label.longitude));
      final at = Offset(p.dx, p.dy);
      // 화면 근처 것만 추린다. 536개를 모두 배치 계산할 이유가 없다.
      if (at.dx < -200 ||
          at.dx > size.width + 200 ||
          at.dy < -200 ||
          at.dy > size.height + 200) {
        continue;
      }
      candidates.add((at: at, text: _layoutLabel(label), label: label));
    }

    // 큰 지명(시 → 읍면 → 오름) 순으로 자리를 준다.
    candidates.sort((a, b) => a.label.kind.index.compareTo(b.label.kind.index));

    final placed = <Rect>[];
    for (final item in candidates) {
      if (placed.length >= _maxLabels) break;

      final spot = _findSpot(item.at, item.text, size, placed);
      if (spot == null) continue;

      placed.add(spot);
      // 점은 찍지 않는다. 지형 위의 점은 경로의 출발점과 헷갈린다.
      item.text.paint(canvas, spot.topLeft);
    }
  }

  /// 글자를 놓을 자리를 찾는다. 제자리가 막히면 조금씩 비켜 본다.
  ///
  /// 비켜 놓지 않으면, 오름을 빙 두르는 코스에서 경로가 이름을 전부 덮어
  /// 지도에 이름이 하나도 남지 않는다. 지도가 제 역할을 못 하는 셈이다.
  Rect? _findSpot(
    Offset at,
    TextPainter text,
    Size size,
    List<Rect> placed,
  ) {
    for (final offset in _labelOffsets) {
      final box = Rect.fromCenter(
        center: at + offset * text.height,
        width: text.width,
        height: text.height,
      );

      // 글자 상자가 통째로 들어오는 것만 놓는다. 좌표만 보고 걸렀더니
      // "동알오름"이 "동알오ᄅ"으로 잘려 나갔다.
      if (box.left < 12 ||
          box.right > size.width - 12 ||
          box.top < 10 ||
          box.bottom > size.height - 34) {
        continue;
      }
      if (_crossesRoute(box)) continue;
      if (placed.any((o) => o.inflate(_labelSpacing / 2).overlaps(box))) {
        continue;
      }
      return box;
    }
    return null;
  }

  /// 비켜 볼 자리. 글자 높이의 배수로 위·아래를 먼저 본다 — 좌우로 밀면
  /// 이름이 가리키는 지점에서 너무 멀어진다.
  static const List<Offset> _labelOffsets = [
    Offset.zero,
    Offset(0, -1.4),
    Offset(0, 1.4),
    Offset(0, -2.8),
    Offset(0, 2.8),
    Offset(-2.2, -1.4),
    Offset(2.2, -1.4),
    Offset(-2.2, 1.4),
    Offset(2.2, 1.4),
  ];

  /// 경로가 글자 상자를 지나가는지.
  bool _crossesRoute(Rect box) {
    if (route.isEmpty) return false;
    final area = box.inflate(_routeClearance);

    for (final point in route) {
      final p = projection.toPixel(point);
      if (area.contains(Offset(p.dx, p.dy))) return true;
    }
    return false;
  }

  TextPainter _layoutLabel(BasemapLabel label) {
    final isPeak = label.kind == BasemapLabelKind.peak;

    return TextPainter(
      text: TextSpan(
        text: label.name,
        style: TextStyle(
          color: palette.label,
          fontSize: isPeak ? palette.labelSize * 0.88 : palette.labelSize,
          fontWeight: isPeak ? FontWeight.w600 : FontWeight.w700,
          height: 1,
          // 지형 위에 바로 얹히므로 글자 뒤를 살짝 띄워 읽히게 한다.
          shadows: [
            Shadow(color: palette.labelHalo, blurRadius: 6),
            Shadow(color: palette.labelHalo, blurRadius: 12),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
  }

  static GeoPoint _point(double lat, double lng) =>
      GeoPoint(latitude: lat, longitude: lng);

  @override
  bool shouldRepaint(JejuBasemapPainter old) =>
      old.projection != projection ||
      old.palette != palette ||
      old.route != route ||
      !identical(old.basemap, basemap);
}

typedef _Bounds = ({
  double minLat,
  double minLng,
  double maxLat,
  double maxLng,
});

/// 지형을 어떤 색으로 그릴지. 카드 배색(다크/라이트)마다 다르다.
class BasemapPalette {
  const BasemapPalette({
    required this.sea,
    required this.land,
    required this.coastline,
    required this.majorRoad,
    required this.midRoad,
    required this.minorRoad,
    required this.label,
    required this.labelHalo,
    this.coastlineWidth = 3,
    this.majorRoadWidth = 7,
    this.midRoadWidth = 4,
    this.minorRoadWidth = 2,
    this.labelSize = 26,
  });

  final Color sea;
  final Color land;
  final Color coastline;

  /// 굵기 세 단계. 한 색으로 다 그리면 지도가 한 덩어리로 뭉쳐 보인다.
  final Color majorRoad;
  final Color midRoad;
  final Color minorRoad;

  final Color label;

  /// 글자 뒤에 깔아 지형에서 띄우는 색.
  final Color labelHalo;

  final double coastlineWidth;
  final double majorRoadWidth;
  final double midRoadWidth;
  final double minorRoadWidth;
  final double labelSize;

  @override
  bool operator ==(Object other) =>
      other is BasemapPalette &&
      other.sea == sea &&
      other.land == land &&
      other.coastline == coastline &&
      other.majorRoad == majorRoad &&
      other.midRoad == midRoad &&
      other.minorRoad == minorRoad &&
      other.label == label &&
      other.labelHalo == labelHalo;

  @override
  int get hashCode => Object.hash(
    sea,
    land,
    coastline,
    majorRoad,
    midRoad,
    minorRoad,
    label,
    labelHalo,
  );
}
