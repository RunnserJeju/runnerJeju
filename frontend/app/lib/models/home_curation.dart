/// 홈 두 섹션에 띄울 것(운영 웹 '홈 구성'에서 고른다). 서버 `HomeCurationOut`과 1:1이다.
///
/// id만 온다 — 코스·협력업체 자체는 홈이 이미 받는 목록에서 찾아 쓴다. 목록에 없는
/// id(비공개로 바뀐 코스 등)는 화면에서 건너뛴다.
class HomeCuration {
  const HomeCuration({required this.courseIds, required this.partnerIds});

  /// '러닝 코스 큐레이션'에 띄울 코스(순서대로).
  final List<String> courseIds;

  /// '추천 협력 업체'에 띄울 업체(순서대로).
  final List<String> partnerIds;

  factory HomeCuration.fromJson(Map<String, dynamic> json) => HomeCuration(
    courseIds: [for (final id in (json['course_ids'] as List?) ?? const []) id.toString()],
    partnerIds: [for (final id in (json['partner_ids'] as List?) ?? const []) id.toString()],
  );
}
