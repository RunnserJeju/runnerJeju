import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../services/service_locator.dart';
import '../../theme/app_theme.dart';
import '../../utils/transient_messenger.dart';
import '../../widgets/stamp_tone.dart';
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
    if (courseId != null) {
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
      backgroundColor: week.participated
          ? _BingoView.background
          : AppColors.paper,
      appBar: AppBar(title: Text(week.title)),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: week.participated
              ? const EdgeInsets.only(bottom: 40)
              : const EdgeInsets.fromLTRB(20, 8, 20, 40),
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

  static const Color background = Color(0xFFF5F5F5);

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
    final total = bingo.cells.length;
    final remaining = total - bingo.acquiredCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(acquired: bingo.acquiredCount, remaining: remaining),
        _StatsRow(
          items: [
            ('${bingo.completedLines}줄', '완성 빙고'),
            ('${bingo.acquiredCount}', '달린 코스'),
            ('$remaining', '남은 코스'),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      '러닝 코스 빙고',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  _LegendDot(color: AppColors.muted, label: '미완주'),
                  SizedBox(width: 12),
                  _LegendDot(color: AppColors.accent, label: '완주'),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                '제주 곳곳을 달리며 한 칸씩 채워보세요',
                style: TextStyle(fontSize: 14, color: AppColors.muted),
              ),
              const SizedBox(height: 16),
              _Board(cells: bingo.cells, onTapCell: onTapCell),
              const SizedBox(height: 16),
              const _InfoCard(),
            ],
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.acquired, required this.remaining});

  final int acquired;
  final int remaining;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '빙고판',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              style: const TextStyle(fontSize: 15, color: AppColors.muted),
              children: [
                TextSpan(
                  text: '$acquired개',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                  ),
                ),
                TextSpan(text: ' 완주 · $remaining개 미완주'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 완성 줄·달린 코스·남은 코스. 정보 표시만 — 탭처럼 보이지 않게 모두 진한 글씨.
class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.items});

  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: AppColors.lineSoft),
          bottom: BorderSide(color: AppColors.lineSoft),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        children: [
          for (final (value, label) in items)
            Expanded(
              child: Column(
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: const SizedBox.square(dimension: 8),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: AppColors.muted),
        ),
      ],
    );
  }
}

/// 흰 카드 안에 5x5 칸. 칸 사이 선은 각 칸의 얇은 테두리가 겹쳐 1px로 보인다.
class _Board extends StatelessWidget {
  const _Board({required this.cells, required this.onTapCell});

  final List<BingoCell> cells;
  final ValueChanged<BingoCell> onTapCell;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.lineSoft),
      ),
      padding: const EdgeInsets.all(8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          color: const Color(0xFFFAFAFA),
          child: GridView.count(
            crossAxisCount: Bingo.size,
            shrinkWrap: true,
            // 기본값은 기기 하단 safe area만큼 아래 여백을 붙여 카드 밑이 빈다.
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final cell in cells)
                _BingoCellTile(cell: cell, onTap: () => onTapCell(cell)),
            ],
          ),
        ),
      ),
    );
  }
}

class _BingoCellTile extends StatelessWidget {
  const _BingoCellTile({required this.cell, required this.onTap});

  final BingoCell cell;
  final VoidCallback onTap;

  static const Color _acquiredFill = Color(0x52F0B765); // #F0B765 32%
  static const Color _acquiredLabel = Color(0xFF804B12);
  static const Color _lockedLabel = Color(0xFF8B8B8B);
  static const Color _line = Color(0x1A0D0D0D); // ink 10%

  /// 전용 스탬프 이름의 "[러닝위크] " 접두어는 칸에선 뺀다 — 자리도 없고 모두 같은 말이다.
  static String _label(String name) =>
      name.replaceFirst(RegExp(r'^\[러닝위크\]\s*'), '');

  @override
  Widget build(BuildContext context) {
    final stamp = cell.stamp;
    final acquired = cell.acquired;
    return Material(
      color: acquired ? _acquiredFill : Colors.transparent,
      child: InkWell(
        onTap: stamp == null ? null : onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: _line, width: 0.5),
          ),
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
          child: Column(
            children: [
              Expanded(
                child: _StampCircle(url: stamp?.imageUrl, acquired: acquired),
              ),
              const SizedBox(height: 4),
              // 두 줄 높이를 고정해 긴 이름이 있어도 칸마다 도안 크기가 같다.
              SizedBox(
                height: 24,
                child: Center(
                  child: Text(
                    stamp == null ? '' : _label(stamp.name),
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9.5,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                      color: acquired ? _acquiredLabel : _lockedLabel,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const SizedBox.square(
              dimension: 40,
              child: Icon(
                Icons.info_outline_rounded,
                size: 20,
                color: AppColors.accent,
              ),
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '달리기를 마치면 해당 코스에 색이 채워져요.',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  '1줄/3줄/5줄을 완성하면 추첨으로 경품을 드려요.\n(재고 소진 시 조기 마감)',
                  style: TextStyle(fontSize: 13, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 받았으면 컬러 도안, 못 받았으면 같은 도안을 흑백·반투명으로. 도안이 없으면 잠금 도안.
class _StampCircle extends StatelessWidget {
  const _StampCircle({required this.url, required this.acquired, this.size});

  final String? url;
  final bool acquired;
  final double? size;

  static const String _lockedAsset = 'assets/images/stamp_locked.png';

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (url case final url? when url.isNotEmpty) {
      child = CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.contain,
        errorWidget: (_, _, _) => const _AcquiredFallback(),
      );
      if (!acquired) child = stampLockedTone(child);
    } else if (!acquired) {
      child = Opacity(opacity: 0.55, child: Image.asset(_lockedAsset));
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
