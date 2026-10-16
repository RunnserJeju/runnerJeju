/// 홈 섹션의 한 칸. 서버 `HomeCurationItem`과 1:1이다.
class HomeCurationItem {
  const HomeCurationItem({required this.id, this.describe, this.detail = const {}});

  /// 섹션에 따라 코스 id 또는 협력업체 id.
  final String id;

  /// 운영자가 쓴 큐레이션 설명. 앱 노출 방식은 아직 정하지 않았다.
  final String? describe;

  /// 형태가 정해지지 않은 부가 정보(서버 *_curations.detail JSONB).
  final Map<String, dynamic> detail;

  factory HomeCurationItem.fromJson(Map<String, dynamic> json) => HomeCurationItem(
    id: json['id'].toString(),
    describe: json['describe'] as String?,
    detail: (json['detail'] as Map<String, dynamic>?) ?? const {},
  );
}

/// 홈 두 섹션에 띄울 것(운영 웹 '홈 구성'에서 고른다). 서버 `HomeCurationOut`과 1:1이다.
///
/// 코스·협력업체 자체는 오지 않는다 — 홈이 이미 받는 목록에서 id로 찾아 쓴다. 목록에
/// 없는 id(비공개로 바뀐 코스 등)는 화면에서 건너뛴다.
class HomeCuration {
  const HomeCuration({required this.courses, required this.partners});

  /// '러닝 코스 큐레이션'에 띄울 코스(순서대로).
  final List<HomeCurationItem> courses;

  /// '추천 협력 업체'에 띄울 업체(순서대로).
  final List<HomeCurationItem> partners;

  factory HomeCuration.fromJson(Map<String, dynamic> json) => HomeCuration(
    courses: [
      for (final item in (json['courses'] as List?) ?? const [])
        HomeCurationItem.fromJson(item as Map<String, dynamic>),
    ],
    partners: [
      for (final item in (json['partners'] as List?) ?? const [])
        HomeCurationItem.fromJson(item as Map<String, dynamic>),
    ],
  );
}
