import 'package:flutter_test/flutter_test.dart';
import 'package:runners_jeju/models/geo_point.dart';
import 'package:runners_jeju/models/run_record.dart';
import 'package:runners_jeju/utils/continuation_window.dart';

void main() {
  final base = RunRecord(
    id: 'run-1',
    courseId: 'course-1',
    courseName: '성산 해안 코스',
    startedAt: DateTime.utc(2026, 11, 7, 0),
    endedAt: DateTime.utc(2026, 11, 7, 0, 30),
    distanceMeters: 3000,
    duration: const Duration(minutes: 30),
    path: const [
      GeoPoint(latitude: 33.0, longitude: 126.0),
      GeoPoint(latitude: 33.001, longitude: 126.0),
    ],
  );

  final segment = RunRecord(
    courseId: 'course-1',
    startedAt: DateTime.utc(2026, 11, 8, 0),
    endedAt: DateTime.utc(2026, 11, 8, 0, 20),
    distanceMeters: 2000,
    duration: const Duration(minutes: 20),
    path: const [
      GeoPoint(latitude: 33.01, longitude: 126.01),
      GeoPoint(latitude: 33.011, longitude: 126.01),
    ],
    continuesRunId: 'run-1',
    segmentId: 'seg-1',
  );

  group('RunRecord.continued', () {
    final merged = RunRecord.continued(base, segment);

    test('거리·시간을 더하고 시작은 원래 기록, 끝은 이어 달린 끝', () {
      expect(merged.id, 'run-1');
      expect(merged.distanceMeters, 5000);
      expect(merged.duration, const Duration(minutes: 50));
      expect(merged.startedAt, base.startedAt);
      expect(merged.endedAt, segment.endedAt);
    });

    test('이어 달린 첫 점에서 경로를 끊는다', () {
      expect(merged.path, hasLength(4));
      expect(merged.path[1].startsNewSegment, isFalse);
      expect(merged.path[2].startsNewSegment, isTrue);
      expect(merged.path[3].startsNewSegment, isFalse);
    });
  });

  test('이어달리기 업로드는 구간 id를 싣고 코스는 싣지 않는다', () {
    final json = segment.toContinueJson();
    expect(json['segment_id'], 'seg-1');
    expect(json.containsKey('course_id'), isFalse);
    expect(json['distance_meters'], 2000);
    expect(json['duration_sec'], 1200);
  });

  test('따로 저장할 때는 이어달리기 표시를 뗀다', () {
    final standalone = segment.asStandalone();
    expect(standalone.isContinuation, isFalse);
    expect(standalone.segmentId, isNull);
    expect(standalone.toJson()['course_id'], 'course-1');
  });

  group('ContinuationWindow (KST, 시작한 날 포함 7일)', () {
    // 2026-11-01 09:00 KST
    final startedAt = DateTime.utc(2026, 11, 1, 0);

    test('7일째 되는 날이 마지막 날', () {
      expect(ContinuationWindow.lastDay(startedAt), DateTime.utc(2026, 11, 7));
    });

    test('마지막 날 밤까지는 열려 있고 다음 날 KST 자정에 닫힌다', () {
      // 11/7 23:59 KST = 11/7 14:59 UTC
      final lastMinute = DateTime.utc(2026, 11, 7, 14, 59);
      expect(ContinuationWindow.daysLeft(startedAt, now: lastMinute), 0);
      expect(ContinuationWindow.isOpen(startedAt, now: lastMinute), isTrue);

      // 11/8 00:00 KST = 11/7 15:00 UTC
      final nextDay = DateTime.utc(2026, 11, 7, 15);
      expect(ContinuationWindow.isOpen(startedAt, now: nextDay), isFalse);
    });

    test('기기 시간대가 아니라 KST 날짜로 센다', () {
      // 10/31 23:30 UTC는 KST로 11/1 08:30 — 11/1에 시작한 기록이다.
      final lateUtc = DateTime.utc(2026, 10, 31, 23, 30);
      expect(ContinuationWindow.lastDay(lateUtc), DateTime.utc(2026, 11, 7));
    });
  });
}
