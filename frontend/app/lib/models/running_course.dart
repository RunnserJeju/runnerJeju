import 'course_facility.dart';
import 'geo_point.dart';

/// 코스 난이도. [value]는 서버 `courses.difficulty`(SMALLINT)와 같은 값이어야 한다.
enum CourseDifficulty {
  easy(1, '★', '초급'),
  normal(2, '★★', '중급'),
  hard(3, '★★★', '고급');

  const CourseDifficulty(this.value, this.label, this.title);

  final int value;

  /// 별 표기. 상세/칩처럼 좁은 자리에 쓴다.
  final String label;

  /// 글자 표기. 홈 추천 카드 뱃지에 쓴다.
  final String title;

  static CourseDifficulty fromValue(int? value) =>
      CourseDifficulty.values.firstWhere(
        (e) => e.value == value,
        orElse: () => CourseDifficulty.normal,
      );
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
    this.parkings = const [],
    this.restrooms = const [],
    this.description,
    this.estimatedTimeMin,
    this.thumbnailUrl,
    this.stampImageUrl,
    this.completedCount = 0,
    this.isCompletedByMe = false,
    this.startPoint,
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

  /// 옛 단일 주소 필드. [parkings]/[restrooms]로 대체되는 중이라 새 코스에선
  /// 늘 null이다(서버 컬럼 drop 전까지만 유지).
  final String? parkingAddress;
  final String? restroomAddress;

  /// 근처 주차장/화장실. 코스당 여러 개이고 좌표를 포함해 지도에 마커로 찍는다.
  final List<CourseFacility> parkings;
  final List<CourseFacility> restrooms;

  final String? description;

  /// 예상 소요시간(분). 명단에 없으면 null이라 화면에서 숨긴다. 안내값이다.
  final int? estimatedTimeMin;

  /// 대표 썸네일 URL(Supabase Storage public URL). 없으면 null.
  final String? thumbnailUrl;

  /// 이 코스 완주 시 주는 스탬프 도안 URL. 없으면 앱이 기본 도안을 그린다.
  /// 스탬프 앨범이 잠긴 칸(미획득)의 목표 도안을 그릴 때도 쓴다.
  final String? stampImageUrl;

  /// 코스를 이루는 좌표 목록. 지도에 그대로 폴리라인으로 그린다.
  final List<GeoPoint> path;

  /// 이 코스를 완주한 전체 러너 수.
  final int completedCount;

  /// 내가 이미 완주해서 스탬프를 받았는지.
  final bool isCompletedByMe;

  /// 코스가 시작되는 지점 = 지도에 라벨을 찍는 자리.
  ///
  /// 값은 경로의 첫 점과 같지만 필드로 따로 둔다. 목록 응답에는 [path]가 빠져
  /// 있어서(용량 때문), 지도가 코스마다 상세를 다시 부르지 않으려면 점 하나는
  /// 목록에서 바로 받아야 한다. 경로가 없는 코스면 null이다.
  final GeoPoint? startPoint;

  GeoPoint? get endPoint => path.isEmpty ? null : path.last;

  /// 예상 소요시간을 사람이 읽는 문자열로. 없으면 null이라 화면에서 숨긴다.
  /// 예) 45 → "45분", 90 → "1시간 30분", 120 → "2시간".
  String? get estimatedTimeLabel {
    final m = estimatedTimeMin;
    if (m == null) return null;
    if (m < 60) return '$m분';
    final hours = m ~/ 60;
    final minutes = m % 60;
    return minutes == 0 ? '$hours시간' : '$hours시간 $minutes분';
  }

  /// 칩으로 보여줄 태그 목록. 빈 항목과 앞뒤 공백은 걸러낸다.
  List<String> get tagList => (tags ?? '')
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
    parkings: _facilities(json['parkings']),
    restrooms: _facilities(json['restrooms']),
    description: json['description'] as String?,
    estimatedTimeMin: (json['estimated_time_min'] as num?)?.toInt(),
    thumbnailUrl: json['thumbnail_url'] as String?,
    stampImageUrl: json['stamp_image_url'] as String?,
    path: ((json['path'] as List?) ?? const [])
        .map((e) => GeoPoint.fromJson(e as Map<String, dynamic>))
        .toList(),
    completedCount: (json['completed_count'] as num?)?.toInt() ?? 0,
    isCompletedByMe: json['is_completed_by_me'] as bool? ?? false,
    startPoint: json['start_point'] == null
        ? null
        : GeoPoint.fromJson(json['start_point'] as Map<String, dynamic>),
  );
}

/// 목록/상세 응답의 parkings·restrooms(둘 다 없을 수 있음)를 파싱한다.
List<CourseFacility> _facilities(dynamic raw) => ((raw as List?) ?? const [])
    .map((e) => CourseFacility.fromJson(e as Map<String, dynamic>))
    .toList();
