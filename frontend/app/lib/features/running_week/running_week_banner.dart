import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'running_week.dart';

/// 커뮤니티 상단에 고정으로 보이는 러닝위크 배너. 홈 공지 배너와 같은 비율이다.
///
/// 이미지는 글자까지 넣은 완성본이라 위에 아무것도 얹지 않는다. 운영자가 이미지를
/// 아직 안 올렸으면 제목 카드로 대신한다.
class RunningWeekBanner extends StatelessWidget {
  const RunningWeekBanner({super.key, required this.week, required this.onTap});

  static const double aspectRatio = 402 / 172;

  final RunningWeek week;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final imageUrl = week.imageUrl;

    return AspectRatio(
      aspectRatio: aspectRatio,
      child: Material(
        color: AppColors.inkSoft,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: imageUrl != null && imageUrl.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => const SizedBox.shrink(),
                  errorWidget: (_, _, _) => _TitleCard(week: week),
                )
              : _TitleCard(week: week),
        ),
      ),
    );
  }
}

class _TitleCard extends StatelessWidget {
  const _TitleCard({required this.week});

  final RunningWeek week;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const Text(
            'RUNNING WEEK',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            week.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
