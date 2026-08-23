import 'package:flutter_test/flutter_test.dart';
import 'package:runners_jeju/models/running_course.dart';

void main() {
  Map<String, dynamic> baseJson() => {
    'id': 'c1',
    'name': '테스트 코스',
    'distance_km': 6,
    'difficulty': 2,
    'address': '제주',
    'path': const [],
  };

  group('RunningCourse.fromJson — parkings/restrooms', () {
    test('목록을 CourseFacility로 파싱한다', () {
      final course = RunningCourse.fromJson({
        ...baseJson(),
        'parkings': [
          {'name': '주차장A', 'address': '제주 A', 'lat': 33.5, 'lng': 126.5},
        ],
        'restrooms': [
          {'name': null, 'address': '제주 B', 'lat': 33.4, 'lng': 126.4},
          {'name': '화장실C', 'address': '제주 C', 'lat': 33.3, 'lng': 126.3},
        ],
      });

      expect(course.parkings, hasLength(1));
      expect(course.parkings.first.name, '주차장A');
      expect(course.parkings.first.lat, 33.5);

      expect(course.restrooms, hasLength(2));
      expect(course.restrooms.first.name, isNull);
      expect(course.restrooms.last.name, '화장실C');
    });

    test('필드가 없으면 빈 목록이다', () {
      final course = RunningCourse.fromJson(baseJson());

      expect(course.parkings, isEmpty);
      expect(course.restrooms, isEmpty);
    });
  });
}
