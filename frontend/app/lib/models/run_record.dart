import 'geo_point.dart';

/// 완료된 러닝 1회의 기록.
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

  bool get isCourseRun => courseId != null;

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

  factory RunRecord.fromJson(Map<String, dynamic> json) => RunRecord(
    id: json['id']?.toString(),
    courseId: json['course_id']?.toString(),
    courseName: json['course_name'] as String?,
    startedAt: DateTime.parse(json['started_at'] as String),
    endedAt: DateTime.parse(json['ended_at'] as String),
    distanceMeters: (json['distance_meters'] as num).toDouble(),
    duration: Duration(seconds: (json['duration_sec'] as num).toInt()),
    path: ((json['path'] as List?) ?? const [])
        .map((e) => GeoPoint.fromJson(e as Map<String, dynamic>))
        .toList(),
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
