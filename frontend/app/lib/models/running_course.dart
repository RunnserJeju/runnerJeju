import 'geo_point.dart';

enum CourseDifficulty {
  easy('입문'),
  normal('보통'),
  hard('상급');

  const CourseDifficulty(this.label);

  final String label;

  static CourseDifficulty fromName(String? name) =>
      CourseDifficulty.values.firstWhere(
        (e) => e.name == name,
        orElse: () => CourseDifficulty.normal,
      );
}

/// 서버에서 내려받아 따라 달리는 러닝 코스.
class RunningCourse {
  const RunningCourse({
    required this.id,
    required this.name,
    required this.distanceMeters,
    required this.path,
    this.description,
    this.region,
    this.difficulty = CourseDifficulty.normal,
    this.estimatedDuration,
    this.elevationGainMeters,
    this.thumbnailUrl,
    this.completedCount = 0,
    this.isCompletedByMe = false,
  });

  final String id;
  final String name;
  final String? description;

  /// 코스가 속한 지역명 (예: 애월, 성산).
  final String? region;

  final double distanceMeters;
  final CourseDifficulty difficulty;
  final Duration? estimatedDuration;
  final double? elevationGainMeters;
  final String? thumbnailUrl;

  /// 코스를 이루는 좌표 목록. 지도에 그대로 폴리라인으로 그린다.
  final List<GeoPoint> path;

  /// 이 코스를 완주한 전체 러너 수.
  final int completedCount;

  /// 내가 이미 완주해서 스탬프를 받았는지.
  final bool isCompletedByMe;

  GeoPoint? get startPoint => path.isEmpty ? null : path.first;
  GeoPoint? get endPoint => path.isEmpty ? null : path.last;

  factory RunningCourse.fromJson(Map<String, dynamic> json) => RunningCourse(
    id: json['id'].toString(),
    name: json['name'] as String,
    description: json['description'] as String?,
    region: json['region'] as String?,
    distanceMeters: (json['distance_meters'] as num).toDouble(),
    difficulty: CourseDifficulty.fromName(json['difficulty'] as String?),
    estimatedDuration: json['estimated_duration_sec'] == null
        ? null
        : Duration(seconds: (json['estimated_duration_sec'] as num).toInt()),
    elevationGainMeters: (json['elevation_gain_meters'] as num?)?.toDouble(),
    thumbnailUrl: json['thumbnail_url'] as String?,
    path: ((json['path'] as List?) ?? const [])
        .map((e) => GeoPoint.fromJson(e as Map<String, dynamic>))
        .toList(),
    completedCount: (json['completed_count'] as num?)?.toInt() ?? 0,
    isCompletedByMe: json['is_completed_by_me'] as bool? ?? false,
  );
}

/// 사용자가 새 코스를 서버에 올릴 때 보내는 요청 본문.
class CourseUploadRequest {
  const CourseUploadRequest({
    required this.name,
    required this.path,
    required this.distanceMeters,
    this.description,
    this.region,
    this.difficulty = CourseDifficulty.normal,
  });

  final String name;
  final String? description;
  final String? region;
  final CourseDifficulty difficulty;
  final double distanceMeters;
  final List<GeoPoint> path;

  Map<String, dynamic> toJson() => {
    'name': name,
    if (description != null) 'description': description,
    if (region != null) 'region': region,
    'difficulty': difficulty.name,
    'distance_meters': distanceMeters,
    'path': path.map((e) => e.toJson()).toList(),
  };
}
