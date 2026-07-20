import 'package:flutter/material.dart';

import '../models/running_course.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

/// 코스 목록/홈에서 쓰는 코스 요약 카드.
class CourseCard extends StatelessWidget {
  const CourseCard({super.key, required this.course, this.onTap});

  final RunningCourse course;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
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
              if (course.description != null) ...[
                const SizedBox(height: 4),
                Text(
                  course.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _Tag(
                    icon: Icons.straighten_rounded,
                    label: '${Formatters.distanceKm(course.distanceMeters)}km',
                  ),
                  _Tag(
                    icon: Icons.trending_up_rounded,
                    label: course.difficulty.label,
                  ),
                  if (course.estimatedDuration != null)
                    _Tag(
                      icon: Icons.schedule_rounded,
                      label: Formatters.duration(course.estimatedDuration!),
                    ),
                  if (course.region != null)
                    _Tag(
                      icon: Icons.place_outlined,
                      label: course.region!,
                    ),
                ],
              ),
            ],
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
