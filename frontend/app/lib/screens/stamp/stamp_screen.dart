import 'package:flutter/material.dart';

import '../../models/run_stamp.dart';
import '../../services/service_locator.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/async_view.dart';
import '../../widgets/stamp_badge.dart';

/// 완주 스탬프 보관함.
class StampScreen extends StatefulWidget {
  const StampScreen({super.key});

  @override
  State<StampScreen> createState() => _StampScreenState();
}

class _StampScreenState extends State<StampScreen> {
  late Future<List<RunStamp>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = Services.instance.stamp.loadMyStamps();
  }

  Future<void> _refresh() async {
    setState(_load);
    await _future.catchError((_) => <RunStamp>[]);
  }

  void _showStampDetail(RunStamp stamp) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StampBadge(stamp: stamp, size: 132),
              const SizedBox(height: 16),
              Text(
                '${Formatters.date(stamp.acquiredAt)} 완주',
                style: Theme.of(sheetContext).textTheme.bodyMedium,
              ),
              if (stamp.region != null) ...[
                const SizedBox(height: 4),
                Text(
                  stamp.region!,
                  style: Theme.of(sheetContext).textTheme.bodySmall,
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
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('스탬프')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<RunStamp>>(
          future: _future,
          builder: (context, snapshot) => AsyncView<List<RunStamp>>(
            snapshot: snapshot,
            onRetry: _refresh,
            isEmpty: (stamps) => stamps.isEmpty,
            emptyTitle: '아직 받은 스탬프가 없어요',
            emptyMessage: '코스를 완주하면 스탬프가 찍혀요',
            emptyIcon: Icons.workspace_premium_outlined,
            builder: (context, stamps) => _StampGrid(
              stamps: stamps,
              onTapStamp: _showStampDetail,
            ),
          ),
        ),
      ),
    );
  }
}

class _StampGrid extends StatelessWidget {
  const _StampGrid({required this.stamps, required this.onTapStamp});

  final List<RunStamp> stamps;
  final void Function(RunStamp stamp) onTapStamp;

  /// 보관함이 비어 보이지 않도록 다음 목표 자리를 빈 슬롯으로 채운다.
  static const int _minSlots = 9;

  @override
  Widget build(BuildContext context) {
    final emptySlots = (_minSlots - stamps.length).clamp(0, _minSlots);

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          sliver: SliverToBoxAdapter(
            child: _StampSummary(count: stamps.length),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 24,
              crossAxisSpacing: 12,
              childAspectRatio: 0.74,
            ),
            itemCount: stamps.length + emptySlots,
            itemBuilder: (context, index) {
              if (index >= stamps.length) {
                return const Center(child: EmptyStampSlot());
              }

              final stamp = stamps[index];
              return Center(
                child: StampBadge(
                  stamp: stamp,
                  onTap: () => onTapStamp(stamp),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StampSummary extends StatelessWidget {
  const _StampSummary({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '모은 스탬프',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            '$count개',
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}
