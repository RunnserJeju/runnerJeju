/// 발급된 쿠폰의 유효 상태. 서버가 used_at·valid_until로 계산해 내려준다.
enum CouponStatus {
  available('사용 가능'),
  used('사용 완료'),
  expired('기간 만료');

  const CouponStatus(this.label);

  final String label;

  static CouponStatus fromWire(String? value) => CouponStatus.values.firstWhere(
    (status) => status.name == value,
    orElse: () => CouponStatus.expired,
  );
}

/// 내 쿠폰 한 장. 서버 `MyCouponOut`(schemas.py)과 1:1이다.
///
/// 이름·혜택·설명은 쿠폰 종류를 라이브 참조하므로 운영자가 고치면 바로 바뀐다.
class Coupon {
  const Coupon({
    required this.id,
    required this.name,
    required this.benefit,
    required this.issuedAt,
    required this.status,
    this.description,
    this.usedAt,
    this.validUntil,
    this.partnerIds,
    this.usedPartnerName,
  });

  final String id;
  final String name;

  /// 예) "아메리카노 1잔". 쿠폰에서 가장 크게 보여준다.
  final String benefit;
  final String? description;
  final DateTime issuedAt;
  final DateTime? usedAt;

  /// 무기한이면 null.
  final DateTime? validUntil;
  final CouponStatus status;

  /// 쓸 수 있는 업체 id. null이면 모든 협력업체.
  final List<String>? partnerIds;

  /// 사용한 업체 이름. 미사용이거나 업체가 지워졌으면 null.
  final String? usedPartnerName;

  bool get isAvailable => status == CouponStatus.available;

  /// 이 업체에서 쓸 수 있는지.
  bool allows(String partnerId) =>
      partnerIds == null || partnerIds!.contains(partnerId);

  factory Coupon.fromJson(Map<String, dynamic> json) => Coupon(
    id: json['id'].toString(),
    name: json['name'] as String,
    benefit: json['benefit'] as String,
    description: json['description'] as String?,
    issuedAt: DateTime.parse(json['issued_at'] as String),
    usedAt: json['used_at'] == null
        ? null
        : DateTime.parse(json['used_at'] as String),
    validUntil: json['valid_until'] == null
        ? null
        : DateTime.parse(json['valid_until'] as String),
    status: CouponStatus.fromWire(json['status'] as String?),
    partnerIds: (json['partner_ids'] as List?)
        ?.map((e) => e.toString())
        .toList(),
    usedPartnerName: json['used_partner_name'] as String?,
  );
}
