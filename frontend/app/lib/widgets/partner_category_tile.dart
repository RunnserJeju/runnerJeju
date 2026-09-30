import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/course_partner.dart';

/// 협력업체 업종 아이콘 타일: 업종 색을 옅게 깐 둥근 사각형에 업종 아이콘.
///
/// 홈 큐레이션과 러닝 탭 협력업체 시트가 같이 쓴다. 전용 SVG가 있는 업종은 SVG를,
/// 없으면 머티리얼 아이콘을 그린다.
class PartnerCategoryTile extends StatelessWidget {
  const PartnerCategoryTile({super.key, required this.category, this.size = 48});

  final PartnerCategory category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final iconSize = size * 0.46;
    final svg = category.svgAsset;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: category.tint.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(size / 4),
      ),
      child: svg != null
          ? SvgPicture.asset(
              svg,
              width: iconSize,
              height: iconSize,
              colorFilter: ColorFilter.mode(category.tint, BlendMode.srcIn),
            )
          : Icon(category.icon, size: iconSize, color: category.tint),
    );
  }
}
