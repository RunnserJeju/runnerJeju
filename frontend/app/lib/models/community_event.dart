/// 커뮤니티 이벤트. 그림(선택) + 게시글. 노출 기간 필터는 서버가 한다.
class CommunityEvent {
  const CommunityEvent({
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

  /// 본문. 링크(https://…, [글자](https://…))는 화면에서 눌러 열 수 있게 그린다.
  final String body;
  final DateTime createdAt;
  final String? imageUrl;

  /// 노출 기간. null이면 제한 없음.
  final DateTime? startsAt;
  final DateTime? endsAt;

  factory CommunityEvent.fromJson(Map<String, dynamic> json) => CommunityEvent(
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
