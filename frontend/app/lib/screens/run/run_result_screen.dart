import 'package:flutter/material.dart';

import '../../models/run_record.dart';
import '../../models/run_stamp.dart';
import '../../models/run_verification.dart';
import '../../services/run_submission.dart';
import '../../services/service_locator.dart';
import '../../theme/app_theme.dart';
import '../../widgets/coupon_card.dart';
import '../../widgets/coupon_celebration.dart';
import '../../widgets/run_metrics_card.dart';
import '../../widgets/run_map_view.dart';
import '../../widgets/stamp_badge.dart';
import '../../widgets/stamp_celebration.dart';
import 'run_share_screen.dart';

/// 러닝 결과. 저장·검증은 [RunSubmission]이 돌리고 여기서는 진행 상황과 보상을 보여준다.
class RunResultScreen extends StatefulWidget {
  const RunResultScreen({super.key, required this.record});

  final RunRecord record;

  @override
  State<RunResultScreen> createState() => _RunResultScreenState();
}

class _RunResultScreenState extends State<RunResultScreen> {
  RunSubmission get _submission => Services.instance.runSubmission;

  /// 연출 팝업은 한 번에 하나씩. 띄우는 동안 들어온 건 끝나고 이어서 띄운다.
  bool _celebrating = false;

  @override
  void initState() {
    super.initState();
    // 보통 run_screen이 완료 시점에 이미 제출했다. 다른 경로로 열렸을 때만 여기서.
    if (_submission.record != widget.record) {
      _submission.submit(widget.record);
    }
    _submission.addListener(_onSubmissionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _drainCelebrations());
  }

  @override
  void dispose() {
    _submission.removeListener(_onSubmissionChanged);
    super.dispose();
  }

  void _onSubmissionChanged() {
    if (!mounted) return;
    setState(() {});
    _drainCelebrations();
  }

  Future<void> _drainCelebrations() async {
    if (_celebrating) return;
    _celebrating = true;
    try {
      while (_submission.pendingCelebrations.isNotEmpty) {
        if (!mounted) return;
        final next = _submission.pendingCelebrations.removeAt(0);
        switch (next) {
          case StampCelebration(:final stamp):
            await showStampCelebration(context, stamp);
          case CouponCelebration(:final coupon):
            await showCouponCelebration(context, coupon);
          case CouponMissCelebration(:final name, :final benefit):
            await showCouponMiss(context, name: name, benefit: benefit);
        }
      }
    } finally {
      _celebrating = false;
    }
  }

  void _close() {
    Services.instance.runTracker.reset();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// 공유 카드로 넘어간다. 저장에 성공한 기록만 공유한다 — 서버에 없는 기록을
  /// 인증으로 올리면 나중에 프로필에서 찾을 수 없다.
  void _openShare() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RunShareScreen(
          record: _submission.uploadResult?.record ?? widget.record,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final s = _submission;

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
            IconButton(
              onPressed: _close,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            _SaveStatusBanner(
              saving: s.uploading,
              error: s.uploadError,
              earnedStamp: s.earnedStampAny,
              onRetry: s.retryUpload,
            ),
            if (record.isCourseRun && s.uploadError == null) ...[
              const SizedBox(height: 12),
              _VerificationBanner(
                verifying: s.verifying,
                verification: s.verification,
                error: s.verificationError,
                onRetry: s.retryVerify,
              ),
            ],
            if (s.earnedStamp != null) ...[
              const SizedBox(height: 20),
              _EarnedStampCard(stamp: s.earnedStamp!),
            ],
            if (s.earnedCoupon != null) ...[
              const SizedBox(height: 12),
              CouponCard(coupon: s.earnedCoupon!),
            ],
            for (final coupon in s.runningWeekCoupons) ...[
              const SizedBox(height: 12),
              CouponCard(coupon: coupon),
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
            RunMetricsCard(record: record),
            const SizedBox(height: 28),
            if (!s.uploading && s.uploadError == null) ...[
              OutlinedButton.icon(
                onPressed: _openShare,
                icon: const Icon(Icons.ios_share_rounded),
                label: const Text('공유하기'),
              ),
              const SizedBox(height: 12),
            ],
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
        color: AppColors.surfaceMuted,
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
        color: AppColors.surfaceMuted,
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
        color: AppColors.surfaceMuted,
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
