import 'package:flutter/material.dart';

import '../models/running_course.dart';
import '../theme/app_theme.dart';

/// 홈 '추천 코스'에서 쓰는 라이트 미니멀 카드.
///
/// 코스에는 대표 이미지가 없어서(서버가 좌표만 준다) 사진이나 컬러 그라디언트로
/// 채우지 않고, 흰 카드 위 타이포와 여백으로 정리한다. 러닝 탭의 [CourseCard]와
/// 결이 같지만, 가로 스크롤에 맞춰 폭이 고정돼 있고 메타를 한 줄로 압축한다.
class CourseRecommendCard extends StatelessWidget {
  const CourseRecommendCard({
    super.key,
    required this.course,
    this.onTap,
    this.width = 232,
  });

  final RunningCourse course;
  final VoidCallback? onTap;

  /// 가로 스크롤에서 카드 하나의 폭.
  final double width;

  @override
  Widget build(BuildContext context) {
    final eyebrow = course.tagList.isNotEmpty
        ? course.tagList.first
        : course.address;

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
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          eyebrow,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF9AA0AC),
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      if (course.isCompletedByMe)
                        const Icon(
                          Icons.verified_rounded,
                          size: 18,
                          color: AppColors.success,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    course.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      height: 1.2,
                      color: AppColors.ink,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      _MetaPill(
                        icon: Icons.straighten_rounded,
                        label: '${course.distanceKm}km',
                      ),
                      const SizedBox(width: 6),
                      _MetaPill(label: course.difficulty.label),
                      const Spacer(),
                      if (course.completedCount > 0)
                        Text(
                          '${course.completedCount}명 완주',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFB0B5BF),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({this.icon, required this.label});

  final IconData? icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: const Color(0xFF5B6472)),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF3D4552),
            ),
          ),
        ],
      ),
    );
  }
}
