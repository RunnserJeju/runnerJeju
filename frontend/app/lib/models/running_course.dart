import 'geo_point.dart';

/// 코스 난이도. [value]는 서버 `courses.difficulty`(SMALLINT)와 같은 값이어야 한다.
enum CourseDifficulty {
  easy(1, '★'),
  normal(2, '★★'),
  hard(3, '★★★');

  const CourseDifficulty(this.value, this.label);

  final int value;
  final String label;

  static CourseDifficulty fromValue(int? value) => CourseDifficulty.values
      .firstWhere((e) => e.value == value, orElse: () => CourseDifficulty.normal);
}

/// 서버에서 내려받아 따라 달리는 러닝 코스.
///
/// 필드는 코스 명단 시트의 컬럼과 1:1이다. 관리자만 등록하고, 고칠 일은 DB에서
/// 직접 처리하므로 앱에는 수정 경로가 없다.
class RunningCourse {
  const RunningCourse({
    required this.id,
    required this.name,
    required this.distanceKm,
    required this.address,
    required this.path,
    this.difficulty = CourseDifficulty.normal,
    this.tags,
    this.parkingAddress,
    this.restroomAddress,
    this.description,
    this.completedCount = 0,
    this.isCompletedByMe = false,
  });

  final String id;
  final String name;

  /// 왕복 기준 거리(km). 시트에 적힌 안내값이라 경로를 실측한 거리가 아니다 —
  /// 진행률처럼 정확도가 필요한 계산에는 [path]에서 직접 거리를 재서 쓴다.
  final int distanceKm;

  final CourseDifficulty difficulty;

  /// 쉼표로 이어진 태그 문자열. 예) `"해안도로,제주시,동쪽"`
  final String? tags;

  /// 코스 시작 지점 주소.
  final String address;

  final String? parkingAddress;
  final String? restroomAddress;
  final String? description;

  /// 코스를 이루는 좌표 목록. 지도에 그대로 폴리라인으로 그린다.
  final List<GeoPoint> path;

  /// 이 코스를 완주한 전체 러너 수.
  final int completedCount;

  /// 내가 이미 완주해서 스탬프를 받았는지.
  final bool isCompletedByMe;

  GeoPoint? get startPoint => path.isEmpty ? null : path.first;
  GeoPoint? get endPoint => path.isEmpty ? null : path.last;

  /// 칩으로 보여줄 태그 목록. 빈 항목과 앞뒤 공백은 걸러낸다.
  List<String> get tagList =>
      (tags ?? '')
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

  factory RunningCourse.fromJson(Map<String, dynamic> json) => RunningCourse(
    id: json['id'].toString(),
    name: json['name'] as String,
    distanceKm: (json['distance_km'] as num).toInt(),
    difficulty: CourseDifficulty.fromValue(
      (json['difficulty'] as num?)?.toInt(),
    ),
    tags: json['tags'] as String?,
    address: json['address'] as String,
    parkingAddress: json['parking_address'] as String?,
    restroomAddress: json['restroom_address'] as String?,
    description: json['description'] as String?,
    path: ((json['path'] as List?) ?? const [])
        .map((e) => GeoPoint.fromJson(e as Map<String, dynamic>))
        .toList(),
    completedCount: (json['completed_count'] as num?)?.toInt() ?? 0,
    isCompletedByMe: json['is_completed_by_me'] as bool? ?? false,
  );
}
