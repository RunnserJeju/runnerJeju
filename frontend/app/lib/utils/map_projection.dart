import 'dart:math' as math;

import '../models/geo_point.dart';
import 'geo_utils.dart';

/// 카카오 정적 지도 이미지 위에 좌표를 찍기 위한 투영.
///
/// 지도 이미지는 서버(`GET /maps/static`)가 중심 좌표와 줌 레벨로 받아 온다.
/// 그 위에 경로를 그리려면 앱이 **같은 기준**으로 좌표를 픽셀로 옮겨야 한다.
/// 이 클래스가 그 기준 하나를 들고 있다.
///
/// 축척은 추측하지 않고 실측했다. 같은 레벨에서 중심을 정확히 2km 옮긴 두
/// 이미지의 픽셀 이동량을 재 보면 lv5=4.000, lv6=8.000, lv7=16.000 m/px로
/// 정확히 2배씩 떨어진다. 즉 해상도는 `2^(level-3)` m/px다.
class MapProjection {
  const MapProjection({
    required this.center,
    required this.level,
    required this.size,
  });

  /// 지도 이미지의 중심 좌표.
  final GeoPoint center;

  /// 카카오 줌 레벨. 작을수록 확대된다.
  final int level;

  /// 지도 이미지가 놓일 영역의 크기(논리 픽셀).
  final ({double width, double height}) size;

  /// 카카오가 받는 줌 레벨의 범위.
  static const int minLevel = 1;
  static const int maxLevel = 15;

  /// 경로가 지도 가장자리에 닿지 않도록 각 변에서 빼 두는 여유(px).
  static const double _padding = 40;

  /// 레벨당 해상도(m/px).
  static double metersPerPixel(int level) => math.pow(2, level - 3).toDouble();

  /// 위도 [lat]에서 경도 1도의 실제 거리(m).
  ///
  /// 지구를 완전한 구로 보고 `111320*cos(lat)`로 계산하면 제주 위도에서 수십 m
  /// 어긋난다. 6km 경로를 900px에 담으면 몇 px 차이라 지도와 경로가 나란히
  /// 놓였을 때 눈에 띈다. 그래서 타원체 보정을 쓴다.
  static double metersPerLongitudeDegree(double lat) {
    final phi = lat * math.pi / 180;
    return 111412.84 * math.cos(phi) - 93.5 * math.cos(3 * phi);
  }

  /// 위도 1도의 실제 거리(m).
  static double metersPerLatitudeDegree(double lat) {
    final phi = lat * math.pi / 180;
    return 111132.92 -
        559.82 * math.cos(2 * phi) +
        1.175 * math.cos(4 * phi);
  }

  /// [path]가 [width]×[height] 안에 다 들어가는 가장 확대된 레벨.
  ///
  /// 레벨은 정수라 경로가 영역을 꽉 채우지는 않는다. 억지로 맞추려고 이미지를
  /// 늘리면 지도가 왜곡되므로, 한 단계 축소된 채로 여백을 두는 쪽을 택한다.
  static int levelToFit(
    List<GeoPoint> path, {
    required double width,
    required double height,
  }) {
    final bounds = GeoUtils.boundsOf(path);
    if (bounds == null) return 5;

    final centerLat =
        (bounds.southWest.latitude + bounds.northEast.latitude) / 2;

    final spanMetersX =
        (bounds.northEast.longitude - bounds.southWest.longitude) *
        metersPerLongitudeDegree(centerLat);
    final spanMetersY =
        (bounds.northEast.latitude - bounds.southWest.latitude) *
        metersPerLatitudeDegree(centerLat);

    final usableWidth = math.max(width - _padding * 2, 1.0);
    final usableHeight = math.max(height - _padding * 2, 1.0);

    // 가로·세로 모두 담으려면 더 큰 쪽이 요구하는 해상도를 따라야 한다.
    final needed = math.max(
      spanMetersX / usableWidth,
      spanMetersY / usableHeight,
    );

    // 한 점에 머문 기록은 요구 해상도가 0이라 가장 확대된 레벨이 된다. 그러면
    // 건물 하나만 크게 나와 어디인지 알 수 없으므로 동네가 보이는 선에서 멈춘다.
    if (needed <= 0) return 4;

    // 2^(level-3) >= needed 를 만족하는 가장 작은 정수 level.
    final level = (math.log(needed) / math.ln2).ceil() + 3;
    return level.clamp(minLevel, maxLevel);
  }

  /// [path] 전체를 담는 지도의 투영을 만든다.
  factory MapProjection.fit(
    List<GeoPoint> path, {
    required double width,
    required double height,
  }) {
    final center = GeoUtils.centerOf(path);
    return MapProjection(
      center: center ?? const GeoPoint(latitude: 33.4996, longitude: 126.5312),
      level: levelToFit(path, width: width, height: height),
      size: (width: width, height: height),
    );
  }

  /// 좌표를 이미지 안의 픽셀 위치로 옮긴다. 중심이 이미지 한가운데다.
  ({double dx, double dy}) toPixel(GeoPoint point) {
    final resolution = metersPerPixel(level);
    final lat = center.latitude;

    final eastMeters = (point.longitude - center.longitude) *
        metersPerLongitudeDegree(lat);
    final northMeters =
        (point.latitude - center.latitude) * metersPerLatitudeDegree(lat);

    return (
      dx: size.width / 2 + eastMeters / resolution,
      // 화면 y는 아래로 자라고 북쪽은 위다.
      dy: size.height / 2 - northMeters / resolution,
    );
  }

  /// 이 화면이 덮는 위경도 범위.
  ///
  /// 투영이 선형이라 네 귀퉁이만 되돌리면 된다. 지형을 그릴 때 이 범위로
  /// 먼저 걸러 내면, 화면 밖 선을 좌표 변환하지 않아도 된다.
  ///
  /// [marginPixels]만큼 넓혀서 돌려준다 — 가장자리에 걸친 선이 잘려 보이지
  /// 않도록 조금 여유를 둔다.
  ({double minLat, double minLng, double maxLat, double maxLng}) visibleBounds({
    double marginPixels = 40,
  }) {
    final resolution = metersPerPixel(level);
    final halfWidthMeters = (size.width / 2 + marginPixels) * resolution;
    final halfHeightMeters = (size.height / 2 + marginPixels) * resolution;

    final dLat = halfHeightMeters / metersPerLatitudeDegree(center.latitude);
    final dLng = halfWidthMeters / metersPerLongitudeDegree(center.latitude);

    return (
      minLat: center.latitude - dLat,
      minLng: center.longitude - dLng,
      maxLat: center.latitude + dLat,
      maxLng: center.longitude + dLng,
    );
  }

  /// 같은 투영이면 다시 그릴 필요가 없다([CustomPainter.shouldRepaint]).
  @override
  bool operator ==(Object other) =>
      other is MapProjection &&
      other.level == level &&
      other.center.latitude == center.latitude &&
      other.center.longitude == center.longitude &&
      other.size == size;

  @override
  int get hashCode =>
      Object.hash(level, center.latitude, center.longitude, size);
}
