import 'package:flutter_test/flutter_test.dart';
import 'package:runners_jeju/models/geo_point.dart';
import 'package:runners_jeju/models/running_course.dart';

void main() {
  const a = GeoPoint(latitude: 33.10, longitude: 126.10, altitude: 5);
  const b = GeoPoint(latitude: 33.20, longitude: 126.20, altitude: 15);
  const c = GeoPoint(latitude: 33.30, longitude: 126.30, altitude: 30);

  RunningCourse course({List<GeoPoint> path = const [a, b, c]}) =>
      RunningCourse(
        id: 'c1',
        name: '테스트 코스',
        distanceKm: 6,
        address: '제주',
        path: path,
        startPoint: path.isEmpty ? null : path.first,
        completedCount: 3,
      );

  group('RunningCourse.reversed', () {
    test('경로를 거꾸로 뒤집고 시작점을 새 첫 점으로 옮긴다', () {
      final reversed = course().reversed();

      expect(reversed.path, [c, b, a]);
      expect(reversed.startPoint, c);
      // 고도는 점에 붙어 있어 함께 뒤집힌다.
      expect(reversed.path.map((p) => p.altitude), [30, 15, 5]);
    });

    test('경로 밖의 정보는 그대로 둔다', () {
      final reversed = course().reversed();

      expect(reversed.id, 'c1');
      expect(reversed.name, '테스트 코스');
      expect(reversed.address, '제주');
      expect(reversed.completedCount, 3);
    });

    test('두 번 뒤집으면 원래 방향이다', () {
      final original = course();

      final twice = original.reversed().reversed();

      expect(twice.path, original.path);
      expect(twice.startPoint, original.startPoint);
    });

    test('경로가 없으면 시작점을 건드리지 않는다', () {
      const listItem = RunningCourse(
        id: 'c1',
        name: '목록 코스',
        distanceKm: 6,
        address: '제주',
        path: [],
        startPoint: a,
      );

      final reversed = listItem.reversed();

      expect(reversed.path, isEmpty);
      expect(reversed.startPoint, a);
    });
  });
}
