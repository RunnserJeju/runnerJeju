/// 홈 화면 상단 이미지 배너 1개.
///
/// 이름을 `HomeBanner`로 둔 이유: Flutter Material에 이미 `Banner` 위젯이 있어서
/// 이름이 겹치면 매번 `import 'dart:...' as`로 피해야 한다.
class HomeBanner {
  const HomeBanner({
    required this.id,
    required this.imageUrl,
    required this.sortOrder,
    required this.createdAt,
  });

  final String id;
  final String imageUrl;
  final int sortOrder;
  final DateTime createdAt;

  factory HomeBanner.fromJson(Map<String, dynamic> json) => HomeBanner(
    id: json['id'].toString(),
    imageUrl: json['image_url'] as String,
    sortOrder: json['sort_order'] as int,
    createdAt: DateTime.parse(json['created_at'] as String),
  );
}
