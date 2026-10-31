import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/run_stamp.dart';
import '../../models/running_course.dart';
import '../../services/service_locator.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/async_view.dart';
import '../../widgets/stamp_badge.dart';
import '../../widgets/stamp_tone.dart';

/// 스탬프함. 스탬프 종류 전체를 카드 그리드로 깔고, 받은 것은 색상·못 받은 것은 흑백.
/// 스탬프는 코스와 분리됐다(#71) — 코스 완주 스탬프면 코스 정보를 곁들인다.
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

  /// 스탬프 종류·내 스탬프·코스를 함께 불러 슬롯 목록으로 합친다.
  /// 순서는 스탬프 종류 순(서버 정렬), 목록에 없는 스탬프(숨긴 종류 등)는 뒤에.
  Future<List<_StampSlot>> _buildSlots() async {
    final definitionsFuture = Services.instance.stamp.loadDefinitions();
    final stampsFuture = Services.instance.stamp.loadMyStamps();
    final coursesFuture = Services.instance.course.loadCourses();
    final definitions = await definitionsFuture;
    final stamps = await stampsFuture;
    final courses = await coursesFuture;

    final byDefinition = {for (final s in stamps) s.definitionId: s};
    final courseById = {for (final c in courses) c.id: c};
    final definitionIds = definitions.map((d) => d.id).toSet();

    return [
      for (final d in definitions)
        _StampSlot.fromDefinition(
          d,
          byDefinition[d.id],
          courseById[d.courseId],
        ),
      for (final s in stamps)
        if (!definitionIds.contains(s.definitionId)) _StampSlot.fromStamp(s),
    ];
  }

  Future<void> _refresh() async {
    setState(_load);
    await _future.catchError((_) => <_StampSlot>[]);
  }

  /// 받은 스탬프는 도안·획득일, 못 받은 스탬프는 이름과 획득 조건 안내.
  /// 가운데 작은 팝업. 우상단 X나 바깥을 누르면 닫힌다.
  void _showStampDetail(_StampSlot slot) {
    final stamp = slot.stamp;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.white,
        // 화면 폭의 약 3분의 2(좌우 48 여백을 뺀 폭의 2/3).
        insetPadding: EdgeInsets.symmetric(
          horizontal: (MediaQuery.sizeOf(dialogContext).width + 192) / 6,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Stack(
          children: [
            // Stack 안이라 폭이 내용만큼 줄어든다. 팝업 폭을 꽉 채워 가운데에 놓는다.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 36, 24, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StampBadge(
                    stamp: stamp,
                    name: slot.name,
                    imageUrl: slot.imageUrl,
                    acquired: slot.acquired,
                    size: 132,
                  ),
                  if (slot.description case final description?) ...[
                    const SizedBox(height: 12),
                    Text(
                      description,
                      textAlign: TextAlign.center,
                      style: Theme.of(dialogContext).textTheme.bodyMedium,
                    ),
                  ],
                  if (stamp != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      '${Formatters.date(stamp.acquiredAt)} 획득',
                      style: Theme.of(dialogContext).textTheme.bodyMedium,
                    ),
                  ],
                ],
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                tooltip: '닫기',
                onPressed: () => Navigator.of(dialogContext).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ],
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
            emptyTitle: '아직 스탬프가 없어요',
            emptyMessage: '스탬프가 등록되면 모을 수 있어요',
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
  final void Function(_StampSlot slot) onTapStamp;

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
            Tab(text: '획득'),
            Tab(text: '미획득'),
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
                  emptyText: '아직 스탬프가 없어요',
                ),
                _StampGrid(
                  slots: acquired,
                  onRefresh: onRefresh,
                  onTapStamp: onTapStamp,
                  emptyText: '아직 받은 스탬프가 없어요',
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
        ),
      ],
    );
  }
}

/// 제목 + "N개 획득 · M개 미획득" 요약.
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
                TextSpan(text: ' 획득 · ${total - acquired}개 미획득'),
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
  final void Function(_StampSlot slot) onTapStamp;
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
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
                    onTap: () => onTapStamp(slot),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// 흰 카드 하나: 도안 + 이름 + (코스 스탬프면) 지역·거리·난이도 + (획득 시) 획득일.
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
              // 두 줄까지, 넘으면 말줄임. 칸 높이(mainAxisExtent)는 고정이라 두 줄이어도 안 늘어난다.
              Text(
                slot.name,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
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

/// 원형 스탬프 도안. 받았으면 컬러, 못 받았으면 같은 도안을 흑백·반투명으로.
/// 도안이 없을 때만 회색 잠금 도안.
class _StampImage extends StatelessWidget {
  const _StampImage({required this.url, required this.acquired});

  final String? url;
  final bool acquired;

  static const double _size = 64;

  static const String _lockedAsset = 'assets/images/stamp_locked.png';

  @override
  Widget build(BuildContext context) {
    final url = this.url;
    if (url == null || url.isEmpty) {
      if (!acquired) {
        return Opacity(
          opacity: 0.55,
          child: Image.asset(_lockedAsset, width: _size, height: _size),
        );
      }
      return const SizedBox(width: _size, height: _size, child: _Fallback());
    }
    Widget image = SizedBox(
      width: _size,
      height: _size,
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          placeholder: (_, _) => const _Fallback(),
          errorWidget: (_, _, _) => const _Fallback(),
        ),
      ),
    );
    if (!acquired) image = stampLockedTone(image);
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

/// 스탬프 그리드 한 칸. 스탬프 종류 하나 = 슬롯 하나이며, 받은 스탬프가 있으면 획득.
class _StampSlot {
  const _StampSlot({
    required this.name,
    required this.acquired,
    required this.imageUrl,
    this.description,
    this.stamp,
    this.region,
    this.distanceKm,
    this.difficulty,
  });

  /// [course]는 코스 완주 스탬프일 때 그 코스(숨긴 코스면 null).
  factory _StampSlot.fromDefinition(
    StampDefinition definition,
    RunStamp? stamp,
    RunningCourse? course,
  ) => _StampSlot(
    name: definition.name,
    acquired: stamp != null,
    imageUrl: definition.imageUrl,
    description: definition.description,
    stamp: stamp,
    region: course == null ? null : _regionOf(course.address),
    distanceKm: course?.distanceKmLabel,
    difficulty: course?.difficulty,
  );

  factory _StampSlot.fromStamp(RunStamp stamp) => _StampSlot(
    name: stamp.name,
    acquired: true,
    imageUrl: stamp.imageUrl,
    description: stamp.description,
    stamp: stamp,
  );

  final String name;
  final bool acquired;
  final String? imageUrl;
  final String? description;
  final RunStamp? stamp;

  /// 코스 메타. 코스 완주 스탬프가 아니면 null이라 카드에서 숨긴다.
  final String? region;
  final String? distanceKm;
  final CourseDifficulty? difficulty;

  /// "제주시 · 14 km". 지역·거리 둘 다 없으면 null.
  String? get metaLine {
    final parts = [?region, if (distanceKm case final d?) '$d km'];
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
