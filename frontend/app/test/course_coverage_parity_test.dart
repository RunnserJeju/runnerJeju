import 'dart:convert';
import 'dart:io';

import 'package:runners_jeju/models/geo_point.dart';
import 'package:runners_jeju/utils/course_coverage.dart';
import 'package:flutter_test/flutter_test.dart';

/// 서버-클라이언트 커버리지 패리티 테스트.
///
/// 서버가 자기 구현으로 계산해 저장한 픽스처(server/tests/fixtures/coverage_parity.json)를
/// 읽어, Dart 증분 구현이 같은 입력에서 같은 비율을 내는지 확인한다. 두 구현은
/// 의도적으로 중복이라(서버는 일괄, 클라는 실시간 증분) 이 테스트가 어긋남을 잡는
/// 유일한 자동 장치다. 서버 쪽 가드는 server/tests/test_coverage_parity.py.
void main() {
  final fixtureFile = File('../../server/tests/fixtures/coverage_parity.json');

  test('서버 픽스처의 모든 케이스에서 같은 비율이 나온다', () {
    expect(
      fixtureFile.existsSync(),
      isTrue,
      reason: '픽스처가 없으면 server/tests/test_coverage_parity.py의 생성 안내를 따른다',
    );

    final fixture = jsonDecode(fixtureFile.readAsStringSync()) as Map<String, dynamic>;
    final tolerance = (fixture['tolerance_meters'] as num).toDouble();
    final course = [
      for (final p in fixture['course'] as List)
        GeoPoint(latitude: (p[0] as num).toDouble(), longitude: (p[1] as num).toDouble()),
    ];

    for (final rawCase in fixture['cases'] as List) {
      final c = rawCase as Map<String, dynamic>;
      final tracker = CourseCoverageTracker(course, toleranceMeters: tolerance);

      for (final p in c['run'] as List) {
        tracker.add(
          GeoPoint(latitude: (p[0] as num).toDouble(), longitude: (p[1] as num).toDouble()),
        );
      }

      expect(
        tracker.ratio,
        closeTo((c['expected_ratio'] as num).toDouble(), 1e-9),
        reason: '케이스 ${c['name']}에서 서버와 어긋남',
      );
    }
  });
}
