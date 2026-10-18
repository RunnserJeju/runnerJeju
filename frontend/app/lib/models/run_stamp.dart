/// 받은 스탬프. 이름·도안은 스탬프 종류([StampDefinition])에서 온다 — 스탬프는
/// 코스와 분리됐고(#71), 코스 완주는 획득 조건의 하나다.
class RunStamp {
  const RunStamp({
    required this.id,
    required this.definitionId,
    required this.name,
    required this.acquiredAt,
    this.description,
    this.imageUrl,
    this.courseId,
    this.recordId,
  });

  final String id;
  final String definitionId;
  final String name;
  final DateTime acquiredAt;

  /// 획득 조건 안내.
  final String? description;

  /// 스탬프 도안 이미지. 없으면 앱에서 기본 도안을 그린다.
  final String? imageUrl;

  /// 코스 완주 스탬프면 그 코스. 그 밖의 스탬프는 null.
  final String? courseId;

  /// 스탬프를 받은 러닝 기록 id. 달리지 않고 받은 스탬프는 null.
  final String? recordId;

  factory RunStamp.fromJson(Map<String, dynamic> json) => RunStamp(
    id: json['id'].toString(),
    definitionId: json['stamp_definition_id'].toString(),
    name: json['name'] as String,
    acquiredAt: DateTime.parse(json['acquired_at'] as String),
    description: json['description'] as String?,
    imageUrl: json['image_url'] as String?,
    courseId: json['course_id']?.toString(),
    recordId: json['record_id']?.toString(),
  );
}

/// 스탬프 종류. 스탬프 탭이 아직 못 받은 칸까지 그리는 데 쓴다.
class StampDefinition {
  const StampDefinition({
    required this.id,
    required this.name,
    required this.conditionType,
    this.description,
    this.imageUrl,
    this.courseId,
  });

  final String id;
  final String name;

  /// 'course_complete' | 'manual'. 서버 app/stamp_rules.CONDITION_TYPES와 같다.
  final String conditionType;
  final String? description;
  final String? imageUrl;

  /// 코스 완주 스탬프면 그 코스.
  final String? courseId;

  factory StampDefinition.fromJson(Map<String, dynamic> json) =>
      StampDefinition(
        id: json['id'].toString(),
        name: json['name'] as String,
        conditionType: json['condition_type'] as String,
        description: json['description'] as String?,
        imageUrl: json['image_url'] as String?,
        courseId: json['course_id']?.toString(),
      );
}
