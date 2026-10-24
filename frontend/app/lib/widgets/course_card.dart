import 'package:flutter/material.dart';

import '../models/running_course.dart';
import '../theme/app_theme.dart';
import 'course_thumbnail.dart';
import 'listing_card.dart';
import 'tag_chip.dart';

/// 코스 목록/홈에서 쓰는 코스 요약 카드. 틀은 [ListingCard].
class CourseCard extends StatelessWidget {
  const CourseCard({
    super.key,
    required this.course,
    this.onTap,
    this.distanceLabel,
  });

  final RunningCourse course;
  final VoidCallback? onTap;

  /// 현위치에서 시작점까지의 거리 표기. 예) '1.2km'. 없으면 안 그린다.
  final String? distanceLabel;

  @override
  Widget build(BuildContext context) {
    return ListingCard(
      onTap: onTap,
      thumbnail: CourseThumbnail(url: course.thumbnailUrl, iconSize: 30),
      title: course.name,
      titleTrailing: [
        if (course.isCompletedByMe)
          const Icon(Icons.verified_rounded, size: 20, color: AppColors.success),
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
      subtitle: course.description,
      // 넘치는 태그는 Wrap이 통째로 다음 줄로 내리고 틀의 ClipRect가 그 줄을 숨긴다.
      footer: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          TagChip(icon: Icons.straighten_rounded, label: '왕복 ${course.distanceKmLabel}km'),
          TagChip(icon: Icons.trending_up_rounded, label: course.difficulty.label),
          if (course.estimatedTimeLabel != null)
            TagChip(icon: Icons.schedule_rounded, label: course.estimatedTimeLabel!),
          for (final tag in course.tagList) TagChip(icon: Icons.sell_outlined, label: tag),
        ],
      ),
    );
  }
}
