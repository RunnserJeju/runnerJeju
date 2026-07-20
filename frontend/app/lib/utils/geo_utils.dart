import 'dart:math' as math;

import '../models/geo_point.dart';

/// 위경도 계산 유틸. 서버와 무관하게 단말에서 거리/진행률을 계산할 때 쓴다.
class GeoUtils {
  const GeoUtils._();

  static const double _earthRadiusMeters = 6371000;

  /// 두 지점 사이의 대원 거리(m).
  static double distanceBetween(GeoPoint a, GeoPoint b) {
    final dLat = _toRadians(b.latitude - a.latitude);
    final dLng = _toRadians(b.longitude - a.longitude);
    final lat1 = _toRadians(a.latitude);
    final lat2 = _toRadians(b.latitude);

    final h =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.sin(dLng / 2) * math.sin(dLng / 2) * math.cos(lat1) * math.cos(lat2);

    return 2 * _earthRadiusMeters * math.asin(math.min(1, math.sqrt(h)));
  }

  /// 경로 전체 길이(m).
  static double pathLength(List<GeoPoint> path) {
    var total = 0.0;
    for (var i = 1; i < path.length; i++) {
      total += distanceBetween(path[i - 1], path[i]);
    }
    return total;
  }

  /// 경로를 모두 담는 사각형 범위. 비어 있으면 null.
  static ({GeoPoint southWest, GeoPoint northEast})? boundsOf(
    List<GeoPoint> path,
  ) {
    if (path.isEmpty) return null;

    var minLat = path.first.latitude;
    var maxLat = path.first.latitude;
    var minLng = path.first.longitude;
    var maxLng = path.first.longitude;

    for (final p in path) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }

    return (
      southWest: GeoPoint(latitude: minLat, longitude: minLng),
      northEast: GeoPoint(latitude: maxLat, longitude: maxLng),
    );
  }

  /// 경로의 중심점. 비어 있으면 null.
  static GeoPoint? centerOf(List<GeoPoint> path) {
    final bounds = boundsOf(path);
    if (bounds == null) return null;

    return GeoPoint(
      latitude: (bounds.southWest.latitude + bounds.northEast.latitude) / 2,
      longitude: (bounds.southWest.longitude + bounds.northEast.longitude) / 2,
    );
  }

  /// [point]에서 [path] 위의 가장 가까운 지점까지의 거리(m). path가 비면 null.
  static double? distanceToPath(GeoPoint point, List<GeoPoint> path) {
    if (path.isEmpty) return null;

    var nearest = double.infinity;
    for (final p in path) {
      nearest = math.min(nearest, distanceBetween(point, p));
    }
    return nearest;
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180;
}
