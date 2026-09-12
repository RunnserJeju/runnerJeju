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
        math.sin(dLng / 2) *
            math.sin(dLng / 2) *
            math.cos(lat1) *
            math.cos(lat2);

    return 2 * _earthRadiusMeters * math.asin(math.min(1, math.sqrt(h)));
  }

  /// 경로에서 [toleranceMeters] 안쪽의 잔 꼭짓점을 걷어낸다(Douglas–Peucker).
  ///
  /// GPS로 딴 코스는 직선 도로에서도 몇 m씩 흔들리는 점이 촘촘히 찍혀 있어,
  /// 그대로 그리면 사실상 모든 구간이 잘게 꺾인 선이 된다. 그림용으로만 쓴다 —
  /// 거리·진행률 계산은 원본 경로를 본다.
  static List<GeoPoint> simplify(List<GeoPoint> path, double toleranceMeters) {
    if (path.length < 3) return path;

    // 좁은 지역이라 위경도를 m 단위 평면으로 펴서 점-선분 거리를 잰다.
    final lat0 = _toRadians(path.first.latitude);
    final cosLat = math.cos(lat0);
    double x(GeoPoint p) =>
        _toRadians(p.longitude) * cosLat * _earthRadiusMeters;
    double y(GeoPoint p) => _toRadians(p.latitude) * _earthRadiusMeters;

    double distToSegment(GeoPoint p, GeoPoint a, GeoPoint b) {
      final ax = x(a), ay = y(a), bx = x(b), by = y(b), px = x(p), py = y(p);
      final dx = bx - ax, dy = by - ay;
      final lenSq = dx * dx + dy * dy;
      var t = lenSq == 0 ? 0.0 : ((px - ax) * dx + (py - ay) * dy) / lenSq;
      t = t.clamp(0.0, 1.0);
      final cx = ax + t * dx, cy = ay + t * dy;
      return math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
    }

    final keep = List<bool>.filled(path.length, false);
    keep[0] = true;
    keep[path.length - 1] = true;
    final stack = <(int, int)>[(0, path.length - 1)];
    while (stack.isNotEmpty) {
      final (start, end) = stack.removeLast();
      var farthest = 0.0;
      var index = -1;
      for (var i = start + 1; i < end; i++) {
        final d = distToSegment(path[i], path[start], path[end]);
        if (d > farthest) {
          farthest = d;
          index = i;
        }
      }
      if (index != -1 && farthest > toleranceMeters) {
        keep[index] = true;
        stack.add((start, index));
        stack.add((index, end));
      }
    }
    return [
      for (var i = 0; i < path.length; i++)
        if (keep[i]) path[i],
    ];
  }

  /// [a]에서 [b]를 바라보는 방위각(도, 북쪽 0, 시계방향).
  static double bearing(GeoPoint a, GeoPoint b) {
    final lat1 = _toRadians(a.latitude);
    final lat2 = _toRadians(b.latitude);
    final dLng = _toRadians(b.longitude - a.longitude);
    final y = math.sin(dLng) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  /// 진행 방향이 [thresholdDegrees]보다 크게 꺾이는 꼭짓점마다 경로를 자른다.
  /// 꼭짓점은 앞 조각의 끝이자 뒤 조각의 시작으로 양쪽에 다 들어간다.
  ///
  /// 지도 SDK의 선 패턴(화살표)은 조각(segment) 단위로 처음부터 다시 놓이므로,
  /// 크게 꺾이는 곳에서 조각을 나누면 화살표가 그 꼭짓점을 걸치지 않는다.
  static List<List<GeoPoint>> splitAtBends(
    List<GeoPoint> path,
    double thresholdDegrees,
  ) {
    if (path.length < 3) return [path];

    final pieces = <List<GeoPoint>>[];
    var start = 0;
    var previous = bearing(path[0], path[1]);
    for (var i = 1; i < path.length - 1; i++) {
      final next = bearing(path[i], path[i + 1]);
      var turn = (next - previous).abs();
      if (turn > 180) turn = 360 - turn;
      previous = next;
      if (turn > thresholdDegrees) {
        pieces.add(path.sublist(start, i + 1));
        start = i;
      }
    }
    pieces.add(path.sublist(start));
    return pieces;
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
  static ({GeoPoint southWest, GeoPoint northEast})? _boundsOf(
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
    final bounds = _boundsOf(path);
    if (bounds == null) return null;

    return GeoPoint(
      latitude: (bounds.southWest.latitude + bounds.northEast.latitude) / 2,
      longitude: (bounds.southWest.longitude + bounds.northEast.longitude) / 2,
    );
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180;
}
