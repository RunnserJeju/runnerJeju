import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/community_event.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/linked_text.dart';

/// 이벤트 상세. 그림(있으면) + 제목 + 본문. 본문 링크는 눌러서 연다.
class EventDetailScreen extends StatelessWidget {
  const EventDetailScreen({super.key, required this.event});

  final CommunityEvent event;

  @override
  Widget build(BuildContext context) {
    final imageUrl = event.imageUrl;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('이벤트')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          if (imageUrl != null && imageUrl.isNotEmpty)
            // 이벤트 그림은 글자까지 넣은 포스터일 수 있어 자르지 않고 원래 비율로 보인다.
            CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.fitWidth,
              width: double.infinity,
              placeholder: (_, _) => const AspectRatio(
                aspectRatio: 16 / 9,
                child: ColoredBox(color: AppColors.paper),
              ),
              errorWidget: (_, _, _) => const SizedBox.shrink(),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  Formatters.date(event.createdAt),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 18),
                LinkedText(
                  event.body,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.6,
                    color: AppColors.textBody,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
