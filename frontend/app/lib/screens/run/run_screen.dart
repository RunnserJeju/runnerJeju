import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/geo_point.dart';
import '../../models/running_course.dart';
import '../../services/location_service.dart';
import '../../services/run_live_widget.dart';
import '../../services/run_tracker.dart';
import '../../services/service_locator.dart';
import '../../test/simulation_launcher.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../utils/transient_messenger.dart';
import '../../widgets/admin_only.dart';
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
  RunLiveWidget get _liveWidget => Services.instance.runLiveWidget;

  final TransientMessenger _messenger = TransientMessenger();

  /// 안내를 이미 띄운 끊김 사유. 같은 사유로 두 번 알리지 않으려고 들고 있는다.
  LocationInterruption? _notifiedInterruption;

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
    // 화면을 벗어나면 잠금화면 위젯도 걷어낸다 — 유령 위젯이 남지 않게.
    // (정상 종료는 _finish에서 이미 걷지만, 여기서 한 번 더 안전망을 둔다.)
    unawaited(_liveWidget.stop());
    super.dispose();
  }

  /// tracker의 현재 값으로 위젯에 보낼 한 컷을 만든다.
  RunWidgetData _snapshot() => RunWidgetData(
    distanceMeters: _tracker.distanceMeters,
    elapsed: _tracker.elapsed,
    paceSecondsPerKm: _tracker.paceSecondsPerKm,
    paused: _tracker.status == RunStatus.paused,
  );

  void _onTrackerChanged() {
    if (!mounted) return;

    // 같은 끊김으로 매 갱신마다 안내가 뜨지 않게, 사유가 바뀔 때만 알린다.
    // (화면에 남는 표시는 _ControlPanel이 따로 그린다 — 안내는 사라지지만
    // 왜 멈췄는지는 계속 보여야 한다.)
    final interruption = _tracker.interruption;
    if (interruption != _notifiedInterruption) {
      _notifiedInterruption = interruption;
      if (interruption != null) _messenger.show(context, interruption.message);
    }

    // 잠금화면 위젯도 같은 값으로 갱신한다(throttle은 위젯 계층이 담당).
    if (_tracker.isActive) unawaited(_liveWidget.update(_snapshot()));

    setState(() {});
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
    if (availability.isReady) {
      // 잠금화면 위젯을 띄운다(Android 상시 알림 / iOS Live Activity).
      unawaited(_liveWidget.start(_snapshot()));
    }
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

  /// 러닝을 끝내고 결과 화면으로 넘어간다.
  ///
  /// 되묻지 않는다. 종료 버튼은 일시정지 상태에서만 나오므로 여기까지 오려면
  /// 이미 한 번 멈추기로 마음먹고 버튼을 두 번 누른 뒤다. 거기서 한 번 더
  /// 물으면 확인 절차가 아니라 달리고 온 사람 앞을 막는 문이 된다.
  Future<void> _finish() async {
    _tracker.finish();
    // 러닝이 끝났으니 잠금화면 위젯을 걷는다.
    unawaited(_liveWidget.stop());
    final record = _tracker.buildRecord();
    if (record == null || !mounted) return;

    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => RunResultScreen(record: record)),
    );
  }

  /// 러닝 중에는 뒤로가기로 화면을 벗어나지 못하게 막는다.
  ///
  /// 뒤로가기는 연달아 눌리기 쉬워서, 안내를 그냥 띄우면 같은 문장이 누른
  /// 횟수만큼 줄을 선다([TransientMessenger] 참고).
  Future<void> _handlePop(bool didPop) async {
    if (didPop) return;

    _messenger.show(context, '러닝 중이에요. 종료하려면 정지 버튼을 눌러주세요.');
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
                    interruption: tracker.interruption,
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
    required this.interruption,
    required this.coursePath,
    required this.onStart,
    required this.onStartSimulation,
    required this.onPause,
    required this.onResume,
    required this.onFinish,
  });

  final RunTracker tracker;

  /// 위치가 끊겨서 멈춘 것이라면 그 사유. 사용자가 누른 일시정지와 화면 상태가
  /// 같아서, 이유를 적어 두지 않으면 왜 멈췄는지 알 길이 없다.
  final LocationInterruption? interruption;

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
          if (interruption != null) ...[
            _InterruptionNotice(interruption: interruption!),
            const SizedBox(height: 16),
          ],
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
      // 시뮬레이션 버튼은 admin 계정에게만 보인다(AdminOnly 참고).
      RunStatus.idle || RunStatus.finished => Row(
        children: [
          Expanded(
            child: FilledButton(onPressed: onStart, child: const Text('러닝 시작')),
          ),
          AdminOnly(
            child: Row(
              children: [
                const SizedBox(width: 12),
                SimulationStartButton(
                  coursePath: coursePath,
                  onStart: onStartSimulation,
                ),
              ],
            ),
          ),
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


/// 위치가 끊겨 기록이 멈췄음을 컨트롤 패널 안에 남겨 두는 줄.
///
/// 스낵바만으로는 부족하다. 몇 초 뒤 사라지는데, 그동안 화면을 안 보고 있었다면
/// 남는 것은 "멈춰 있는 러닝" 하나뿐이라 사용자가 직접 일시정지를 누른 것과
/// 구분되지 않는다.
class _InterruptionNotice extends StatelessWidget {
  const _InterruptionNotice({required this.interruption});

  final LocationInterruption interruption;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.location_off_rounded,
            size: 18,
            color: AppColors.danger,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  interruption.message,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  '위치를 다시 켜고 이어서를 누르면 계속 기록해요.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF5B6472)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
