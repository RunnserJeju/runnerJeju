import 'package:flutter/material.dart';

import '../../models/home_banner.dart';
import '../../models/notice.dart';
import '../../services/service_locator.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/admin_only.dart';
import '../../widgets/async_view.dart';
import '../../widgets/banner_carousel.dart';
import 'banner_create_screen.dart';
import 'notice_create_screen.dart';

/// 홈: 배너 + 공지사항.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<Notice>> _noticesFuture;
  late Future<List<HomeBanner>> _bannersFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _noticesFuture = Services.instance.notice.loadNotices();
    _bannersFuture = Services.instance.banner.loadBanners();
  }

  Future<void> _refresh() async {
    setState(_load);
    await _noticesFuture.catchError((_) => <Notice>[]);
    await _bannersFuture.catchError((_) => <HomeBanner>[]);
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
              icon: const Icon(Icons.add_photo_alternate_outlined),
              tooltip: '배너 등록',
              onPressed: () => Navigator.of(context)
                  .push(
                    MaterialPageRoute(builder: (_) => const BannerCreateScreen()),
                  )
                  .then((_) => _refresh()),
            ),
          ),
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
            // 배너가 없으면 섹션 자체를 접는다 — 공지사항과 달리 배너는 장식용이라
            // "배너가 없어요" 같은 빈 상태를 굳이 보여줄 필요가 없다.
            FutureBuilder<List<HomeBanner>>(
              future: _bannersFuture,
              builder: (context, snapshot) {
                final banners = snapshot.data ?? const <HomeBanner>[];
                if (banners.isEmpty) return const SizedBox.shrink();
                return Column(
                  children: [
                    BannerCarousel(banners: banners),
                    const SizedBox(height: 24),
                  ],
                );
              },
            ),
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
