import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../services/service_locator.dart';
import '../../theme/app_theme.dart';
import '../../utils/transient_messenger.dart';
import 'participation_form_screen.dart';
import 'running_week.dart';
import 'running_week_banner.dart';

/// 러닝위크 화면. 참가 신청 전에는 소개와 시작 버튼, 신청 후에는 5x5 빙고판.
///
/// 빙고판은 참가 신청을 해야 볼 수 있다(서버도 신청 전에는 내려주지 않는다).
class RunningWeekScreen extends StatefulWidget {
  const RunningWeekScreen({
    super.key,
    required this.week,
    required this.onOpenCourse,
  });

  final RunningWeek week;

  /// 코스 완주 스탬프 칸을 누르면 그 코스 안내(러닝 탭)로 보낸다.
  final ValueChanged<String> onOpenCourse;

  @override
  State<RunningWeekScreen> createState() => _RunningWeekScreenState();
}

class _RunningWeekScreenState extends State<RunningWeekScreen> {
  late RunningWeek _week = widget.week;
  final _messenger = TransientMessenger();

  Future<void> _reload() async {
    try {
      final week = await Services.instance.runningWeek.loadCurrent();
      if (!mounted) return;
      if (week == null) {
        // 그 사이 공개가 끝났다.
        Navigator.of(context).pop();
        return;
      }
      setState(() => _week = week);
    } catch (e) {
      if (mounted) _messenger.show(context, e.toString());
    }
  }

  Future<void> _start() async {
    final joined = await Navigator.of(context).push<RunningWeek>(
      MaterialPageRoute(builder: (_) => ParticipationFormScreen(week: _week)),
    );
    if (joined != null && mounted) setState(() => _week = joined);
  }

  void _openCell(BingoCell cell) {
    final stamp = cell.stamp;
    if (stamp == null) return;
    final courseId = stamp.courseId;
    if (stamp.conditionType == 'course_complete' && courseId != null) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      widget.onOpenCourse(courseId);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StampCircle(
                url: stamp.imageUrl,
                acquired: cell.acquired,
                size: 96,
              ),
              const SizedBox(height: 14),
              Text(
                stamp.name,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (stamp.description case final description?) ...[
                const SizedBox(height: 8),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: Theme.of(sheetContext).textTheme.bodyMedium,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final week = _week;
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(title: Text(week.title)),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: week.participated
              ? [_BingoView(week: week, onTapCell: _openCell)]
              : [_IntroView(week: week, onStart: _start)],
        ),
      ),
    );
  }
}

class _IntroView extends StatelessWidget {
  const _IntroView({required this.week, required this.onStart});

  final RunningWeek week;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RunningWeekBanner(week: week, onTap: onStart),
        const SizedBox(height: 20),
        if (week.description case final description?) ...[
          Text(
            description,
            style: const TextStyle(
              fontSize: 15,
              height: 1.5,
              color: AppColors.textBody,
            ),
          ),
          const SizedBox(height: 20),
        ],
        const Text(
          '참가 신청을 하면 5x5 빙고판이 열려요. 칸마다 스탬프 하나 — 스탬프를 받으면 칸이 채워져요.',
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
            color: AppColors.textSubtle,
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: onStart, child: const Text('러닝위크 시작하기')),
      ],
    );
  }
}

class _BingoView extends StatelessWidget {
  const _BingoView({required this.week, required this.onTapCell});

  final RunningWeek week;
  final ValueChanged<BingoCell> onTapCell;

  @override
  Widget build(BuildContext context) {
    final bingo = week.bingo;
    if (bingo == null || bingo.cells.length != Bingo.size * Bingo.size) {
      return const Padding(
        padding: EdgeInsets.only(top: 80),
        child: Text(
          '빙고판을 준비하고 있어요.\n잠시 후 다시 확인해 주세요.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: AppColors.textSubtle),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(
          TextSpan(
            style: const TextStyle(fontSize: 14, color: AppColors.textSubtle),
            children: [
              TextSpan(
                text: '${bingo.completedLines}줄 빙고',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              TextSpan(
                text: '   ${bingo.acquiredCount} / ${bingo.cells.length}칸',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: Bingo.size,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 0.78,
          children: [
            for (final cell in bingo.cells)
              _BingoCellTile(cell: cell, onTap: () => onTapCell(cell)),
          ],
        ),
        const SizedBox(height: 16),
        const Text(
          '코스 칸을 누르면 그 코스 안내로 가요. 러닝위크 전에 받은 스탬프도 채워져요.',
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: AppColors.textSubtle,
          ),
        ),
      ],
    );
  }
}

class _BingoCellTile extends StatelessWidget {
  const _BingoCellTile({required this.cell, required this.onTap});

  final BingoCell cell;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final stamp = cell.stamp;
    return Material(
      color: cell.acquired ? Colors.white : AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: stamp == null ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
          child: Column(
            children: [
              Expanded(
                child: _StampCircle(
                  url: stamp?.imageUrl,
                  acquired: cell.acquired,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                stamp?.name ?? '',
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  color: cell.acquired ? AppColors.ink : AppColors.textSubtle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 받았으면 도안, 못 받았으면 스탬프 탭과 같은 회색 잠금 도안.
class _StampCircle extends StatelessWidget {
  const _StampCircle({required this.url, required this.acquired, this.size});

  final String? url;
  final bool acquired;
  final double? size;

  static const String _lockedAsset = 'assets/images/stamp_locked.png';

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (!acquired) {
      child = Opacity(opacity: 0.55, child: Image.asset(_lockedAsset));
    } else if (url case final url? when url.isNotEmpty) {
      child = ClipOval(
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          errorWidget: (_, _, _) => const _AcquiredFallback(),
        ),
      );
    } else {
      child = const _AcquiredFallback();
    }
    return SizedBox(
      width: size,
      height: size,
      child: AspectRatio(aspectRatio: 1, child: child),
    );
  }
}

class _AcquiredFallback extends StatelessWidget {
  const _AcquiredFallback();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(color: AppColors.paper, shape: BoxShape.circle),
      child: Center(child: Icon(Icons.star_rounded, color: AppColors.accent)),
    );
  }
}
