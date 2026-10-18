import 'package:flutter/material.dart';

import '../../features/running_week/running_week.dart';
import '../../features/running_week/running_week_banner.dart';
import '../../features/running_week/running_week_screen.dart';
import '../../services/service_locator.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_title.dart';

/// 커뮤니티 탭. 상단 고정 영역(지금은 러닝위크 배너) 아래 이벤트 섹션.
///
/// 상단 고정 영역은 [_pinned] 목록 하나다. 기능을 내릴 때는 그 항목만 뺀다.
/// 이벤트 목록은 아직 서버가 없어 빈 안내만 보인다(#70).
class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key, required this.onOpenCourse});

  /// 러닝위크 빙고의 코스 칸을 누르면 그 코스 안내(러닝 탭)로 보낸다.
  final ValueChanged<String> onOpenCourse;

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  RunningWeek? _runningWeek;

  @override
  void initState() {
    super.initState();
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
        onRefresh: _loadRunningWeek,
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
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(20, 24, 20, 120),
              sliver: SliverToBoxAdapter(
                child: Text(
                  '아직 진행 중인 이벤트가 없어요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: AppColors.textSubtle,
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
