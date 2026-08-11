import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/geo_point.dart';
import '../../models/running_course.dart';
import '../../services/location_service.dart';
import '../../services/run_tracker.dart';
import '../../services/service_locator.dart';
import '../../test/simulation_launcher.dart';
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

  /// [source]를 주면 실제 GPS 대신 그 위치원으로 달린다(디버그 빌드의 시뮬레이션).
  Future<void> _start({LocationService? source}) async {
    final availability = await _tracker.start(
      course: widget.course,
      source: source,
    );
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
      builder: (dialogContext) {
        // 크기와 모양은 같게 두고 색으로만 구분한다. 
        Widget action(String label, bool result, {Color? background}) =>
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: background,
                  minimumSize: const Size.fromHeight(44),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onPressed: () => Navigator.of(dialogContext).pop(result),
                child: Text(label, maxLines: 1),
              ),
            );

        return AlertDialog(
          title: const Text('러닝을 종료할까요?'),
          content: const Text('기록을 저장하고 결과 화면으로 이동해요.'),
          actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
          actions: [
            Row(
              children: [
                action('계속 달리기', false),
                const SizedBox(width: 12),
                action('종료', true, background: AppColors.danger),
              ],
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    await _completeRun();
  }

  /// 러닝을 끝내고 결과 화면으로 넘어간다. 수동 종료(확인 다이얼로그 뒤)와
  /// 완주 자동 종료가 공유하는 경로다.
  Future<void> _completeRun() async {
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
                    onClose: isActive
                        ? null
                        : () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  _ControlPanel(
                    tracker: tracker,
                    coursePath: widget.course?.path ?? const [],
                    onStart: _start,
                    onStartSimulation: (source) => _start(source: source),
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
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 6,
                              backgroundColor: const Color(0xFFE8EBEF),
                              valueColor: const AlwaysStoppedAnimation(
                                AppColors.ink,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 커버리지 숫자. 바만으로는 얼마나 달렸는지 읽기 어렵다.
                        Text(
                          '코스 ${(progress! * 100).round()}%',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
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
    required this.coursePath,
    required this.onStart,
    required this.onStartSimulation,
    required this.onPause,
    required this.onResume,
    required this.onFinish,
  });

  final RunTracker tracker;
  final List<GeoPoint> coursePath;
  final VoidCallback onStart;
  final void Function(LocationService source) onStartSimulation;
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
          const SizedBox(height: 24),
          _Controls(
            tracker: tracker,
            coursePath: coursePath,
            onStart: onStart,
            onStartSimulation: onStartSimulation,
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
    required this.coursePath,
    required this.onStart,
    required this.onStartSimulation,
    required this.onPause,
    required this.onResume,
    required this.onFinish,
  });

  final RunTracker tracker;
  final List<GeoPoint> coursePath;
  final VoidCallback onStart;
  final void Function(LocationService source) onStartSimulation;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return switch (tracker.status) {
      // 시뮬레이션 버튼은 디버그 빌드에서만 그려진다(SimulationStartButton 참고).
      RunStatus.idle || RunStatus.finished => Row(
        children: [
          Expanded(
            child: FilledButton(onPressed: onStart, child: const Text('러닝 시작')),
          ),
          if (kDebugMode) ...[
            const SizedBox(width: 12),
            SimulationStartButton(
              coursePath: coursePath,
              onStart: onStartSimulation,
            ),
          ],
        ],
      ),
      // 종료는 항상 일시정지를 거친다 — 완주했든 아니든 사용자가 일시정지를
      // 누른 뒤 종료 버튼으로 끝낸다(아래 RunStatus.paused 참고).
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

