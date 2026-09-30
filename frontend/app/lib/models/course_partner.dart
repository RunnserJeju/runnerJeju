import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'geo_point.dart';

/// 협력업체 업종. 서버는 업종 컬럼 없이 `detail.category`에 문자열로 담는다
/// (운영 웹 협력업체 폼의 "업종" 선택이 채운다). 모르는 값·빈 값은 [other]다.
enum PartnerCategory {
  cafe('cafe', '카페', Icons.local_cafe_rounded, AppColors.tintAmber, 'assets/icons/partner_cafe.svg'),
  food('food', '음식점', Icons.restaurant_rounded, Color(0xFFEF6C57), null),
  stay('stay', '숙박', Icons.hotel_rounded, AppColors.tintGreen, 'assets/icons/partner_house.svg'),
  store('store', '상점', Icons.shopping_bag_rounded, AppColors.tintBlue, null),
  other('other', '기타', Icons.storefront_rounded, Color(0xFFFF8A00), null);

  const PartnerCategory(this.wire, this.label, this.icon, this.tint, this.svgAsset);

  /// `detail.category`에 들어가는 값.
  final String wire;
  final String label;

  /// 지도 마커에 새기는 글리프. 마커는 캔버스로 그려서 SVG를 쓸 수 없다.
  final IconData icon;
  final Color tint;

  /// 목록 타일에 쓰는 SVG(있는 업종만). 없으면 [icon]으로 대신한다.
  final String? svgAsset;

  static PartnerCategory fromWire(Object? value) => PartnerCategory.values.firstWhere(
    (category) => category.wire == value,
    orElse: () => PartnerCategory.other,
  );
}

/// 협력업체에 연결된 코스(이름만). 협력업체 시트에서 그 코스로 넘어갈 때 쓴다.
class PartnerCourseRef {
  const PartnerCourseRef({required this.id, required this.name});

  final String id;
  final String name;

  factory PartnerCourseRef.fromJson(Map<String, dynamic> json) =>
      PartnerCourseRef(id: json['id'].toString(), name: json['name'] as String);
}

/// 협력업체 한 곳. 서버 `PartnerSummary`/`PartnerWithCourses`(schemas.py)와 1:1이다.
///
/// 코스 응답에 실려 올 때는 [courses]가 비어 있고, 협력업체 목록(GET /partners)으로
/// 받으면 연결된 코스가 채워진다. [CourseFacility]와 달리 이름이 필수, 주소가 선택이다.
/// 좌표는 운영 웹이 등록 시점에 채운 값이라 지도에 그대로 마커로 찍는다.
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
    this.courses = const [],
  });

  /// partners 테이블의 id. 여러 코스에 같은 업체가 걸리면 같은 값이다.
  final String id;
  final String name;
  final String? address;
  final double lat;
  final double lng;
  final String? comment;

  /// 계정명(@handle)이나 URL. 서버가 형식을 정하지 않는다 — [instagramUrl] 참고.
  final String? instagram;

  /// 예) "러너 인증 시 아메리카노 10% 할인".
  final String? benefit;

  /// 형태가 정해지지 않은 부가 정보(서버 partners.detail JSONB). 지금은 category만 읽는다.
  final Map<String, dynamic> detail;

  /// 연결된 코스(이름순). 코스 응답에서 온 업체는 비어 있다.
  final List<PartnerCourseRef> courses;

  PartnerCategory get category => PartnerCategory.fromWire(detail['category']);

  GeoPoint get point => GeoPoint(latitude: lat, longitude: lng);

  /// 목록 한 줄 표기. 주소가 있으면 "이름 · 주소", 없으면 이름만.
  String get label => address == null ? name : '$name · $address';

  /// 인스타그램 프로필 URL. 운영자가 URL을 넣었으면 그대로, 계정명이면 만들어 준다.
  Uri? get instagramUrl {
    final raw = instagram?.trim();
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return Uri.tryParse(raw);
    final handle = raw.replaceFirst(RegExp(r'^@'), '');
    return Uri.https('www.instagram.com', '/$handle/');
  }

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
    courses: [
      for (final course in (json['courses'] as List?) ?? const [])
        PartnerCourseRef.fromJson(course as Map<String, dynamic>),
    ],
  );
}
