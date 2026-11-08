import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/course_partner.dart';
import '../models/run_record.dart';
import '../models/user_log.dart';
import '../services/exit_info.dart';
import '../services/run_tracker.dart';
import '../services/service_locator.dart';
import '../services/user_log_service.dart';
import '../theme/app_theme.dart';
import 'community/community_screen.dart';
import 'home/home_screen.dart';
import 'profile/profile_screen.dart';
import 'run/run_result_screen.dart';
import 'running/running_screen.dart';
import 'stamp/stamp_screen.dart';

/// 하단 탭으로 구성된 앱 뼈대.
///
/// 예전에는 탭 사이에 러닝 시작 FAB가 하나 더 떠 있었다. 러닝은 '러닝'
/// 탭([RunningScreen])이 지도째로 맡는다 — 코스를 고르는 것도, 코스 없이 바로
/// 달리는 것도 그 안에서 끝나므로 버튼을 따로 띄울 이유가 없다.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _communityTab = 1;
  static const _runningTab = 2;

  /// 다른 탭에서 코스를 열 때 러닝 탭의 선택을 바깥에서 움직이려고 둔다.
  /// 러닝 탭은 IndexedStack 안에서 계속 살아 있어 State가 늘 붙어 있다.
  final GlobalKey<RunningScreenState> _runningKey = GlobalKey();
  final GlobalKey<CommunityScreenState> _communityKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    Services.instance.runRecovery.begin();
    WidgetsBinding.instance.addPostFrameCallback((_) => _recoverPendingRun());
  }

  /// 지난 실행이 러닝 중이거나 업로드 전에 죽었으면 일지가 남아 있다. 묻지 않고
  /// 죽기 전 마지막 점까지를 기록으로 올리고 결과 화면으로 간다.
  Future<void> _recoverPendingRun() async {
    final recovery = Services.instance.runRecovery;
    final journal = Services.instance.runJournal;
    final record = await journal.read();
    if (record == null || !_canRecover) {
      recovery.settle(false);
      return;
    }

    final exit = await lastExitInfo();
    final detail = {
      LogKeys.courseId: ?record.courseId,
      LogKeys.distanceM: record.distanceMeters.round(),
      LogKeys.elapsedSec: record.duration.inSeconds,
      LogKeys.exit: ?exit,
    };
    // 러닝 화면의 종료와 같은 기준: 너무 짧으면 기록이 아니다.
    if (record.isTooShort) {
      writeLog(
        LogName.runAbandon,
        detail: {LogKeys.reason: 'app_killed', ...detail},
      );
      unawaited(journal.discard());
      recovery.settle(false);
      return;
    }
    // 응답만 못 받고 서버엔 들어갔을 수 있어 같은 시작 시각 기록이 있으면 다시 올리지 않는다.
    // 이어달리기 구간은 서버가 구간 id로 중복을 걸러 주므로 그냥 다시 올린다.
    final uploaded = !record.isContinuation && await _alreadyUploaded(record);
    if (uploaded) unawaited(journal.discard());
    if (uploaded || !mounted || !_canRecover) {
      recovery.settle(false);
      return;
    }

    writeLog(LogName.runRecover, detail: detail);
    recovery.settle(true);
    unawaited(Services.instance.runSubmission.submit(record));
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RunResultScreen(record: record)),
    );
  }

  /// 읽는 사이 새 러닝이 시작됐으면 일지는 이미 그 러닝 것이다. 건드리지 않는다.
  bool get _canRecover =>
      mounted && Services.instance.runTracker.status == RunStatus.idle;

  Future<bool> _alreadyUploaded(RunRecord record) async {
    try {
      final records = await Services.instance.run.loadMyRecords(
        limit: 5,
        since: record.startedAt.subtract(const Duration(minutes: 1)),
        until: record.startedAt.add(const Duration(minutes: 1)),
        withPath: false,
      );
      return records.any(
        (r) =>
            r.startedAt.difference(record.startedAt).abs() <
            const Duration(seconds: 2),
      );
    } catch (_) {
      return false; // 확인을 못 하면 올린다. 중복이 유실보다 낫다.
    }
  }

  void _openCourse(String courseId, LogSource source) {
    setState(() => _index = _runningTab);
    _runningKey.currentState?.openCourse(courseId, source: source);
  }

  /// 커뮤니티 탭으로 옮겨 러닝위크를 연다. 공지 버튼도 이걸 쓴다.
  /// 빙고판에서 연 코스를 보다가 돌아갈 때는, 빙고판이 코스를 열 때 이미 닫혔으므로
  /// (RunningWeekScreen._openCell의 popUntil) 커뮤니티 탭으로 옮겨 배너를 누른
  /// 것과 똑같이 다시 연다 — 스택에는 늘 빙고판 한 장만 쌓인다.
  void _returnToRunningWeek() {
    setState(() => _index = _communityTab);
    _communityKey.currentState?.openRunningWeek();
  }

  /// 러닝 탭으로 옮기고 협력업체 모드에서 그 업체를 고른 상태로 연다.
  void _openPartner(CoursePartner partner, LogSource source) {
    setState(() => _index = _runningTab);
    _runningKey.currentState?.openPartner(partner, source: source);
  }

  static const _items = <({IconData? icon, String? asset, String label})>[
    (icon: Icons.home, asset: null, label: '홈'),
    (icon: Icons.groups, asset: null, label: '커뮤니티'),
    (icon: null, asset: 'assets/icons/nav_run.svg', label: '러닝'),
    (icon: Icons.star, asset: null, label: '스탬프'),
    (icon: Icons.person, asset: null, label: '마이페이지'),
  ];

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[
      HomeScreen(
        onShowMap: () => setState(() => _index = _runningTab),
        onOpenCourse: (courseId) => _openCourse(courseId, LogSource.home),
        onOpenPartner: (partner) => _openPartner(partner, LogSource.home),
        onOpenRunningWeek: _returnToRunningWeek,
      ),
      CommunityScreen(
        key: _communityKey,
        onOpenCourse: (courseId) =>
            _openCourse(courseId, LogSource.runningWeek),
      ),
      RunningScreen(
        key: _runningKey,
        onReturnToRunningWeek: _returnToRunningWeek,
      ),
      const StampScreen(),
      ProfileScreen(onOpenCourse: _openCourse),
    ];

    return Scaffold(
      // 탭 안에 지도(카카오맵 PlatformView)를 쓰는 화면이 있다(RunningScreen).
      // 이 바깥 Scaffold가 키보드에 맞춰 body를 리사이즈하면 그 안의
      // IndexedStack 전체가 줄어들면서 지도가 함께 리사이즈돼 렌더링이
      // 깨진다. 리사이즈 대신 키보드가 위에 그냥 덮이게 둔다.
      resizeToAvoidBottomInset: false,
      body: IndexedStack(index: _index, children: tabs),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.lineSoft)),
        ),
        child: BottomAppBar(
          color: Colors.transparent,
          elevation: 0,
          height: 68,
          padding: EdgeInsets.zero,
          child: Row(
            children: [
              for (final (index, item) in _items.indexed)
                Expanded(
                  child: _NavItem(
                    icon: item.icon,
                    asset: item.asset,
                    label: item.label,
                    selected: _index == index,
                    onTap: () => setState(() => _index = index),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.asset,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  /// 머티리얼 아이콘 또는 SVG 에셋 중 하나만 쓴다.
  final IconData? icon;
  final String? asset;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accent : AppColors.muted;

    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (asset case final asset?)
            SvgPicture.asset(
              asset,
              width: 22,
              height: 22,
              colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
            )
          else
            Icon(icon, color: color, size: 22),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
