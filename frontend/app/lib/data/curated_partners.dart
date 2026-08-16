import 'package:flutter/material.dart';

/// 러닝 코스 큐레이션에 붙는 제휴 업체.
///
/// 백엔드에 협력업체 엔티티가 아직 없어서(=DB에서 못 불러옴) 홈 큐레이션 섹션은
/// 이 하드코딩 더미로 채운다. 협력업체 API가 생기면 이 파일을 모델/서비스로
/// 대체하면 된다 — 화면 쪽은 [CuratedPartner] 형태만 유지하면 그대로 붙는다.
class CuratedPartner {
  const CuratedPartner({
    required this.name,
    required this.category,
    required this.benefit,
    required this.icon,
  });

  final String name;

  /// 업종 라벨. 예) '카페', '러닝 편집샵'.
  final String category;

  /// 러너 대상 혜택 한 줄. 예) '아메리카노 10% 할인'.
  final String benefit;

  final IconData icon;
}

/// 홈 큐레이션에서 코스와 순환 매칭해 보여줄 더미 제휴처 목록.
const List<CuratedPartner> kCuratedPartners = [
  CuratedPartner(
    name: '해변 원두 로스터리',
    category: '카페',
    benefit: '러너 인증 시 아메리카노 10% 할인',
    icon: Icons.local_cafe_rounded,
  ),
  CuratedPartner(
    name: '러너스 편집샵',
    category: '러닝 용품',
    benefit: '러닝화·용품 5% 상시 할인',
    icon: Icons.storefront_rounded,
  ),
  CuratedPartner(
    name: '오션뷰 포케볼',
    category: '건강식',
    benefit: '완주 스탬프 제시 시 러너 세트 제공',
    icon: Icons.rice_bowl_rounded,
  ),
  CuratedPartner(
    name: '제주 리커버리 스파',
    category: '회복·마사지',
    benefit: '풋 케어 15분 무료 체험',
    icon: Icons.spa_rounded,
  ),
];

/// 코스 순번에 맞춰 제휴처를 순환 배정한다. 더미이므로 규칙은 단순하게 둔다.
CuratedPartner partnerForIndex(int index) =>
    kCuratedPartners[index % kCuratedPartners.length];
