import '../network/json.dart';
import 'geo_point.dart';

/// 완료된 러닝 1회의 기록.
///
/// 이어달리기 구간이면 [continuesRunId]가 붙는다. 그때 이 기록은 원래 기록 뒤에
/// 붙일 **구간 하나**(거리·시간·경로 모두 이번에 달린 것만)이고, 서버가 합친다.
class RunRecord {
  const RunRecord({
    required this.startedAt,
    required this.endedAt,
    required this.distanceMeters,
    required this.duration,
    required this.path,
    this.id,
    this.courseId,
    this.courseName,
    this.completed = false,
    this.matchRate,
    this.continuesRunId,
    this.segmentId,
  });

  final String? id;

  /// 코스를 따라 달린 경우 그 코스 id. 자유 러닝이면 null.
  final String? courseId;
  final String? courseName;

  final DateTime startedAt;
  final DateTime endedAt;
  final double distanceMeters;
  final Duration duration;
  final List<GeoPoint> path;

  /// 이 러닝으로 코스 완주 인증이 통과했는지. 서버가 채운다.
  final bool completed;

  /// 코스 경로 일치율(0~1). 이어달리기 목록에서만 서버가 채운다.
  final double? matchRate;

  /// 이어달리기 구간이면 이어 붙일 원래 기록의 id.
  final String? continuesRunId;

  /// 이어달리기 구간의 id. 업로드를 재시도해도 서버가 같은 구간을 두 번 붙이지 않는다.
  final String? segmentId;

  bool get isCourseRun => courseId != null;
  bool get isContinuation => continuesRunId != null;

  /// 이 거리 이하로 끝낸 러닝은 저장하지 않는다(m). 시작하자마자 끈 것이다.
  /// 이어달리기 구간도 같다 — 그때는 원래 기록을 건드리지 않는다.
  static const double minMeters = 10;
  bool get isTooShort => distanceMeters <= minMeters;

  /// km당 초. 거리가 0이면 null.
  double? get paceSecondsPerKm {
    if (distanceMeters <= 0) return null;
    return duration.inSeconds / (distanceMeters / 1000);
  }

  /// 시속(km/h). 시간이 0이면 null.
  double? get speedKmh {
    if (duration.inSeconds <= 0) return null;
    return (distanceMeters / 1000) / (duration.inSeconds / 3600);
  }

  /// [base] 뒤에 이어달리기 구간 [segment]를 붙인 모습. 서버가 합치는 규칙과 같다
  /// (run_continuation.append_segment) — 업로드 응답을 받기 전에 결과 화면에 쓴다.
  static RunRecord continued(RunRecord base, RunRecord segment) => RunRecord(
    id: base.id,
    courseId: base.courseId,
    courseName: base.courseName,
    startedAt: base.startedAt,
    endedAt: segment.endedAt.isAfter(base.endedAt)
        ? segment.endedAt
        : base.endedAt,
    distanceMeters: base.distanceMeters + segment.distanceMeters,
    duration: base.duration + segment.duration,
    path: [
      ...base.path,
      // 원래 기록 끝 → 이어 달린 첫 점은 잇지 않는다.
      for (final (i, point) in segment.path.indexed)
        i == 0 ? point.asSegmentStart() : point,
    ],
  );

  /// 이어 붙일 원래 기록이 사라졌거나 이미 완주된 경우, 구간을 따로 저장하려고 쓴다.
  RunRecord asStandalone() => RunRecord(
    courseId: courseId,
    courseName: courseName,
    startedAt: startedAt,
    endedAt: endedAt,
    distanceMeters: distanceMeters,
    duration: duration,
    path: path,
  );

  factory RunRecord.fromJson(Map<String, dynamic> json) => RunRecord(
    id: json['id']?.toString(),
    courseId: json['course_id']?.toString(),
    courseName: json['course_name'] as String?,
    startedAt: DateTime.parse(json['started_at'] as String),
    endedAt: DateTime.parse(json['ended_at'] as String),
    distanceMeters: (json['distance_meters'] as num).toDouble(),
    duration: Duration(seconds: (json['duration_sec'] as num).toInt()),
    path: parseList(json['path'], GeoPoint.fromJson),
    completed: json['completed'] as bool? ?? false,
    matchRate: (json['match_rate'] as num?)?.toDouble(),
  );

  Map<String, dynamic> toJson() => {
    if (courseId != null) 'course_id': courseId,
    // 서버에는 항상 UTC로 보낸다. 로컬 시각을 그대로 보내면 오프셋이 빠져서
    // 서버가 UTC로 오해한다. 표시할 때 Formatters가 toLocal()로 되돌린다.
    'started_at': startedAt.toUtc().toIso8601String(),
    'ended_at': endedAt.toUtc().toIso8601String(),
    'distance_meters': distanceMeters,
    'duration_sec': duration.inSeconds,
    'path': path.map((e) => e.toJson()).toList(),
  };

  /// 이어달리기 구간 업로드(POST /runs/{id}/continue). 코스는 원래 기록의 것을 쓴다.
  Map<String, dynamic> toContinueJson() => {
    'segment_id': segmentId,
    'started_at': startedAt.toUtc().toIso8601String(),
    'ended_at': endedAt.toUtc().toIso8601String(),
    'distance_meters': distanceMeters,
    'duration_sec': duration.inSeconds,
    'path': path.map((e) => e.toJson()).toList(),
  };
}

/// 러닝 기록을 서버에 올린 결과. 코스 완주 시 스탬프가 함께 내려온다.
class RunUploadResult {
  const RunUploadResult({required this.record, this.earnedStampId});

  final RunRecord record;
  final String? earnedStampId;

  bool get earnedStamp => earnedStampId != null;

  factory RunUploadResult.fromJson(Map<String, dynamic> json) =>
      RunUploadResult(
        record: RunRecord.fromJson(json['record'] as Map<String, dynamic>),
        earnedStampId: json['earned_stamp_id']?.toString(),
      );
}
