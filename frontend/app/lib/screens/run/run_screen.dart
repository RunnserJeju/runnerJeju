import 'package:flutter/material.dart';

import '../../models/geo_point.dart';
import '../../models/running_course.dart';
import '../../services/location_service.dart';
import '../../services/run_tracker.dart';
import '../../services/service_locator.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/metric_tile.dart';
import '../../widgets/run_map_view.dart';
import 'run_result_screen.dart';

/// 러닝 화면: 지도에 실시간 경로를 그리고 거리/시간/페이스를 보여준다.
///
/// [course]를 주면 코스를 따라 달리는 러닝이 되고, 코스 경로가 함께 그려진다.
class RunScreen extends StatefulWidget {
  const RunScreen({super.key, this.course});

  final RunningCourse? course;

  @override
  State<RunScreen> createState() => _RunScreenState();
}

class _RunScreenState extends State<RunScreen> {
  RunTracker get _tracker => Services.instance.runTracker;

  GeoPoint? _initialCenter;

  @override
  void initState() {
    super.initState();
    _tracker.addListener(_onTrackerChanged);
    _resolveInitialCenter();
  }

  @override
  void dispose() {
    _tracker.removeListener(_onTrackerChanged);
    super.dispose();
  }

  void _onTrackerChanged() {
    if (mounted) setState(() {});
  }

  /// 러닝 시작 전에도 지도가 내 주변을 보여주도록 현재 위치를 한 번 조회한다.
  Future<void> _resolveInitialCenter() async {
    if (widget.course != null) return;

    final availability = await Services.instance.location.ensurePermission();
    if (!availability.isReady || !mounted) return;

    try {
      final position = await Services.instance.location.currentPosition();
      if (mounted) setState(() => _initialCenter = position);
    } catch (_) {
      // 위치를 못 잡아도 기본 중심으로 지도를 띄운다.
    }
  }

  Future<void> _start() async {
    final availability = await _tracker.start(course: widget.course);
    if (availability.isReady || !mounted) return;

    _showPermissionSheet(availability);
  }

  void _showPermissionSheet(LocationAvailability availability) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.location_off_rounded, size: 32),
              const SizedBox(height: 12),
              Text(
                availability.message,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              const Text('러닝 경로를 기록하려면 위치 권한이 필요해요.'),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  if (availability == LocationAvailability.serviceDisabled) {
                    Services.instance.location.openLocationSettings();
                  } else {
                    Services.instance.location.openAppSettings();
                  }
                },
                child: const Text('설정 열기'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _finish() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('러닝을 종료할까요?'),
        content: const Text('기록을 저장하고 결과 화면으로 이동해요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('계속 달리기'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('종료'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    _tracker.finish();
    final record = _tracker.buildRecord();
    if (record == null || !mounted) return;

    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => RunResultScreen(record: record)),
    );
  }

  /// 러닝 중에는 뒤로가기로 화면을 벗어나지 못하게 막는다.
  Future<void> _handlePop(bool didPop) async {
    if (didPop) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('러닝 중이에요. 종료하려면 정지 버튼을 눌러주세요.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tracker = _tracker;
    final isActive = tracker.isActive;

    return PopScope(
      canPop: !isActive,
      onPopInvokedWithResult: (didPop, _) => _handlePop(didPop),
      child: Scaffold(
        backgroundColor: AppColors.ink,
        body: Stack(
          children: [
            Positioned.fill(
              child: RunMapView(
                coursePath: widget.course?.path ?? const [],
                runPath: tracker.path,
                currentPosition: tracker.currentPosition,
                initialCenter: _initialCenter,
                followCurrentPosition: tracker.status == RunStatus.running,
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  _TopBar(
                    course: widget.course,
                    progress: tracker.courseProgress,
                    onClose: isActive ? null : () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  _ControlPanel(
                    tracker: tracker,
                    onStart: _start,
                    onPause: tracker.pause,
                    onResume: tracker.resume,
                    onFinish: _finish,
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

class _TopBar extends StatelessWidget {
  const _TopBar({required this.course, required this.progress, this.onClose});

  final RunningCourse? course;
  final double? progress;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    course?.name ?? '자유 러닝',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  if (progress != null) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        backgroundColor: const Color(0xFFE8EBEF),
                        valueColor: const AlwaysStoppedAnimation(AppColors.ink),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onClose != null)
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
              ),
          ],
        ),
      ),
    );
  }
}

/// 하단 지표 + 시작/일시정지/종료 컨트롤.
class _ControlPanel extends StatelessWidget {
  const _ControlPanel({
    required this.tracker,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onFinish,
  });

  final RunTracker tracker;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: MetricTile(
              label: '거리 (KM)',
              value: Formatters.distanceKm(tracker.distanceMeters),
              emphasized: true,
              alignment: CrossAxisAlignment.center,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              MetricTile(
                label: '시간',
                value: Formatters.duration(tracker.elapsed),
                alignment: CrossAxisAlignment.center,
              ),
              MetricTile(
                label: '평균 페이스',
                value: Formatters.pace(tracker.paceSecondsPerKm),
                alignment: CrossAxisAlignment.center,
              ),
            ],
          ),
          if (tracker.hasReachedCourseGoal) ...[
            const SizedBox(height: 16),
            const _GoalReachedBanner(),
          ],
          const SizedBox(height: 24),
          _Controls(
            tracker: tracker,
            onStart: onStart,
            onPause: onPause,
            onResume: onResume,
            onFinish: onFinish,
          ),
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.tracker,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onFinish,
  });

  final RunTracker tracker;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return switch (tracker.status) {
      RunStatus.idle || RunStatus.finished => FilledButton(
        onPressed: onStart,
        child: const Text('러닝 시작'),
      ),
      RunStatus.running => Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onPause,
              icon: const Icon(Icons.pause_rounded),
              label: const Text('일시정지'),
            ),
          ),
        ],
      ),
      RunStatus.paused => Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onResume,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('이어서'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: onFinish,
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              icon: const Icon(Icons.stop_rounded),
              label: const Text('종료'),
            ),
          ),
        ],
      ),
    };
  }
}

class _GoalReachedBanner extends StatelessWidget {
  const _GoalReachedBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        children: [
          Icon(Icons.flag_rounded, size: 18, color: AppColors.ink),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '완주 지점에 도착했어요! 종료하면 스탬프를 받아요',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
