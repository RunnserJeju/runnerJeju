import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/run_stamp.dart';
import '../../models/running_course.dart';
import '../../services/service_locator.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/async_view.dart';
import '../../widgets/stamp_badge.dart';

/// 스탬프함. 전체 코스를 카드 그리드로 깔고, 완주분은 색상·미완주는 흑백.
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
  /// 순서는 코스 카탈로그 순, 코스 목록에 없는 스탬프(삭제된 코스 등)는 뒤에.
  Future<List<_StampSlot>> _buildSlots() async {
    final stampsFuture = Services.instance.stamp.loadMyStamps();
    final coursesFuture = Services.instance.course.loadCourses();
    final stamps = await stampsFuture;
    final courses = await coursesFuture;

    final byCourse = {for (final s in stamps) s.courseId: s};
    final courseIds = courses.map((c) => c.id).toSet();

    return [
      for (final c in courses) _StampSlot.fromCourse(c, byCourse[c.id]),
      for (final s in stamps)
        if (!courseIds.contains(s.courseId)) _StampSlot.fromStamp(s),
    ];
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
        backgroundColor: Colors.white,
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SafeArea(
          bottom: false,
          child: _Header(acquired: acquired.length, total: slots.length),
        ),
        const TabBar(
          labelColor: AppColors.ink,
          unselectedLabelColor: AppColors.muted,
          labelStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          unselectedLabelStyle: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
          indicatorColor: AppColors.ink,
          indicatorWeight: 2,
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: AppColors.lineSoft,
          tabs: [
            Tab(text: '전체'),
            Tab(text: '완주'),
            Tab(text: '미완주'),
          ],
        ),
        Expanded(
          child: ColoredBox(
            color: AppColors.paper,
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
                  emptyText: '아직 완주한 코스가 없어요',
                ),
                _StampGrid(
                  slots: unacquired,
                  onRefresh: onRefresh,
                  onTapStamp: onTapStamp,
                  emptyText: '모든 코스를 완주했어요!',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 제목 + "N개 완주 · M개 미완주" 요약.
class _Header extends StatelessWidget {
  const _Header({required this.acquired, required this.total});

  final int acquired;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '스탬프함',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.muted,
              ),
              children: [
                TextSpan(
                  text: '$acquired개',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                  ),
                ),
                TextSpan(text: ' 완주 · ${total - acquired}개 미완주'),
              ],
            ),
          ),
        ],
      ),
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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
              sliver: SliverGrid.builder(
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      mainAxisExtent: 188,
                    ),
                itemCount: slots.length,
                itemBuilder: (context, index) {
                  final slot = slots[index];
                  return _StampCard(
                    slot: slot,
                    onTap: slot.acquired
                        ? () => onTapStamp(slot.stamp!)
                        : null,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// 흰 카드 하나: 도안 + 코스명 + 지역·거리 + 난이도 + (완주 시) 완주일.
class _StampCard extends StatelessWidget {
  const _StampCard({required this.slot, this.onTap});

  final _StampSlot slot;
  final VoidCallback? onTap;

  static const _metaStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: AppColors.muted,
    height: 1.3,
  );

  @override
  Widget build(BuildContext context) {
    final acquired = slot.acquired;
    final levelColor = slot.difficulty?.color;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 14, 8, 12),
          child: Column(
            children: [
              _StampImage(url: slot.imageUrl, acquired: acquired),
              const SizedBox(height: 10),
              Text(
                slot.courseName,
                maxLines: 1,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: acquired ? AppColors.ink : AppColors.muted,
                ),
              ),
              if (slot.metaLine case final meta?) ...[
                const SizedBox(height: 4),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _metaStyle,
                ),
              ],
              if (slot.difficulty case final d?)
                Text(d.title, style: _metaStyle),
              if (acquired) ...[
                const Spacer(),
                Text(
                  Formatters.monthDay(slot.stamp!.acquiredAt),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: levelColor ?? AppColors.accent,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 원형 스탬프 도안. DB 이미지를 불러오고, 미완주면 흑백·반투명.
class _StampImage extends StatelessWidget {
  const _StampImage({required this.url, required this.acquired});

  final String? url;
  final bool acquired;

  static const double _size = 64;

  /// 휘도 기반 grayscale 매트릭스.
  static const ColorFilter _grayscale = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    Widget image = SizedBox(
      width: _size,
      height: _size,
      child: ClipOval(
        child: url != null && url!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                placeholder: (_, _) => const _Fallback(),
                errorWidget: (_, _, _) => const _Fallback(),
              )
            : const _Fallback(),
      ),
    );
    if (!acquired) {
      image = Opacity(
        opacity: 0.55,
        child: ColorFiltered(colorFilter: _grayscale, child: image),
      );
    }
    return image;
  }
}

/// 도안이 없거나 못 불러왔을 때의 자리 표시.
class _Fallback extends StatelessWidget {
  const _Fallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.paper,
      child: Icon(Icons.star_rounded, size: 28, color: AppColors.accent),
    );
  }
}

/// 스탬프 그리드 한 칸. 코스 하나 = 슬롯 하나이며, 대응 스탬프가 있으면 완주.
class _StampSlot {
  const _StampSlot({
    required this.courseId,
    required this.courseName,
    required this.acquired,
    required this.imageUrl,
    this.stamp,
    this.region,
    this.distanceKm,
    this.difficulty,
  });

  factory _StampSlot.fromCourse(RunningCourse course, RunStamp? stamp) =>
      _StampSlot(
        courseId: course.id,
        courseName: stamp?.courseName ?? course.name,
        acquired: stamp != null,
        // 발급된 도안이 우선, 없으면 코스에 설정된 목표 도안.
        imageUrl: stamp?.imageUrl ?? course.stampImageUrl,
        stamp: stamp,
        region: _regionOf(course.address),
        distanceKm: course.distanceKm,
        difficulty: course.difficulty,
      );

  factory _StampSlot.fromStamp(RunStamp stamp) => _StampSlot(
    courseId: stamp.courseId,
    courseName: stamp.courseName,
    acquired: true,
    imageUrl: stamp.imageUrl,
    stamp: stamp,
  );

  final String courseId;
  final String courseName;
  final bool acquired;
  final String? imageUrl;
  final RunStamp? stamp;

  /// 코스 메타. 코스 목록에 없는 스탬프는 null이라 카드에서 숨긴다.
  final String? region;
  final int? distanceKm;
  final CourseDifficulty? difficulty;

  /// "제주시 · 14 km". 지역·거리 둘 다 없으면 null.
  String? get metaLine {
    final parts = [
      ?region,
      if (distanceKm case final d?) '$d km',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// 주소에서 시/군/읍/면 단위만 뽑는다. 예) "제주특별자치도 서귀포시 ..." → "서귀포시".
  static String? _regionOf(String address) {
    final tokens = address.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    if (tokens.isEmpty) return null;
    return tokens.firstWhere(
      (t) => RegExp(r'[시군읍면]$').hasMatch(t),
      orElse: () => tokens.first,
    );
  }
}

extension on CourseDifficulty {
  Color get color => switch (this) {
    CourseDifficulty.easy => AppColors.levelEasy,
    CourseDifficulty.normal => AppColors.levelNormal,
    CourseDifficulty.hard => AppColors.levelHard,
  };
}
