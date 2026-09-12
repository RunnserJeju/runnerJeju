import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/running_course.dart';
import '../theme/app_theme.dart';

/// 홈 '추천 코스' 카드: 사진을 카드 가득 깔고 그 위에 난이도 뱃지와
/// 이름·주소·거리·시간·태그를 얹는다.
///
/// 썸네일이 없으면 같은 크기의 단색 면을 깔아 가로 스크롤에서 카드가 나란히
/// 정렬되게 한다.
class CourseRecommendCard extends StatelessWidget {
  const CourseRecommendCard({
    super.key,
    required this.course,
    this.onTap,
    this.width = 200,
    this.height = 240,
  });

  final RunningCourse course;

  final VoidCallback? onTap;

  /// 가로 스크롤에서 카드 하나의 크기.
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: const Color(0xFF93C5FD),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (course.thumbnailUrl case final url? when url.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => const SizedBox.shrink(),
                  errorWidget: (_, _, _) => const SizedBox.shrink(),
                ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Color(0xBF000000),
                      Color(0x33000000),
                      Color(0x00000000),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _LevelBadge(difficulty: course.difficulty),
                    if (course.isCompletedByMe)
                      Container(
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
                  ],
                ),
              ),
              Positioned(
                left: 14,
                right: 14,
                bottom: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      course.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        color: Colors.white,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      course.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.6),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _MetaRow(course: course),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.difficulty});

  final CourseDifficulty difficulty;

  @override
  Widget build(BuildContext context) {
    final color = switch (difficulty) {
      CourseDifficulty.easy => AppColors.levelEasy,
      CourseDifficulty.normal => AppColors.levelNormal,
      CourseDifficulty.hard => AppColors.levelHard,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.6),
        border: Border.all(color: color.withValues(alpha: 0.8), width: 0.6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        difficulty.title,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: Colors.white,
          height: 1.5,
        ),
      ),
    );
  }
}

/// 거리 · 시간 · 첫 태그. 시간과 태그는 없으면 뺀다.
class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.course});

  final RunningCourse course;

  @override
  Widget build(BuildContext context) {
    final time = course.estimatedTimeLabel;
    final tag = course.tagList.firstOrNull;

    return Row(
      children: [
        _MetaItem(
          asset: 'assets/icons/meta_run.svg',
          text: '${course.distanceKm} km',
        ),
        if (time != null) ...[
          const _Dot(),
          _MetaItem(asset: 'assets/icons/meta_time.svg', text: time),
        ],
        if (tag != null)
          Flexible(
            child: Text(
              '· $tag',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ),
      ],
    );
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.asset, required this.text});

  final String asset;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SvgPicture.asset(asset, width: 13, height: 13),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: Colors.white.withValues(alpha: 0.9),
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Text(
        '·',
        style: TextStyle(
          fontSize: 10,
          color: Colors.white.withValues(alpha: 0.3),
        ),
      ),
    );
  }
}
