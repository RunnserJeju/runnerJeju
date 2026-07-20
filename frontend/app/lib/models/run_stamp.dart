/// 코스를 완주하면 발급되는 완주 스탬프.
class RunStamp {
  const RunStamp({
    required this.id,
    required this.courseId,
    required this.courseName,
    required this.acquiredAt,
    this.imageUrl,
    this.region,
    this.recordId,
  });

  final String id;
  final String courseId;
  final String courseName;
  final String? region;
  final DateTime acquiredAt;

  /// 스탬프 도안 이미지. 없으면 앱에서 기본 도안을 그린다.
  final String? imageUrl;

  /// 스탬프를 발급받은 러닝 기록 id.
  final String? recordId;

  factory RunStamp.fromJson(Map<String, dynamic> json) => RunStamp(
    id: json['id'].toString(),
    courseId: json['course_id'].toString(),
    courseName: json['course_name'] as String,
    region: json['region'] as String?,
    acquiredAt: DateTime.parse(json['acquired_at'] as String),
    imageUrl: json['image_url'] as String?,
    recordId: json['record_id']?.toString(),
  );
}
