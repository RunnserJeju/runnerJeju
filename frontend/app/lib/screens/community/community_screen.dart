import 'package:flutter/material.dart';

import '../../features/running_week/running_week.dart';
import '../../features/running_week/running_week_banner.dart';
import '../../features/running_week/running_week_screen.dart';
import '../../models/running_program.dart';
import '../../services/service_locator.dart';
import '../../theme/app_theme.dart';
import '../../widgets/async_view.dart';
import '../../widgets/section_title.dart';

/// 커뮤니티 탭. 상단 고정 영역(지금은 러닝위크 배너) 아래 러닝 프로그램 섹션.
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
  late Future<List<RunningProgram>> _future;
  RunningWeek? _runningWeek;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = Services.instance.program.loadPrograms();
    _loadRunningWeek();
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

  Future<void> _refresh() async {
    setState(_load);
    await _future.catchError((_) => <RunningProgram>[]);
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
        child: FutureBuilder<List<RunningProgram>>(
          future: _future,
          builder: (context, snapshot) => AsyncView<List<RunningProgram>>(
            snapshot: snapshot,
            onRetry: _refresh,
            // 프로그램이 비어도 상단 고정 영역은 보여야 해서 빈 상태는 목록 안에서 그린다.
            builder: (context, programs) =>
                _ProgramList(pinned: _pinned, programs: programs),
          ),
        ),
      ),
    );
  }
}

class _ProgramList extends StatelessWidget {
  const _ProgramList({required this.pinned, required this.programs});

  final List<Widget> pinned;
  final List<RunningProgram> programs;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        for (final widget in pinned)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            sliver: SliverToBoxAdapter(child: widget),
          ),
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
          sliver: SliverToBoxAdapter(child: SectionTitle('러닝 프로그램')),
        ),
        if (programs.isEmpty)
          const SliverPadding(
            padding: EdgeInsets.fromLTRB(20, 24, 20, 120),
            sliver: SliverToBoxAdapter(
              child: Text(
                '아직 열린 러닝 프로그램이 없어요.\n곧 다양한 프로그램이 열릴 예정이에요.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: AppColors.textSubtle,
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
            sliver: SliverList.separated(
              itemCount: programs.length,
              itemBuilder: (context, index) =>
                  _ProgramCard(program: programs[index]),
              separatorBuilder: (_, _) => const SizedBox(height: 12),
            ),
          ),
      ],
    );
  }
}

class _ProgramCard extends StatelessWidget {
  const _ProgramCard({required this.program});

  final RunningProgram program;

  @override
  Widget build(BuildContext context) {
    final period = program.periodLabel;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            program.title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: AppColors.ink,
            ),
          ),
          if (program.description != null) ...[
            const SizedBox(height: 6),
            Text(
              program.description!,
              style: const TextStyle(fontSize: 13, color: AppColors.inkSoft),
            ),
          ],
          if (period != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.event_rounded,
                  size: 15,
                  color: AppColors.accent,
                ),
                const SizedBox(width: 6),
                Text(
                  period,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkSoft,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
