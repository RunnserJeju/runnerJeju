import 'package:flutter/material.dart';

import '../models/running_course.dart';
import '../theme/app_theme.dart';
import 'course_thumbnail.dart';

/// 코스 목록/홈에서 쓰는 코스 요약 카드.
class CourseCard extends StatelessWidget {
  const CourseCard({super.key, required this.course, this.onTap});

  final RunningCourse course;
  final VoidCallback? onTap;

  /// 썸네일 한 변. 카드 내용 높이도 이 값으로 고정된다 — 태그·설명이 몇 개든
  /// 목록의 모든 카드가 같은 높이다.
  static const double _thumbnailSize = 96;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = course.description;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            height: _thumbnailSize,
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox.square(
                    dimension: _thumbnailSize,
                    child: CourseThumbnail(
                      url: course.thumbnailUrl,
                      iconSize: 30,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              course.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (course.isCompletedByMe)
                            const Icon(
                              Icons.verified_rounded,
                              size: 20,
                              color: AppColors.success,
                            ),
                        ],
                      ),
                      if (description != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      // 높이를 한 줄로 고정한다. 넘치는 태그는 Wrap이 통째로
                      // 다음 줄로 내리고 ClipRect가 그 줄을 숨긴다 — 전체 태그는
                      // 상세 시트에서 보인다.
                      SizedBox(
                        height: 30,
                        child: ClipRect(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _Tag(
                                icon: Icons.straighten_rounded,
                                label: '왕복 ${course.distanceKm}km',
                              ),
                              _Tag(
                                icon: Icons.trending_up_rounded,
                                label: course.difficulty.label,
                              ),
                              if (course.estimatedTimeLabel != null)
                                _Tag(
                                  icon: Icons.schedule_rounded,
                                  label: course.estimatedTimeLabel!,
                                ),
                              for (final tag in course.tagList)
                                _Tag(icon: Icons.sell_outlined, label: tag),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: const Color(0xFF5B6472)),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF3D4552),
            ),
          ),
        ],
      ),
    );
  }
}
