import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/course_partner.dart';
import '../theme/app_theme.dart';
import 'listing_card.dart';
import 'partner_category_tile.dart';
import 'tag_chip.dart';

/// 협력업체 목록 카드. 코스 카드와 같은 틀([ListingCard])이라 두 목록의 밀도가 같다.
/// 썸네일이 없으면 업종 아이콘 타일을 같은 자리에 그린다.
class PartnerCard extends StatelessWidget {
  const PartnerCard({
    super.key,
    required this.partner,
    this.onTap,
    this.distanceLabel,
  });

  final CoursePartner partner;
  final VoidCallback? onTap;

  /// '1.2km' 같은 현위치 거리. 위치를 모르면 null이라 숨긴다.
  final String? distanceLabel;

  @override
  Widget build(BuildContext context) {
    final category = partner.category;
    final address = partner.address;

    return ListingCard(
      onTap: onTap,
      thumbnail: PartnerThumbnail(partner: partner),
      title: partner.name,
      titleTrailing: [
        if (distanceLabel case final label?) ...[
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.accent,
            ),
          ),
        ],
      ],
      subtitle: partner.benefit,
      subtitleStyle: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
      footer: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          TagChip(icon: category.icon, label: category.label),
          if (address != null) TagChip(icon: Icons.place_outlined, label: address),
        ],
      ),
    );
  }
}

/// 협력업체 썸네일. 주어진 자리를 꽉 채우고, 없거나 못 받아오면 업종 타일로 대신한다.
class PartnerThumbnail extends StatelessWidget {
  const PartnerThumbnail({super.key, required this.partner, this.size = ListingCard.thumbnailSize});

  final CoursePartner partner;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = partner.thumbnailUrl;
    final fallback = PartnerCategoryTile(category: partner.category, size: size);
    if (url == null || url.isEmpty) return fallback;

    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, _) => fallback,
      errorWidget: (_, _, _) => fallback,
    );
  }
}
