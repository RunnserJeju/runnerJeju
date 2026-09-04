/// 홈 화면에 노출되는 공지사항. [imageUrl]이 있으면 상단 배너 캐러셀에도 실린다.
///
/// 노출 기간(startsAt/endsAt) 필터링은 서버가 한다 — 앱은 지금 노출 중인 공지만
/// 받는다. 그래도 기간을 파싱해 두는 건 상세 표기 등 나중 쓰임을 위해서다.
class Notice {
  const Notice({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.imageUrl,
    this.startsAt,
    this.endsAt,
  });

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;

  /// 배너 이미지. null이면 텍스트 공지만.
  final String? imageUrl;

  bool get hasImage => imageUrl != null;

  /// 노출 기간. null이면 제한 없음(상시).
  final DateTime? startsAt;
  final DateTime? endsAt;

  factory Notice.fromJson(Map<String, dynamic> json) => Notice(
    id: json['id'].toString(),
    title: json['title'] as String,
    body: json['body'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
    imageUrl: json['image_url'] as String?,
    startsAt: json['starts_at'] == null
        ? null
        : DateTime.parse(json['starts_at'] as String),
    endsAt: json['ends_at'] == null
        ? null
        : DateTime.parse(json['ends_at'] as String),
  );
}
