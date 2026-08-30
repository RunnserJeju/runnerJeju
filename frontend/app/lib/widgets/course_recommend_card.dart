import 'package:flutter/material.dart';

import '../models/running_course.dart';
import '../theme/app_theme.dart';

/// 홈 '추천 코스' 카드: 사진(상단) + 이름·특징(하단).
///
/// 코스에 대표 썸네일([RunningCourse.thumbnailUrl])이 있으면 배경으로 깔고,
/// 없거나 로딩에 실패하면 뉴트럴 플레이스홀더로 높이를 맞춰 가로 스크롤에서
/// 나란히 정렬되게 한다.
class CourseRecommendCard extends StatelessWidget {
  const CourseRecommendCard({
    super.key,
    required this.course,
    this.onTap,
    this.width = 220,
  });

  final RunningCourse course;

  final VoidCallback? onTap;

  /// 가로 스크롤에서 카드 하나의 폭.
  final double width;

  @override
  Widget build(BuildContext context) {
    final features = <String>[
      '${course.distanceKm}km',
      course.difficulty.label,
      if (course.tagList.isNotEmpty) course.tagList.first,
    ];

    return SizedBox(
      width: width,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFECEEF2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── 사진 ──
                SizedBox(
                  height: 120,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (course.thumbnailUrl != null)
                        Image.network(
                          course.thumbnailUrl!,
                          fit: BoxFit.cover,
                          // 로딩 실패(잘못된 URL·네트워크)면 플레이스홀더로 떨어진다.
                          errorBuilder: (_, _, _) => const _Placeholder(),
                        )
                      else
                        const _Placeholder(),
                      if (course.isCompletedByMe)
                        Positioned(
                          top: 10,
                          right: 10,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              size: 14,
                              color: AppColors.success,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // ── 이름 · 특징 ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        course.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        features.join('  ·  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF9AA0AC),
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

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.paper,
      alignment: Alignment.center,
      child: Icon(
        Icons.directions_run_rounded,
        size: 40,
        color: AppColors.ink.withValues(alpha: 0.12),
      ),
    );
  }
}
