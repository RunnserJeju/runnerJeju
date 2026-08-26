/// 러닝 프로그램. 커뮤니티 탭에 노출되는 러닝 모임/챌린지.
///
/// 아직 서버에 프로그램 API가 없어 목록은 비어 있다. 필드는 서버가 생길 때
/// 맞춰 갈 예정이라, 지금은 화면이 필요로 하는 최소만 둔다.
class RunningProgram {
  const RunningProgram({
    required this.id,
    required this.title,
    this.description,
    this.startDate,
    this.endDate,
    this.imageUrl,
  });

  final String id;
  final String title;
  final String? description;

  /// 프로그램 진행 기간. 상시 모집이면 둘 다 null이다.
  final DateTime? startDate;
  final DateTime? endDate;

  /// 프로그램 대표 이미지. 없으면 화면에서 기본 도안을 그린다.
  final String? imageUrl;

  factory RunningProgram.fromJson(Map<String, dynamic> json) => RunningProgram(
    id: json['id'].toString(),
    title: json['title'] as String,
    description: json['description'] as String?,
    startDate: json['start_date'] == null
        ? null
        : DateTime.parse(json['start_date'] as String),
    endDate: json['end_date'] == null
        ? null
        : DateTime.parse(json['end_date'] as String),
    imageUrl: json['image_url'] as String?,
  );
}
