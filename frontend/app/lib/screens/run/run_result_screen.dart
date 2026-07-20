import 'package:flutter/material.dart';

import '../../models/run_record.dart';
import '../../models/run_stamp.dart';
import '../../models/run_verification.dart';
import '../../services/service_locator.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/metric_tile.dart';
import '../../widgets/run_map_view.dart';
import '../../widgets/stamp_badge.dart';
import '../course/course_upload_screen.dart';

/// 러닝 결과: 기록을 서버에 저장하고, 완주 스탬프를 받았으면 함께 보여준다.
class RunResultScreen extends StatefulWidget {
  const RunResultScreen({super.key, required this.record});

  final RunRecord record;

  @override
  State<RunResultScreen> createState() => _RunResultScreenState();
}

class _RunResultScreenState extends State<RunResultScreen> {
  /// 기록 저장은 화면 진입 시 자동으로 1회 실행하고, 실패하면 재시도 버튼을 준다.
  RunUploadResult? _uploadResult;
  RunStamp? _earnedStamp;
  String? _saveError;
  bool _saving = true;

  /// 코스를 따라 달린 경우에만 수행하는 경로 검증.
  RunVerification? _verification;
  String? _verificationError;
  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    _save();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _saveError = null;
    });

    try {
      final result = await Services.instance.run.saveRecord(widget.record);
      if (!mounted) return;

      setState(() {
        _uploadResult = result;
        _saving = false;
      });

      // 저장된 기록 id가 있어야 검증을 요청할 수 있다.
      final runId = result.record.id;
      final courseId = widget.record.courseId;
      if (runId != null && courseId != null) {
        await _verify(runId: runId, courseId: courseId);
      }

      if (result.earnedStampId != null) {
        await _loadStamp(result.earnedStampId!);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saveError = '$e';
        _saving = false;
      });
    }
  }

  /// 경로 검증 요청. 검증 실패는 기록 저장을 되돌리지 않고 배너로만 알린다.
  Future<void> _verify({
    required String runId,
    required String courseId,
  }) async {
    setState(() {
      _verifying = true;
      _verificationError = null;
    });

    try {
      final verification = await Services.instance.verification.verify(
        runId: runId,
        courseId: courseId,
      );
      if (!mounted) return;

      setState(() {
        _verification = verification;
        _verifying = false;
      });

      // 스탬프는 검증이 matched일 때만 발급된다.
      if (verification.earnedStampId != null) {
        await _loadStamp(verification.earnedStampId!);
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _verificationError = '$e';
        _verifying = false;
      });
    }
  }

  Future<void> _retryVerification() async {
    final runId = _uploadResult?.record.id;
    final courseId = widget.record.courseId;
    if (runId == null || courseId == null) return;

    await _verify(runId: runId, courseId: courseId);
  }

  /// 스탬프 조회 실패는 저장 자체를 실패로 만들지 않는다. 기본 도안으로 대체된다.
  Future<void> _loadStamp(String stampId) async {
    try {
      final stamp = await Services.instance.stamp.loadStamp(stampId);
      if (mounted) setState(() => _earnedStamp = stamp);
    } catch (_) {
      // 무시: 스탬프 획득 사실은 이미 업로드 결과로 알고 있다.
    }
  }

  void _close() {
    Services.instance.runTracker.reset();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _uploadAsCourse() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CourseUploadScreen(path: widget.record.path),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('러닝 완료'),
          automaticallyImplyLeading: false,
          actions: [
            IconButton(onPressed: _close, icon: const Icon(Icons.close_rounded)),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            _SaveStatusBanner(
              saving: _saving,
              error: _saveError,
              earnedStamp: _uploadResult?.earnedStamp ?? false,
              onRetry: _save,
            ),
            if (record.isCourseRun && _saveError == null) ...[
              const SizedBox(height: 12),
              _VerificationBanner(
                verifying: _verifying,
                verification: _verification,
                error: _verificationError,
                onRetry: _retryVerification,
              ),
            ],
            if (_earnedStamp != null) ...[
              const SizedBox(height: 20),
              _EarnedStampCard(stamp: _earnedStamp!),
            ],
            const SizedBox(height: 20),
            Card(
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                height: 240,
                child: RunMapView(runPath: record.path),
              ),
            ),
            const SizedBox(height: 20),
            _ResultMetrics(record: record),
            const SizedBox(height: 28),
            OutlinedButton.icon(
              onPressed: record.path.length >= 2 ? _uploadAsCourse : null,
              icon: const Icon(Icons.add_road_rounded),
              label: const Text('이 경로를 코스로 등록'),
            ),
            const SizedBox(height: 10),
            FilledButton(onPressed: _close, child: const Text('완료')),
          ],
        ),
      ),
    );
  }
}

