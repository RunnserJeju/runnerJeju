import 'package:flutter/material.dart';

import '../../models/run_stamp.dart';
import '../../models/running_course.dart';
import '../../services/service_locator.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/async_view.dart';
import '../../widgets/stamp_badge.dart';

/// 완주 스탬프 보관함. 전체 코스를 카탈로그로 깔고, 획득분은 색상·미획득은 흑백.
class StampScreen extends StatefulWidget {
  const StampScreen({super.key});

  @override
  State<StampScreen> createState() => _StampScreenState();
}

class _StampScreenState extends State<StampScreen> {
  late Future<List<_StampSlot>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = _buildSlots();
  }

  /// 내 스탬프와 전체 코스를 함께 불러 코스별 슬롯 목록으로 합친다.
  Future<List<_StampSlot>> _buildSlots() async {
    final stampsFuture = Services.instance.stamp.loadMyStamps();
    final coursesFuture = Services.instance.course.loadCourses();
    final stamps = await stampsFuture;
    final courses = await coursesFuture;

    final byCourse = {for (final s in stamps) s.courseId: s};

    // 전체 카탈로그 = 전체 코스. 코스마다 대응 스탬프가 있으면 획득.
    final slots = courses
        .map((c) => _StampSlot.fromCourse(c, byCourse[c.id]))
        .toList();

    // 코스 목록에 없는 스탬프(삭제된 코스 등)도 획득분이니 남긴다.
    final courseIds = courses.map((c) => c.id).toSet();
    slots.addAll(
      stamps
          .where((s) => !courseIds.contains(s.courseId))
          .map(_StampSlot.fromStamp),
    );

    // 획득분 먼저(획득일 최신순), 미획득은 뒤(코스명순).
    slots.sort((a, b) {
      if (a.acquired != b.acquired) return a.acquired ? -1 : 1;
      if (a.acquired && b.acquired) {
        return b.stamp!.acquiredAt.compareTo(a.stamp!.acquiredAt);
      }
      return a.courseName.compareTo(b.courseName);
    });
    return slots;
  }

  Future<void> _refresh() async {
    setState(_load);
    await _future.catchError((_) => <_StampSlot>[]);
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
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('스탬프'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '전체'),
              Tab(text: '획득'),
              Tab(text: '미획득'),
            ],
          ),
        ),
        body: FutureBuilder<List<_StampSlot>>(
          future: _future,
          builder: (context, snapshot) => AsyncView<List<_StampSlot>>(
            snapshot: snapshot,
            onRetry: _refresh,
            isEmpty: (slots) => slots.isEmpty,
            emptyTitle: '아직 스탬프 코스가 없어요',
            emptyMessage: '코스가 등록되면 스탬프를 모을 수 있어요',
            emptyIcon: Icons.workspace_premium_outlined,
            builder: (context, slots) => _StampBody(
              slots: slots,
              onRefresh: _refresh,
              onTapStamp: _showStampDetail,
            ),
          ),
        ),
      ),
    );
  }
}

class _StampBody extends StatelessWidget {
  const _StampBody({
    required this.slots,
    required this.onRefresh,
    required this.onTapStamp,
  });

  final List<_StampSlot> slots;
  final Future<void> Function() onRefresh;
  final void Function(RunStamp stamp) onTapStamp;

  @override
  Widget build(BuildContext context) {
    final acquired = slots.where((s) => s.acquired).toList();
    final unacquired = slots.where((s) => !s.acquired).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: _StampSummary(acquired: acquired.length, total: slots.length),
        ),
        Expanded(
          child: TabBarView(
            children: [
              _StampGrid(
                slots: slots,
                onRefresh: onRefresh,
                onTapStamp: onTapStamp,
                emptyText: '아직 스탬프 코스가 없어요',
              ),
              _StampGrid(
                slots: acquired,
                onRefresh: onRefresh,
                onTapStamp: onTapStamp,
                emptyText: '아직 획득한 스탬프가 없어요',
              ),
              _StampGrid(
                slots: unacquired,
                onRefresh: onRefresh,
                onTapStamp: onTapStamp,
                emptyText: '모든 스탬프를 모았어요!',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StampGrid extends StatelessWidget {
  const _StampGrid({
    required this.slots,
    required this.onRefresh,
    required this.onTapStamp,
    required this.emptyText,
  });

  final List<_StampSlot> slots;
  final Future<void> Function() onRefresh;
  final void Function(RunStamp stamp) onTapStamp;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (slots.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  emptyText,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
              sliver: SliverGrid.builder(
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 24,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.74,
                    ),
                itemCount: slots.length,
                itemBuilder: (context, index) {
                  final slot = slots[index];
                  return Center(
                    child: slot.acquired
                        ? StampBadge(
                            stamp: slot.stamp,
                            onTap: () => onTapStamp(slot.stamp!),
                          )
                        : StampBadge(
                            courseName: slot.courseName,
                            acquired: false,
                          ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _StampSummary extends StatelessWidget {
  const _StampSummary({required this.acquired, required this.total});

  final int acquired;
  final int total;

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
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$acquired',
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                  color: AppColors.ink,
                ),
              ),
              Text(
                ' / 전체 $total개',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 스탬프 그리드 한 칸. 코스 하나 = 슬롯 하나이며, 대응 스탬프가 있으면 획득.
class _StampSlot {
  const _StampSlot({
    required this.courseId,
    required this.courseName,
    required this.acquired,
    this.stamp,
  });

  factory _StampSlot.fromCourse(RunningCourse course, RunStamp? stamp) =>
      _StampSlot(
        courseId: course.id,
        courseName: stamp?.courseName ?? course.name,
        acquired: stamp != null,
        stamp: stamp,
      );

  factory _StampSlot.fromStamp(RunStamp stamp) => _StampSlot(
    courseId: stamp.courseId,
    courseName: stamp.courseName,
    acquired: true,
    stamp: stamp,
  );

  final String courseId;
  final String courseName;
  final bool acquired;
  final RunStamp? stamp;
}
