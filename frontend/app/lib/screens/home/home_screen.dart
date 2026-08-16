import 'package:flutter/material.dart';

import '../../data/curated_partners.dart';
import '../../models/home_banner.dart';
import '../../models/notice.dart';
import '../../models/running_course.dart';
import '../../services/service_locator.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/admin_only.dart';
import '../../widgets/async_view.dart';
import '../../widgets/banner_carousel.dart';
import '../../widgets/course_recommend_card.dart';
import '../course/course_detail_screen.dart';
import 'banner_create_screen.dart';
import 'notice_create_screen.dart';

/// 홈: 배너 + 추천 코스 + 러닝 코스 큐레이션 + 공지사항.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<Notice>> _noticesFuture;
  late Future<List<HomeBanner>> _bannersFuture;
  late Future<List<RunningCourse>> _coursesFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _noticesFuture = Services.instance.notice.loadNotices();
    _bannersFuture = Services.instance.banner.loadBanners();
    _coursesFuture = Services.instance.course.loadCourses();
  }

  Future<void> _refresh() async {
    setState(_load);
    await _noticesFuture.catchError((_) => <Notice>[]);
    await _bannersFuture.catchError((_) => <HomeBanner>[]);
    await _coursesFuture.catchError((_) => <RunningCourse>[]);
  }

  void _openCourse(RunningCourse course) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CourseDetailScreen(courseId: course.id),
      ),
    );
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
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 120),
          children: [
            // ── 상단 배너 ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: FutureBuilder<List<HomeBanner>>(
                future: _bannersFuture,
                builder: (context, snapshot) {
                  final banners = snapshot.data ?? const <HomeBanner>[];
                  // 배너가 없으면 접지 않고 브랜드 히어로를 대신 띄운다.
                  if (banners.isEmpty) return const BrandHeroBanner();
                  return BannerCarousel(banners: banners);
                },
              ),
            ),
            const SizedBox(height: 28),

            // ── 추천 코스 ──
            FutureBuilder<List<RunningCourse>>(
              future: _coursesFuture,
              builder: (context, snapshot) {
                final courses = snapshot.data ?? const <RunningCourse>[];
                // 코스가 아직 없거나 로드 실패면 섹션을 조용히 접는다.
                if (courses.isEmpty) return const SizedBox.shrink();
                final recommended = courses.take(5).toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: _SectionTitle('추천 코스'),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 152,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: recommended.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          final course = recommended[index];
                          return CourseRecommendCard(
                            course: course,
                            onTap: () => _openCourse(course),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 28),
                  ],
                );
              },
            ),

            // ── 러닝 코스 큐레이션 (코스 × 제휴처) ──
            FutureBuilder<List<RunningCourse>>(
              future: _coursesFuture,
              builder: (context, snapshot) {
                final courses = snapshot.data ?? const <RunningCourse>[];
                if (courses.isEmpty) return const SizedBox.shrink();
                final picks = courses.take(4).toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: _SectionTitle('러닝 코스 큐레이션'),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 2, 20, 0),
                      child: Text(
                        '코스를 달리고 근처 제휴처에서 혜택까지',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF8A90A0),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 176,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: picks.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          final course = picks[index];
                          return _CurationCard(
                            course: course,
                            partner: partnerForIndex(index),
                            onTap: () => _openCourse(course),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 28),
                  ],
                );
              },
            ),

            // ── 공지사항 ──
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: _SectionTitle('공지사항'),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: FutureBuilder<List<Notice>>(
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

/// 러닝 코스 큐레이션 카드: 실제 코스(DB)에 더미 제휴처를 묶어 보여준다.
class _CurationCard extends StatelessWidget {
  const _CurationCard({
    required this.course,
    required this.partner,
    this.onTap,
  });

  final RunningCourse course;
  final CuratedPartner partner;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        partner.icon,
                        color: AppColors.accent,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            partner.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            partner.category,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF8A90A0),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  partner.benefit,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Color(0xFF3D4552),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.paper,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.place_rounded,
                        size: 14,
                        color: AppColors.accent,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '${course.name} 근처',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF3D4552),
                          ),
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
