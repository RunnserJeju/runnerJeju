import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../data/curated_partners.dart';
import '../../models/notice.dart';
import '../../models/running_course.dart';
import '../../services/service_locator.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/banner_carousel.dart';
import '../../widgets/course_recommend_card.dart';
import '../course/course_detail_screen.dart';
import '../notification/notification_screen.dart';
import '../../widgets/section_title.dart';

/// 홈: 배너(이미지 있는 공지) + 추천 코스 + 러닝 코스 큐레이션.
///
/// 공지 목록은 홈에 따로 펼치지 않는다 — 배너와 겹쳐서다. 헤더의 벨은 공지가
/// 아니라 알림 화면([NotificationScreen])을 연다.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onShowMap});

  /// '지도로 보기'를 눌렀을 때. 러닝 탭으로 옮겨 준다.
  final VoidCallback onShowMap;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<Notice>> _noticesFuture;
  late Future<List<RunningCourse>> _coursesFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _noticesFuture = Services.instance.notice.loadNotices();
    _coursesFuture = Services.instance.course.loadCourses();
  }

  Future<void> _refresh() async {
    setState(_load);
    await _noticesFuture.catchError((_) => <Notice>[]);
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
      appBar: AppBar(
        // 텍스트 대신 RJC 로고 마크. 시안 크기(71x27) 그대로 높이만 지정하고
        // 가로는 비율에 맡긴다.
        title: SvgPicture.asset(
          'assets/icons/rjc_logo.svg',
          height: 27,
          semanticsLabel: 'Runners Jeju',
        ),
        titleSpacing: 16,
        shape: const Border(
          bottom: BorderSide(color: AppColors.line, width: 0.5),
        ),
        actions: [
          _BellButton(
            // 아직 알림을 만들어 보내는 곳이 없어 읽지 않은 알림도 없다.
            hasUnread: false,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotificationScreen()),
            ),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            // ── 상단 배너 (이미지 있는 공지) ──
            FutureBuilder<List<Notice>>(
              future: _noticesFuture,
              builder: (context, snapshot) {
                final banners = (snapshot.data ?? const <Notice>[])
                    .where((n) => n.hasImage)
                    .toList();
                // 배너가 없으면 접지 않고 브랜드 히어로를 대신 띄운다.
                if (banners.isEmpty) return const BrandHeroBanner();
                return BannerCarousel(
                  banners: banners,
                  onTap: (notice) => showNoticeDetail(context, notice),
                );
              },
            ),

            // ── 추천 코스 ──
            FutureBuilder<List<RunningCourse>>(
              future: _coursesFuture,
              builder: (context, snapshot) {
                final courses = snapshot.data ?? const <RunningCourse>[];
                // 코스가 아직 없거나 로드 실패면 섹션을 조용히 접는다.
                if (courses.isEmpty) return const SizedBox.shrink();
                final recommended = courses.take(5).toList();
                return DecoratedBox(
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: AppColors.line, width: 0.5),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const SectionTitle('추천 코스', small: true),
                            _LinkButton(
                              label: '지도로 보기',
                              onTap: widget.onShowMap,
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 240,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
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
                      const SizedBox(height: 20),
                    ],
                  ),
                );
              },
            ),

            // ── 러닝 코스 큐레이션 (코스 × 제휴처) ──
            FutureBuilder<List<RunningCourse>>(
              future: _coursesFuture,
              builder: (context, snapshot) {
                final courses = snapshot.data ?? const <RunningCourse>[];
                if (courses.isEmpty) return const SizedBox.shrink();
                final picks = courses.take(kCuratedPartners.length).toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SectionTitle('러닝 코스 큐레이션', small: true),
                          SizedBox(height: 2),
                          Text(
                            '코스를 달리고 근처 제휴처에서 혜택까지',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    for (final (index, course) in picks.indexed)
                      _CurationItem(
                        course: course,
                        partner: partnerForIndex(index),
                        isLast: index == picks.length - 1,
                        onTap: () => _openCourse(course),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 섹션 헤더 우측의 작은 텍스트 링크. 예) '지도로 보기 ›'
class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right, size: 12, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

/// 헤더 알림 벨. 읽지 않은 알림이 있으면 우상단에 빨간 점을 찍는다.
class _BellButton extends StatelessWidget {
  const _BellButton({required this.hasUnread, required this.onTap});

  final bool hasUnread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            SvgPicture.asset('assets/icons/bell.svg', width: 20, height: 20),
            if (hasUnread)
              Positioned(
                top: -2,
                right: -1,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD92E16),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 러닝 코스 큐레이션 한 줄: 실제 코스(DB)에 더미 제휴처를 묶어 보여준다.
class _CurationItem extends StatelessWidget {
  const _CurationItem({
    required this.course,
    required this.partner,
    required this.isLast,
    this.onTap,
  });

  final RunningCourse course;
  final CuratedPartner partner;

  /// 마지막 줄은 아래 구분선을 긋지 않는다.
  final bool isLast;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : const Border(
                  bottom: BorderSide(color: AppColors.lineSoft, width: 0.5),
                ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: partner.tint.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SvgPicture.asset(
                partner.iconAsset,
                width: 22,
                height: 22,
                colorFilter: ColorFilter.mode(partner.tint, BlendMode.srcIn),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: Text(
                          partner.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        partner.category,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    partner.benefit,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.ink,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      SvgPicture.asset(
                        'assets/icons/pin.svg',
                        width: 12,
                        height: 12,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '${course.name} 근처',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            const Icon(Icons.chevron_right, size: 16, color: AppColors.line),
          ],
        ),
      ),
    );
  }
}

/// 공지 상세 바텀시트. 배너를 누르면 연다.
void showNoticeDetail(BuildContext context, Notice notice) {
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
              if (notice.hasImage) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: AspectRatio(
                    aspectRatio: 3 / 1,
                    child: CachedNetworkImage(
                      imageUrl: notice.imageUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
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
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted,
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