class _SaveStatusBanner extends StatelessWidget {
  const _SaveStatusBanner({
    required this.saving,
    required this.error,
    required this.earnedStamp,
    required this.onRetry,
  });

  final bool saving;
  final String? error;
  final bool earnedStamp;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (saving) {
      return const _Banner(
        color: Color(0xFFE8EBEF),
        icon: Icons.cloud_upload_outlined,
        title: '기록을 저장하는 중이에요',
      );
    }

    if (error != null) {
      return _Banner(
        color: const Color(0xFFFDE7E8),
        icon: Icons.error_outline_rounded,
        title: '저장하지 못했어요',
        message: error,
        action: TextButton(onPressed: onRetry, child: const Text('다시 시도')),
      );
    }

    return _Banner(
      color: earnedStamp ? AppColors.accent : const Color(0xFFE3F5EC),
      icon: earnedStamp
          ? Icons.workspace_premium_rounded
          : Icons.check_circle_outline_rounded,
      title: earnedStamp ? '완주 스탬프를 받았어요!' : '기록을 저장했어요',
    );
  }
}

/// 코스 러닝일 때만 노출되는 경로 검증 상태.
class _VerificationBanner extends StatelessWidget {
  const _VerificationBanner({
    required this.verifying,
    required this.verification,
    required this.error,
    required this.onRetry,
  });

  final bool verifying;
  final RunVerification? verification;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (verifying) {
      return const _Banner(
        color: Color(0xFFE8EBEF),
        icon: Icons.fact_check_outlined,
        title: '경로를 검증하는 중이에요',
        message: '코스대로 달렸는지 확인하고 있어요',
      );
    }

    if (error != null) {
      return _Banner(
        color: const Color(0xFFFDE7E8),
        icon: Icons.error_outline_rounded,
        title: '경로 검증에 실패했어요',
        message: error,
        action: TextButton(onPressed: onRetry, child: const Text('다시 시도')),
      );
    }

    final result = verification;
    if (result == null) return const SizedBox.shrink();

    final matchRate = result.matchRateLabel;

    return switch (result.status) {
      VerificationStatus.matched => _Banner(
        color: const Color(0xFFE3F5EC),
        icon: Icons.verified_rounded,
        title: result.status.message,
        message: matchRate == null ? result.detail : '코스 일치율 $matchRate',
      ),
      VerificationStatus.mismatched => _Banner(
        color: const Color(0xFFFFF4E0),
        icon: Icons.report_problem_outlined,
        title: result.status.message,
        message: result.detail ?? '완주로 인정되지 않아 스탬프가 발급되지 않았어요',
      ),
      VerificationStatus.failed => _Banner(
        color: const Color(0xFFFDE7E8),
        icon: Icons.error_outline_rounded,
        title: result.status.message,
        message: result.detail,
        action: TextButton(onPressed: onRetry, child: const Text('다시 시도')),
      ),
      // 검증 서버 분리 후 오래 걸리는 경우. 결과는 나중에 프로필에서 확인한다.
      VerificationStatus.pending || VerificationStatus.inProgress => _Banner(
        color: const Color(0xFFE8EBEF),
        icon: Icons.hourglass_bottom_rounded,
        title: result.status.message,
        message: '검증이 끝나면 스탬프가 발급돼요',
        action: TextButton(onPressed: onRetry, child: const Text('새로고침')),
      ),
    };
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.color,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: AppColors.ink),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                if (message != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    message!,
                    style: const TextStyle(fontSize: 12, height: 1.4),
                  ),
                ],
              ],
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

class _EarnedStampCard extends StatelessWidget {
  const _EarnedStampCard({required this.stamp});

  final RunStamp stamp;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(child: StampBadge(stamp: stamp, size: 128)),
      ),
    );
  }
}

class _ResultMetrics extends StatelessWidget {
  const _ResultMetrics({required this.record});

  final RunRecord record;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              Formatters.dateTime(record.startedAt),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: MetricTile(
                label: '거리 (KM)',
                value: Formatters.distanceKm(record.distanceMeters),
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
                  value: Formatters.duration(record.duration),
                  alignment: CrossAxisAlignment.center,
                ),
                MetricTile(
                  label: '평균 페이스',
                  value: Formatters.pace(record.paceSecondsPerKm),
                  alignment: CrossAxisAlignment.center,
                ),
                MetricTile(
                  label: '평균 속도',
                  value: record.speedKmh?.toStringAsFixed(1) ?? '--',
                  unit: 'km/h',
                  alignment: CrossAxisAlignment.center,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
