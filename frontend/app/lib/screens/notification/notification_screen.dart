import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 알림 화면. 홈 헤더의 벨에서 연다. 공지사항과는 별개로, 스탬프 획득·목표 달성
/// 같은 사용자별 이벤트를 보여줄 자리다.
///
/// 아직 알림을 만들어 보내는 쪽(서버·앱 어느 쪽에도)이 없어서 목록은 늘 비어
/// 있다. 데이터가 생기면 [_EmptyState] 자리에 목록을 넣으면 된다.
class NotificationScreen extends StatelessWidget {
  const NotificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('알림'),
        titleTextStyle: const TextStyle(
          color: AppColors.ink,
          fontSize: 26,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
        ),
        titleSpacing: 20,
        toolbarHeight: 64,
        actions: [
          TextButton(
            // 읽을 알림이 없으니 눌러도 할 일이 없다.
            onPressed: null,
            child: const Text(
              '모두 읽음',
              style: TextStyle(fontSize: 14, color: AppColors.muted),
            ),
          ),
          const SizedBox(width: 8),
        ],
        shape: const Border(bottom: BorderSide(color: AppColors.lineSoft)),
      ),
      body: const _EmptyState(),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 80),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_none_rounded,
              size: 40,
              color: AppColors.ink.withValues(alpha: 0.18),
            ),
            const SizedBox(height: 12),
            const Text(
              '알림이 없어요',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '새 소식이 오면 여기에 보여요',
              style: TextStyle(fontSize: 13, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
