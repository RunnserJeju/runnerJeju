import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../features/running_week/running_week.dart';
import '../../features/running_week/running_week_banner.dart';
import '../../features/running_week/running_week_screen.dart';
import '../../models/community_event.dart';
import '../../services/service_locator.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/section_title.dart';
import 'event_detail_screen.dart';

/// 커뮤니티 탭. 상단 고정 영역(지금은 러닝위크 배너) 아래 이벤트 섹션.
///
/// 상단 고정 영역은 [_pinned] 목록 하나다. 기능을 내릴 때는 그 항목만 뺀다.
class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key, required this.onOpenCourse});

  /// 러닝위크 빙고의 코스 칸을 누르면 그 코스 안내(러닝 탭)로 보낸다.
  final ValueChanged<String> onOpenCourse;

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  RunningWeek? _runningWeek;

  /// null이면 불러오는 중.
  List<CommunityEvent>? _events;
  Object? _eventsError;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() => Future.wait([_loadRunningWeek(), _loadEvents()]);

  Future<void> _loadEvents() async {
    try {
      final events = await Services.instance.event.loadEvents();
      if (mounted) {
        setState(() {
          _events = events;
          _eventsError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _eventsError = e);
    }
  }

  void _openEvent(CommunityEvent event) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => EventDetailScreen(event: event)));
  }

  /// 공개 중인 러닝위크. 실패하거나 없으면 배너를 숨긴다 — 커뮤니티 전체를 막을 일은 아니다.
  Future<void> _loadRunningWeek() async {
    RunningWeek? week;
    try {
      week = await Services.instance.runningWeek.loadCurrent();
    } catch (_) {
      week = null;
    }
    if (mounted) setState(() => _runningWeek = week);
  }

  Future<void> _openRunningWeek(RunningWeek week) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            RunningWeekScreen(week: week, onOpenCourse: widget.onOpenCourse),
      ),
    );
    // 참가 신청·스탬프로 상태가 바뀌었을 수 있다.
    if (mounted) _loadRunningWeek();
  }

  List<Widget> get _pinned => [
    if (_runningWeek case final week?)
      RunningWeekBanner(week: week, onTap: () => _openRunningWeek(week)),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('커뮤니티')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            for (final widget in _pinned)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                sliver: SliverToBoxAdapter(child: widget),
              ),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
              sliver: SliverToBoxAdapter(child: SectionTitle('이벤트')),
            ),
            ..._eventSlivers(),
          ],
        ),
      ),
    );
  }

  List<Widget> _eventSlivers() {
    final events = _events;
    final String? message = _eventsError != null
        ? '이벤트를 불러오지 못했어요. 당겨서 다시 시도해 주세요.'
        : events == null
        ? null
        : events.isEmpty
        ? '아직 진행 중인 이벤트가 없어요.'
        : null;

    if (events == null && _eventsError == null) {
      return const [
        SliverPadding(
          padding: EdgeInsets.only(top: 40),
          sliver: SliverToBoxAdapter(
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ];
    }
    if (message != null) {
      return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
          sliver: SliverToBoxAdapter(
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: AppColors.textSubtle,
              ),
            ),
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
        sliver: SliverList.separated(
          itemCount: events!.length,
          itemBuilder: (context, index) => _EventCard(
            event: events[index],
            onTap: () => _openEvent(events[index]),
          ),
          separatorBuilder: (_, _) => const SizedBox(height: 12),
        ),
      ),
    ];
  }
}

/// 이벤트 카드: 그림(있으면) + 제목 + 본문 두 줄 + 등록일.
class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, required this.onTap});

  final CommunityEvent event;
  final VoidCallback onTap;

  /// 목록에서는 링크 문법을 걷어 글자만 보인다. [신청하기](https://…) → 신청하기
  static final _markdownLink = RegExp(r'\[([^\]\n]+)\]\((https?://[^\s)]+)\)');

  @override
  Widget build(BuildContext context) {
    final imageUrl = event.imageUrl;
    final preview = event.body.replaceAllMapped(_markdownLink, (m) => m[1]!);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (imageUrl != null && imageUrl.isNotEmpty)
              AspectRatio(
                aspectRatio: 402 / 172,
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, _) =>
                      const ColoredBox(color: AppColors.paper),
                  errorWidget: (_, _, _) =>
                      const ColoredBox(color: AppColors.paper),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: AppColors.textSubtle,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    Formatters.date(event.createdAt),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
