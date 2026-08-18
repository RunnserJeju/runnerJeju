import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runners_jeju/models/geo_point.dart';
import 'package:runners_jeju/models/run_record.dart';
import 'package:runners_jeju/screens/run/run_detail_screen.dart';

/// 마이페이지에서 넘어오는 러닝 상세 화면이 넘겨받은 기록의 요약 정보를
/// 그대로 보여주는지 확인한다. 지도(RunMapView)는 네이티브 뷰라 렌더 여부만 보고
/// 내용 검증은 하지 않는다.
void main() {
  // 5km를 30분(1800초)에 달린 코스 러닝. 페이스 6'00"/km, 속도 10.0km/h.
  final record = RunRecord(
    id: 'run-1',
    courseId: 'course-1',
    courseName: '제주 올레 1코스',
    startedAt: DateTime(2026, 8, 17, 9, 30),
    endedAt: DateTime(2026, 8, 17, 10, 0),
    distanceMeters: 5000,
    duration: const Duration(minutes: 30),
    path: const [
      GeoPoint(latitude: 33.50, longitude: 126.53),
      GeoPoint(latitude: 33.51, longitude: 126.54),
    ],
  );

  testWidgets('상세 화면이 코스명과 러닝 요약 지표를 보여준다', (tester) async {
    await tester.pumpWidget(MaterialApp(home: RunDetailScreen(record: record)));

    // 코스명은 AppBar 제목으로 노출된다.
    expect(find.text('제주 올레 1코스'), findsOneWidget);

    // 거리 5.00km, 시간 30:00, 속도 10.0km/h.
    expect(find.text('5.00'), findsOneWidget);
    expect(find.text('30:00'), findsOneWidget);
    expect(find.text('10.0'), findsOneWidget);

    // 페이스 6'00"/km (Formatters.pace 형식).
    expect(find.textContaining("6'00"), findsOneWidget);
  });

  testWidgets('자유 러닝은 제목이 "자유 러닝"으로 표시된다', (tester) async {
    final freeRun = RunRecord(
      startedAt: DateTime(2026, 8, 17, 9, 30),
      endedAt: DateTime(2026, 8, 17, 10, 0),
      distanceMeters: 3000,
      duration: const Duration(minutes: 20),
      path: const [GeoPoint(latitude: 33.50, longitude: 126.53)],
    );

    await tester.pumpWidget(
      MaterialApp(home: RunDetailScreen(record: freeRun)),
    );

    expect(find.text('자유 러닝'), findsOneWidget);
  });
}
