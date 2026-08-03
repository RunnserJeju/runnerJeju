import 'package:flutter/material.dart';

import '../../models/notice.dart';
import '../../services/service_locator.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/admin_only.dart';
import '../../widgets/async_view.dart';
import 'notice_create_screen.dart';

/// 홈: 공지사항.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<Notice>> _noticesFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _noticesFuture = Services.instance.notice.loadNotices();
  }

  Future<void> _refresh() async {
    setState(_load);
    await _noticesFuture.catchError((_) => <Notice>[]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Runners Jeju'),
        actions: [
          AdminOnly(
            child: IconButton(
              icon: const Icon(Icons.add_circle_outline_rounded),
              tooltip: '공지사항 작성',
              onPressed: () => Navigator.of(context)
                  .push(
                    MaterialPageRoute(builder: (_) => const NoticeCreateScreen()),
                  )
                  .then((_) => _refresh()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
          children: [
            const _SectionTitle('공지사항'),
            const SizedBox(height: 12),
            FutureBuilder<List<Notice>>(
              future: _noticesFuture,
              builder: (context, snapshot) => AsyncView<List<Notice>>(
                snapshot: snapshot,
                onRetry: _refresh,
                isEmpty: (notices) => notices.isEmpty,
                emptyTitle: '공지사항이 없어요',
                emptyIcon: Icons.campaign_outlined,
                builder: (context, notices) => Column(
                  children: [
                    for (final notice in notices) ...[
                      _NoticeCard(notice: notice),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.notice});

  final Notice notice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showDetail(context, notice),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.campaign_rounded,
                    size: 18,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      notice.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                Formatters.date(notice.createdAt),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                notice.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context, Notice notice) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            20 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  notice.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  Formatters.date(notice.createdAt),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 16),
                Text(notice.body, style: const TextStyle(height: 1.5)),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }
}
