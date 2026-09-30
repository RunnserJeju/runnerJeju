import 'package:flutter/material.dart';

import '../../models/course_partner.dart';
import '../../theme/app_theme.dart';
import '../../widgets/partner_category_tile.dart';
import '../../widgets/section_title.dart';
import '../../widgets/sheet_handle.dart';

/// 협력업체 모드에서 업체를 골랐을 때 목록 시트 자리를 대신하는 상세 시트.
///
/// 코스 상세([CoursePreviewSheet])처럼 모달이 아니라 [Stack]에 얹는다 — 지도를
/// 계속 만지며 다른 핀을 눌러 볼 수 있어야 해서다.
class PartnerPreviewSheet extends StatelessWidget {
  const PartnerPreviewSheet({
    super.key,
    required this.partner,
    required this.onClose,
    required this.onNavigate,
    required this.onOpenInstagram,
    required this.onSelectCourse,
  });

  final CoursePartner partner;

  /// 목록으로 돌아간다.
  final VoidCallback onClose;
  final VoidCallback onNavigate;
  final VoidCallback onOpenInstagram;
  final ValueChanged<PartnerCourseRef> onSelectCourse;

  static const double _collapsedSize = 0.34;
  static const double _expandedSize = 0.82;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: _collapsedSize,
      minChildSize: _collapsedSize,
      maxChildSize: _expandedSize,
      snap: true,
      builder: (context, scrollController) => DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(color: Colors.black12, blurRadius: 16, offset: Offset(0, -2)),
          ],
        ),
        child: SafeArea(
          top: false,
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            children: [
              const Center(child: SheetHandle()),
              const SizedBox(height: 14),
              PartnerDetailContent(
                partner: partner,
                onClose: onClose,
                onNavigate: onNavigate,
                onOpenInstagram: onOpenInstagram,
                onSelectCourse: onSelectCourse,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 협력업체 상세 본문. 협력업체 모드의 시트와, 코스를 보다가 업체 핀을 눌렀을 때
/// 뜨는 모달([showPartnerDetailModal])이 같이 쓴다.
class PartnerDetailContent extends StatelessWidget {
  const PartnerDetailContent({
    super.key,
    required this.partner,
    required this.onClose,
    required this.onNavigate,
    required this.onOpenInstagram,
    this.onSelectCourse,
  });

  final CoursePartner partner;
  final VoidCallback onClose;
  final VoidCallback onNavigate;
  final VoidCallback onOpenInstagram;

  /// 연결 코스를 눌렀을 때. null이면(이미 그 코스를 보고 있는 모달) 코스 칸을 숨긴다.
  final ValueChanged<PartnerCourseRef>? onSelectCourse;

  @override
  Widget build(BuildContext context) {
    final category = partner.category;
    final comment = partner.comment;
    final benefit = partner.benefit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PartnerCategoryTile(category: category, size: 56),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    partner.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    category.label,
                    style: const TextStyle(fontSize: 13, color: AppColors.textSubtle),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded),
              tooltip: '닫기',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        if (benefit != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: category.tint.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.local_offer_rounded, size: 18, color: category.tint),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    benefit,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: onNavigate,
                icon: const Icon(Icons.directions_walk_rounded),
                label: const Text('길찾기'),
              ),
            ),
            if (partner.instagramUrl != null) ...[
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onOpenInstagram,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('인스타그램'),
                ),
              ),
            ],
          ],
        ),
        if (comment != null) ...[
          const SizedBox(height: 20),
          const SectionTitle('소개', small: true),
          const SizedBox(height: 8),
          Text(
            comment,
            style: const TextStyle(fontSize: 14, height: 1.6, color: AppColors.textBody),
          ),
        ],
        if (partner.address != null) ...[
          const SizedBox(height: 20),
          const SectionTitle('위치', small: true),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.place_outlined, size: 17, color: AppColors.textSubtle),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  partner.address!,
                  style: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.textBody),
                ),
              ),
            ],
          ),
        ],
        if (onSelectCourse != null && partner.courses.isNotEmpty) ...[
          const SizedBox(height: 20),
          const SectionTitle('근처 러닝 코스', small: true),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final course in partner.courses)
                ActionChip(
                  avatar: const Icon(Icons.route_rounded, size: 16),
                  label: Text(course.name),
                  onPressed: () => onSelectCourse!(course),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 코스를 보다가 그 코스의 협력업체 핀을 눌렀을 때. 코스 선택을 깨지 않도록 모달로
/// 띄운다(협력업체 모드로 넘어가면 보고 있던 코스 경로가 사라진다).
Future<void> showPartnerDetailModal(
  BuildContext context, {
  required CoursePartner partner,
  required VoidCallback onNavigate,
  required VoidCallback onOpenInstagram,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: SheetHandle()),
            const SizedBox(height: 14),
            PartnerDetailContent(
              partner: partner,
              onClose: () => Navigator.of(sheetContext).pop(),
              onNavigate: onNavigate,
              onOpenInstagram: onOpenInstagram,
            ),
          ],
        ),
      ),
    ),
  );
}
