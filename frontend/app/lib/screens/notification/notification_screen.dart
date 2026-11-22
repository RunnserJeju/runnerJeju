import 'package:flutter/material.dart';

import '../../models/app_notification.dart';
import '../../services/service_locator.dart';
import '../../theme/app_theme.dart';

/// 알림함. 홈 헤더의 벨에서 연다. 최근 7일 동안 받은 알림을 날짜별로 묶어 최신순으로 보여준다
/// (기간은 서버가 자른다). 항목을 누르면 읽음으로 바뀌고 푸시를 눌렀을 때와 같은 화면으로 간다.
class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

// 시안(ALR-01)의 색. 이 화면에서만 쓴다.
const _title = Color(0xFF1F2722);
const _body = Color(0xFF4C574F);
const _meta = Color(0xFF667169);
const _divider = Color(0xFFE5EBE2);
const _unreadFill = Color(0xFFF4F9EF);
const _unreadDot = Color(0xFF3D7827);

class _NotificationScreenState extends State<NotificationScreen> {
  static const _pageSize = 50;

  late Future<List<AppNotification>> _future = _load();

  /// 기간 안의 알림을 개수 제한 없이 전부 받는다.
  Future<List<AppNotification>> _load() async {
    final service = Services.instance.notification;
    final all = <AppNotification>[];
    while (true) {
      final page = await service.fetch(
        before: all.isEmpty ? null : all.last.createdAt,
        limit: _pageSize,
      );
      all.addAll(page);
      if (page.length < _pageSize) break;
    }
    // 벨의 안 읽음 표시도 같이 맞춘다.
    await service.refreshUnread();
    return all;
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() {
      _future = next;
    });
    await next.catchError((_) => const <AppNotification>[]);
  }

  /// 읽음 처리와 이동은 푸시를 눌렀을 때와 같은 길(AppShell)로 보낸다.
  void _open(AppNotification notification) => Services.instance.push.open((
    link: notification.link,
    id: notification.id,
  ));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('알림'),
        titleTextStyle: const TextStyle(
          color: _title,
          fontSize: 23,
          fontWeight: FontWeight.w700,
        ),
        titleSpacing: 0,
        toolbarHeight: 55,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: const Border(bottom: BorderSide(color: _divider)),
      ),
      body: FutureBuilder<List<AppNotification>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return _LoadError(onRetry: _refresh);
          final items = snapshot.data ?? const <AppNotification>[];
          if (items.isEmpty) return const _EmptyState();
          return RefreshIndicator(
            onRefresh: _refresh,
            child: _NotificationList(items: items, onTap: _open),
          );
        },
      ),
    );
  }
}

class _NotificationList extends StatelessWidget {
  const _NotificationList({required this.items, required this.onTap});

  final List<AppNotification> items;
  final ValueChanged<AppNotification> onTap;

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final children = <Widget>[];
    DateTime? currentDay;
    for (final item in items) {
      final day = DateUtils.dateOnly(item.createdAt.toLocal());
      if (day != currentDay) {
        children.add(
          _DayLabel(_dayLabel(day, today), first: currentDay == null),
        );
        currentDay = day;
      }
      children.add(_NotificationTile(item, onTap: () => onTap(item)));
    }
    children.add(const _RetentionNote());

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 16),
      children: children,
    );
  }

  static String _dayLabel(DateTime day, DateTime today) {
    final diff = today.difference(day).inDays;
    if (diff == 0) return '오늘';
    if (diff == 1) return '어제';
    return '${day.month}월 ${day.day}일';
  }
}

class _DayLabel extends StatelessWidget {
  const _DayLabel(this.text, {required this.first});

  final String text;
  final bool first;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, first ? 0 : 21, 20, 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          height: 23 / 14,
          fontWeight: FontWeight.w700,
          color: _meta,
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile(this.item, {required this.onTap});

  final AppNotification item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = !item.isRead;
    return Material(
      color: unread ? _unreadFill : Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 13, 60, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16.5,
                      height: 24 / 16.5,
                      fontWeight: FontWeight.w700,
                      color: _title,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 20.5 / 15,
                      color: _body,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    _time(item.createdAt.toLocal()),
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 16 / 12.5,
                      color: _meta,
                    ),
                  ),
                ],
              ),
            ),
            if (unread)
              const Positioned(
                top: 21,
                right: 24,
                child: SizedBox.square(
                  dimension: 7,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _unreadDot,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            const Positioned(
              left: 17,
              right: 17,
              bottom: 0,
              child: SizedBox(
                height: 1,
                child: ColoredBox(color: _divider),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "오후 3:20"
  static String _time(DateTime at) {
    final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
    final minute = at.minute.toString().padLeft(2, '0');
    return '${at.hour < 12 ? '오전' : '오후'} $hour:$minute';
  }
}

class _RetentionNote extends StatelessWidget {
  const _RetentionNote();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 24, 20, 29),
      child: Text(
        '7일 전 알림까지 확인할 수 있어요',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 14, height: 21 / 14, color: _meta),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '알림을 불러오지 못했어요',
            style: TextStyle(fontSize: 14, color: _meta),
          ),
          TextButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
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
