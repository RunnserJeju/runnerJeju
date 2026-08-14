import 'dart:math' as math;

import '../models/geo_point.dart';

/// 러닝 중 실시간 코스 커버리지(코스 점 중 지나간 비율).
///
/// 서버 `verification.coverage_ratio`와 **같은 판정**을 증분으로 계산한다 —
/// 지역 평면 투영, 점-대-선분 거리, tolerance 30m까지 동일하다. 러닝 중 화면의
/// %와 서버의 최종 match_rate가 같은 개념이어야 "뛸 때는 90%였는데 결과는
/// 70%"라는 혼란이 없다. 두 구현이 어긋나지 않는지는 서버와 같은 픽스처를 읽는
/// 패리티 테스트(test/course_coverage_parity_test.dart)가 지킨다.
///
/// 증분 계산 방식: 코스 점을 시작 시 한 번 투영해 두고, GPS 점이 올 때마다
/// "직전 점 → 새 점" 선분 하나에 대해 아직 안 커버된 코스 점만 검사한다.
/// 선분들의 합집합은 경로 전체와 같으므로 서버가 완성된 경로로 계산한 값과
/// 일치한다. 갱신 1회당 수십 µs 수준이라 러닝 중 부하는 무시할 수 있다.
class CourseCoverageTracker {
  CourseCoverageTracker(
    List<GeoPoint> coursePath, {
    this.toleranceMeters = 30,
  }) : _refLat = coursePath.isEmpty ? 0 : coursePath.first.latitude,
       _refLng = coursePath.isEmpty ? 0 : coursePath.first.longitude,
       _covered = List.filled(coursePath.length, false) {
    // 서버 _to_local_xy와 같은 공식: 위도 1도 ≈ 111,132m, 경도는 cos(위도)만큼 축소.
    _mPerDegLng = 111320.0 * math.cos(_refLat * math.pi / 180);
    _course = [for (final p in coursePath) _toXy(p)];
  }

  /// 코스 점이 "지나간 것"으로 인정되는 반경(m).
  /// 서버 verification.DEFAULT_TOLERANCE_METERS와 같아야 한다.
  final double toleranceMeters;

  static const double _mPerDegLat = 111132.0;

  final double _refLat;
  final double _refLng;
  late final double _mPerDegLng;
  late final List<({double x, double y})> _course;

  final List<bool> _covered;
  int _coveredCount = 0;

  ({double x, double y})? _last;

  ({double x, double y}) _toXy(GeoPoint p) => (
    x: (p.longitude - _refLng) * _mPerDegLng,
    y: (p.latitude - _refLat) * _mPerDegLat,
  );

  /// 커버된 코스 점의 비율 (0.0 ~ 1.0). 코스가 비어 있으면 0.
  double get ratio => _course.isEmpty ? 0 : _coveredCount / _course.length;

  /// GPS 점 하나를 반영한다. RunTracker가 경로에 점을 추가할 때마다 부른다.
  ///
  /// [GeoPoint.startsNewSegment]가 붙은 점(일시정지에서 재개한 첫 점)은 직전 점과
  /// **잇지 않는다.** 일시정지 동안 이동한 구간은 달린 것이 아니므로 그 사이를
  /// 선분으로 이으면 지나가지도 않은 코스 점이 커버된 것으로 잡힌다. 서버도
  /// 같은 표시를 보고 같은 자리에서 끊으므로(verification.to_segments) 실시간
  /// %와 최종 match_rate는 여전히 같은 값이다.
  void add(GeoPoint point) {
    if (_course.isEmpty) return;

    final p = _toXy(point);
    final prev = point.startsNewSegment ? null : _last;
    _last = p;

    final tolSq = toleranceMeters * toleranceMeters;

    for (var i = 0; i < _course.length; i++) {
      if (_covered[i]) continue;

      final c = _course[i];
      final distSq = prev == null
          ? _pointDistSq(c, p)
          : _segmentDistSq(c, prev, p);

      if (distSq <= tolSq) {
        _covered[i] = true;
        _coveredCount++;
      }
    }
  }

  static double _pointDistSq(({double x, double y}) c, ({double x, double y}) p) {
    final dx = c.x - p.x;
    final dy = c.y - p.y;
    return dx * dx + dy * dy;
  }

  /// 점 c에서 선분 [a, b]까지 거리의 제곱. 서버 _near_polyline과 같은 계산.
  static double _segmentDistSq(
    ({double x, double y}) c,
    ({double x, double y}) a,
    ({double x, double y}) b,
  ) {
    final ex = b.x - a.x;
    final ey = b.y - a.y;
    final dx = c.x - a.x;
    final dy = c.y - a.y;

    final segLenSq = ex * ex + ey * ey;
    final t = segLenSq == 0
        ? 0.0
        : ((dx * ex + dy * ey) / segLenSq).clamp(0.0, 1.0);

    final nx = dx - t * ex;
    final ny = dy - t * ey;
    return nx * nx + ny * ny;
  }
}
