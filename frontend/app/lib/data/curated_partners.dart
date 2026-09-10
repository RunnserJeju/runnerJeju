import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

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
    required this.iconAsset,
    required this.tint,
  });

  final String name;

  /// 업종 라벨. 예) '카페', '러닝 용품'.
  final String category;

  /// 러너 대상 혜택 한 줄. 예) '아메리카노 10% 할인'.
  final String benefit;

  /// 업종 아이콘 SVG 경로. 색은 [tint]로 입힌다.
  final String iconAsset;

  /// 아이콘 색. 아이콘 타일 배경은 이 색을 옅게 깐다.
  final Color tint;
}

/// 홈 큐레이션에서 코스와 순환 매칭해 보여줄 더미 제휴처 목록.
const List<CuratedPartner> kCuratedPartners = [
  CuratedPartner(
    name: '해변 원두 로스터리',
    category: '카페',
    benefit: '러너 인증 시 아메리카노 10% 할인',
    iconAsset: 'assets/icons/partner_cafe.svg',
    tint: AppColors.tintAmber,
  ),
  CuratedPartner(
    name: '러너스 편집샵',
    category: '러닝 용품',
    benefit: '러닝화·용품 5% 상시 할인',
    iconAsset: 'assets/icons/partner_shoe.svg',
    tint: AppColors.tintBlue,
  ),
  CuratedPartner(
    name: '제주 스테이',
    category: '숙박',
    benefit: '완주 스탬프 제시 시 조식 무료',
    iconAsset: 'assets/icons/partner_house.svg',
    tint: AppColors.tintGreen,
  ),
];

/// 코스 순번에 맞춰 제휴처를 순환 배정한다. 더미이므로 규칙은 단순하게 둔다.
CuratedPartner partnerForIndex(int index) =>
    kCuratedPartners[index % kCuratedPartners.length];
