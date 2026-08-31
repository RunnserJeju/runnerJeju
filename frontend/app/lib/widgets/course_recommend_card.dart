import 'package:flutter/material.dart';

import '../models/running_course.dart';
import '../theme/app_theme.dart';
import 'course_thumbnail.dart';

/// 홈 '추천 코스' 카드: 사진(상단) + 이름·특징(하단).
///
/// 썸네일 처리는 [CourseThumbnail]이 맡는다 — 없거나 실패해도 같은 높이라
/// 가로 스크롤에서 카드가 나란히 정렬된다.
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
                      CourseThumbnail(url: course.thumbnailUrl, iconSize: 40),
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
