/// 코스에 연결된 협력업체 한 곳. 서버 `PartnerSummary`(schemas.py)와 1:1이다.
///
/// 업체는 서버 partners 테이블에 따로 있고 코스 응답에 실려 온다. [CourseFacility]와
/// 달리 이름이 필수, 주소가 선택이다. 좌표는 운영 웹이 등록 시점에 채운 값이라 지도에
/// 그대로 마커로 찍는다.
class CoursePartner {
  const CoursePartner({
    required this.id,
    required this.name,
    this.address,
    required this.lat,
    required this.lng,
    this.comment,
    this.instagram,
    this.benefit,
    this.detail = const {},
  });

  /// partners 테이블의 id. 여러 코스에 같은 업체가 걸리면 같은 값이다.
  final String id;
  final String name;
  final String? address;
  final double lat;
  final double lng;
  final String? comment;

  /// 계정명이나 URL. 서버가 형식을 정하지 않는다.
  final String? instagram;

  /// 예) "러너 인증 시 아메리카노 10% 할인".
  final String? benefit;

  /// 형태가 정해지지 않은 부가 정보(서버 partners.detail JSONB).
  final Map<String, dynamic> detail;

  /// 목록 한 줄 표기. 주소가 있으면 "이름 · 주소", 없으면 이름만.
  String get label => address == null ? name : '$name · $address';

  factory CoursePartner.fromJson(Map<String, dynamic> json) => CoursePartner(
    id: json['id'].toString(),
    name: json['name'] as String,
    address: json['address'] as String?,
    lat: (json['lat'] as num).toDouble(),
    lng: (json['lng'] as num).toDouble(),
    comment: json['comment'] as String?,
    instagram: json['instagram'] as String?,
    benefit: json['benefit'] as String?,
    detail: (json['detail'] as Map<String, dynamic>?) ?? const {},
  );
}
