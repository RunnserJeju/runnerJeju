import 'package:flutter/material.dart';

/// 서버 데이터를 그리는 화면의 로딩/에러/빈 상태를 한 곳에서 처리한다.
///
/// 서버가 아직 없어도 화면이 깨지지 않고 각 상태를 그대로 보여준다.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.snapshot,
    required this.builder,
    required this.onRetry,
    this.isEmpty,
    this.emptyTitle = '아직 데이터가 없어요',
    this.emptyMessage,
    this.emptyIcon = Icons.inbox_outlined,
  });

  final AsyncSnapshot<T> snapshot;
  final Widget Function(BuildContext context, T data) builder;
  final VoidCallback onRetry;

  /// 데이터를 받았지만 비어 있는지 판단하는 함수. 없으면 빈 상태를 쓰지 않는다.
  final bool Function(T data)? isEmpty;

  final String emptyTitle;
  final String? emptyMessage;
  final IconData emptyIcon;

  @override
  Widget build(BuildContext context) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }

    if (snapshot.hasError) {
      return _StateMessage(
        icon: Icons.wifi_off_rounded,
        title: '불러오지 못했어요',
        message: '${snapshot.error}',
        actionLabel: '다시 시도',
        onAction: onRetry,
      );
    }

    final data = snapshot.data;
    if (data == null) {
      return _StateMessage(
        icon: emptyIcon,
        title: emptyTitle,
        message: emptyMessage,
        actionLabel: '새로고침',
        onAction: onRetry,
      );
    }

    if (isEmpty?.call(data) ?? false) {
      return _StateMessage(
        icon: emptyIcon,
        title: emptyTitle,
        message: emptyMessage,
        actionLabel: '새로고침',
        onAction: onRetry,
      );
    }

    return builder(context, data);
  }
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({
    required this.icon,
    required this.title,
    required this.actionLabel,
    required this.onAction,
    this.message,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 44,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleMedium),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: onAction,
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}
