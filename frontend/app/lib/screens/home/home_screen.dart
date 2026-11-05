import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/course_partner.dart';
import '../../models/home_curation.dart';
import '../../models/notice.dart';
import '../../models/running_course.dart';
import '../../models/user_log.dart';
import '../../services/service_locator.dart';
import '../../services/user_log_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/banner_carousel.dart';
import '../../widgets/course_recommend_card.dart';
import '../../widgets/partner_card.dart';
import '../notification/notification_screen.dart';
import '../../widgets/section_title.dart';

/// 홈: 배너(이미지 있는 공지) + 러닝 코스 큐레이션 + 추천 협력 업체.
///
/// 두 섹션에 무엇을 어떤 순서로 띄울지는 운영 웹 '홈 구성'에서 고른다
/// ([HomeCuration]). 고른 게 없으면 그 섹션은 접힌다.
///
/// 공지 목록은 홈에 따로 펼치지 않는다 — 배너와 겹쳐서다. 헤더의 벨은 공지가
/// 아니라 알림 화면([NotificationScreen])을 연다.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.onShowMap,
    required this.onOpenCourse,
    required this.onOpenPartner,
    required this.onOpenRunningWeek,
  });

  /// '지도로 보기'를 눌렀을 때. 러닝 탭으로 옮겨 준다.
  final VoidCallback onShowMap;

  /// 코스 카드를 눌렀을 때. 러닝 탭으로 옮겨 그 코스를 고른 상태로 연다.
  final ValueChanged<String> onOpenCourse;

  /// 추천 협력 업체 줄을 눌렀을 때. 러닝 탭으로 옮겨 그 업체 핀을 고른 상태로 연다.
  final ValueChanged<CoursePartner> onOpenPartner;

  /// 러닝위크로 연결된 공지의 버튼을 눌렀을 때. 커뮤니티 탭으로 옮겨 러닝위크를 연다.
  final VoidCallback onOpenRunningWeek;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// 실행 시 노출 팝업을 이 앱 실행에서 이미 띄웠는지. 탭을 오가거나 새로고침해도 다시 안 뜬다.
  static bool _launchNoticeShown = false;

  late Future<List<Notice>> _noticesFuture;
  late Future<List<RunningCourse>> _curatedCoursesFuture;
  late Future<List<CoursePartner>> _featuredPartnersFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _noticesFuture = Services.instance.notice.loadNotices();
    _showLaunchNotice();
    final curation = Services.instance.home.loadCuration();
    _curatedCoursesFuture = _pick(
      Services.instance.course.loadCourses(),
      curation.then((c) => [for (final item in c.courses) item.id]),
      (course) => course.id,
    );
    _featuredPartnersFuture = _pick(
      Services.instance.partner.loadPartners(),
      curation.then((c) => [for (final item in c.partners) item.id]),
      (partner) => partner.id,
    );
  }

  /// '앱 실행 시 노출'이 켜진 공지가 있으면 가장 최근 것 하나를 팝업으로 띄운다. 실행당 한 번.
  /// 공지를 못 불러왔으면 조용히 넘어간다.
  void _showLaunchNotice() {
    if (_launchNoticeShown) return;
    _noticesFuture
        .then((notices) async {
          if (_launchNoticeShown) return;
          // 지난 러닝 복구 팝업·결과 화면이 뜨는 실행이면 공지는 겹쳐 띄우지 않는다.
          if (await Services.instance.runRecovery.takesOverLaunch) return;
          // 켜진 공지 중 가장 최근 것. '다시 보지 않기'를 누른 공지는 건너뛴다.
          Notice? launch;
          for (final notice in notices.where((n) => n.showOnLaunch)) {
            if (!await Services.instance.notice.isLaunchDismissed(notice.id)) {
              launch = notice;
              break;
            }
          }
          if (launch == null || _launchNoticeShown || !mounted) return;
          _launchNoticeShown = true;
          final shown = launch;
          showNoticeDetail(
            context,
            shown,
            onOpenRunningWeek: widget.onOpenRunningWeek,
            onDismissForever: () =>
                Services.instance.notice.dismissLaunch(shown.id),
          );
        })
        .catchError((_) {});
  }

  /// [items] 중 [ids]에 든 것만 그 순서대로. 목록에 없는 id(비공개로 바뀐 코스 등)는
  /// 건너뛴다. 둘 중 하나라도 실패하면 실패라 섹션이 접힌다.
  static Future<List<T>> _pick<T>(
    Future<List<T>> items,
    Future<List<String>> ids,
    String Function(T) idOf,
  ) async {
    final (loaded, picked) = await (items, ids).wait;
    final byId = {for (final item in loaded) idOf(item): item};
    return [for (final id in picked) ?byId[id]];
  }

  Future<void> _refresh() async {
    setState(_load);
    await _noticesFuture.catchError((_) => <Notice>[]);
    await _curatedCoursesFuture.catchError((_) => <RunningCourse>[]);
    await _featuredPartnersFuture.catchError((_) => <CoursePartner>[]);
  }

  /// [section]은 홈의 어느 구역에서 눌렀는지 — 로그용. 지금은 코스 큐레이션
  /// 섹션('recommended', 옛 '추천 코스' 시절 값을 그대로 쓴다)뿐이다.
  void _openCourse(String courseId, {required String section, int? position}) {
    writeLog(
      LogName.homeCourseClick,
      detail: {
        LogKeys.courseId: courseId,
        LogKeys.section: section,
        LogKeys.position: ?position,
      },
    );
    widget.onOpenCourse(courseId);
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
                  onTap: (notice) {
                    writeLog(
                      LogName.bannerClick,
                      detail: {
                        LogKeys.noticeId: notice.id,
                        LogKeys.position: banners.indexOf(notice),
                      },
                    );
                    showNoticeDetail(
                      context,
                      notice,
                      onOpenRunningWeek: widget.onOpenRunningWeek,
                    );
                  },
                );
              },
            ),

            // ── 러닝 코스 큐레이션 ──
            FutureBuilder<List<RunningCourse>>(
              future: _curatedCoursesFuture,
              builder: (context, snapshot) {
                // 운영 웹 '홈 구성'에서 고른 코스(고른 순서대로).
                final recommended = snapshot.data ?? const <RunningCourse>[];
                // 고른 코스가 없거나 로드 실패면 섹션을 조용히 접는다.
                if (recommended.isEmpty) return const SizedBox.shrink();
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
                            const SectionTitle('러닝 코스 큐레이션', small: true),
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
                              onTap: () => _openCourse(
                                course.id,
                                section: 'recommended',
                                position: index,
                              ),
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

            // ── 추천 협력 업체 ──
            FutureBuilder<List<CoursePartner>>(
              future: _featuredPartnersFuture,
              builder: (context, snapshot) {
                // 운영 웹 '홈 구성'에서 고른 업체(고른 순서대로).
                final picks = snapshot.data ?? const <CoursePartner>[];
                // 고른 업체가 없거나 로드 실패면 섹션을 조용히 접는다.
                if (picks.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SectionTitle('추천 협력 업체', small: true),
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
                    for (final (index, partner) in picks.indexed)
                      _PartnerItem(
                        partner: partner,
                        course: partner.courses.firstOrNull,
                        isLast: index == picks.length - 1,
                        // 로그(partner_preview_open, source=home)는 러닝 탭이
                        // 업체를 고를 때 남긴다.
                        onTap: () => widget.onOpenPartner(partner),
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

/// 추천 협력 업체 한 줄: 협력업체와 그 업체가 연결된 코스(운영 웹에서 연결).
/// 누르면 러닝 탭에서 그 업체 핀을 고른 상태로 연다. 업체가 여러 코스에 걸려 있으면
/// "근처" 표기에는 첫 코스(이름순)를 쓰고, 연결된 코스가 없으면 그 줄을 뺀다.
class _PartnerItem extends StatelessWidget {
  const _PartnerItem({
    required this.partner,
    required this.course,
    required this.isLast,
    this.onTap,
  });

  final CoursePartner partner;
  final PartnerCourseRef? course;

  /// 마지막 줄은 아래 구분선을 긋지 않는다.
  final bool isLast;
  final VoidCallback? onTap;

  static const double _thumbnailSize = 72;

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
            // 목록·상세와 같은 썸네일(없으면 업종 타일). 한 줄이 세 줄 글이라 72로.
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox.square(
                dimension: _thumbnailSize,
                child: PartnerThumbnail(partner: partner, size: _thumbnailSize),
              ),
            ),
            const SizedBox(width: 14),
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
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        partner.category.label,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                  if (partner.benefit != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      partner.benefit!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.ink,
                        height: 1.4,
                      ),
                    ),
                  ],
                  if (course case final course?) ...[
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
                              fontSize: 11,
                              color: AppColors.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
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

/// 공지 상세 팝업. 배너를 누르거나 앱 실행 시 노출 공지로 연다. 링크가 있으면 본문 아래에 버튼.
/// [onDismissForever]를 주면(실행 시 팝업) 카드 아래에 '다시 보지 않기 | 닫기'를 둔다.
/// 직접 연 공지는 버튼 줄 없이 바깥을 눌러 닫는다.
void showNoticeDetail(
  BuildContext context,
  Notice notice, {
  required VoidCallback onOpenRunningWeek,
  VoidCallback? onDismissForever,
}) {
  showDialog<void>(
    context: context,
    builder: (context) {
      // 팝업 카드와 그 아래 버튼 줄을 한 묶음으로 가운데에 띄운다. 버튼은 카드 밖, 어두운 배경 위.
      return Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
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
                                errorWidget: (_, _, _) =>
                                    const SizedBox.shrink(),
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
                        if (notice.link case final link?) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: () async {
                                // 시트를 닫은 뒤엔 이 context를 못 쓴다 — 미리 잡아 둔다.
                                final messenger = ScaffoldMessenger.of(context);
                                Navigator.of(context).pop();
                                switch (link) {
                                  case RunningWeekLink():
                                    onOpenRunningWeek();
                                  case ExternalLink(:final uri):
                                    final opened = await launchUrl(
                                      uri,
                                      mode: LaunchMode.externalApplication,
                                    );
                                    if (!opened) {
                                      messenger.showSnackBar(
                                        const SnackBar(
                                          content: Text('링크를 열지 못했어요.'),
                                        ),
                                      );
                                    }
                                }
                              },
                              child: Text(
                                notice.linkLabel ?? link.defaultLabel,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              // 실행 시 팝업일 때만 버튼 줄을 둔다. 직접 연 공지는 바깥을 눌러 닫는다.
              if (onDismissForever != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () {
                          onDismissForever();
                          Navigator.of(context).pop();
                        },
                        child: const Text('다시 보지 않기'),
                      ),
                    ),
                    Container(width: 1, height: 14, color: Colors.white54),
                    Expanded(
                      child: TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('닫기'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}
