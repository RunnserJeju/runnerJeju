import 'package:runners_jeju/models/geo_point.dart';
import 'package:runners_jeju/utils/course_coverage.dart';
import 'package:flutter_test/flutter_test.dart';

/// 서버 tests/test_verification.py의 기하 시나리오를 그대로 이식한 테스트.
/// 직선 합성 코스라 비례 관계를 정확히 검증할 수 있다.

// 위도 방향 미터 → 도 변환. 서버 테스트와 같은 값.
const latPerMeter = 1 / 111132.0;

// 위도 33.2도에서 경도 1도 ≈ 93,160m.
const lngPerMeterAt33 = 1 / 93160.0;

/// 정북 방향 3km 직선, 15m 간격 201점(서버 straight 픽스처와 동일).
List<GeoPoint> straightCourse() => [
  for (var i = 0; i < 201; i++)
    GeoPoint(latitude: 33.20 + i * 15 * latPerMeter, longitude: 126.30),
];

List<GeoPoint> shiftEast(List<GeoPoint> path, double meters) => [
  for (final p in path)
    GeoPoint(latitude: p.latitude, longitude: p.longitude + meters * lngPerMeterAt33),
];

double coverageOf(List<GeoPoint> course, List<GeoPoint> run) {
  final tracker = CourseCoverageTracker(course);
  for (final p in run) {
    tracker.add(p);
  }
  return tracker.ratio;
}

void main() {
  group('CourseCoverageTracker 기하', () {
    test('코스를 그대로 달리면 100%', () {
      final course = straightCourse();
      expect(coverageOf(course, course), 1.0);
    });

    test('절반만 달리면 ~50% (점 개수 비율 = 거리 비율)', () {
      final course = straightCourse();
      final half = course.sublist(0, course.length ~/ 2);
      expect(coverageOf(course, half), closeTo(0.5, 0.05));
    });

    test('20m 옆 평행 주행은 tolerance(30m) 안이라 100%', () {
      final course = straightCourse();
      expect(coverageOf(course, shiftEast(course, 20)), 1.0);
    });

    test('50m 옆 평행 주행은 tolerance 밖이라 0%', () {
      final course = straightCourse();
      expect(coverageOf(course, shiftEast(course, 50)), 0.0);
    });

    test('GPS 기록이 뜸해도(75m 간격) 선분이 커버한다', () {
      final course = straightCourse();
      final sparse = [for (var i = 0; i < course.length; i += 5) course[i]];
      expect(coverageOf(course, sparse), closeTo(1.0, 0.01));
    });

    test('역주행도 같은 커버리지', () {
      final course = straightCourse();
      expect(coverageOf(course, course.reversed.toList()), 1.0);
    });

    test('점 하나뿐이면 그 주변만 커버', () {
      final course = straightCourse();
      final ratio = coverageOf(course, [course.first]);
      expect(ratio, greaterThan(0));
      expect(ratio, lessThan(0.05));
    });

    test('빈 코스는 0', () {
      expect(coverageOf([], straightCourse()), 0.0);
    });
  });

  group('증분 계산', () {
    test('점을 하나씩 넣어도 비율은 줄지 않는다', () {
      final course = straightCourse();
      final tracker = CourseCoverageTracker(course);

      var previous = 0.0;
      for (final p in course) {
        tracker.add(p);
        expect(tracker.ratio, greaterThanOrEqualTo(previous));
        previous = tracker.ratio;
      }
      expect(tracker.ratio, 1.0);
    });

    test('트래커 인스턴스끼리 상태가 섞이지 않는다', () {
      final course = straightCourse();
      // 다른 기준점을 가진 코스를 먼저 만들어도,
      final other = CourseCoverageTracker(shiftEast(course, 5000));
      final tracker = CourseCoverageTracker(course);

      for (final p in course) {
        tracker.add(p);
      }

      expect(tracker.ratio, 1.0);
      expect(other.ratio, 0.0);
    });
  });
}
