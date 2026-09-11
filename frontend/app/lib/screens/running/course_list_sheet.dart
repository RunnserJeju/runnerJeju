import 'package:flutter/material.dart';

import '../../models/geo_point.dart';
import '../../models/running_course.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../utils/geo_utils.dart';
import '../../widgets/course_card.dart';
import '../../widgets/sheet_handle.dart';

/// 코스 탐색: 지도 아래에 늘 붙어 있는 시트. 접힌 상태에서는 손잡이와 제목만
/// 보이고, 끌어올리면 현위치에서 가까운 순으로 코스 목록이 나온다.
///
/// 지도는 "어디에 있나"를 보여주지만 "어떤 코스인가"를 훑기에는 나쁘다 —
/// 라벨을 하나씩 눌러 봐야 설명이 나오기 때문이다. 그래서 같은 코스 목록을
/// 목록 형태로도 볼 수 있게 한다. 지도와 이 시트는 **같은 코스 목록의 두
/// 표현**이다. 이름 검색은 검색바 아래 결과 목록이 따로 맡는다.
///
/// 항목을 고르면 별도 상세 화면으로 가지 않고 지도에서 그 코스를 선택한다.
/// 코스 상세는 [CoursePreviewSheet]가 이 자리를 대신 맡는다.
class CourseListSheet extends StatefulWidget {
  const CourseListSheet({
    super.key,
    required this.controller,
    required this.courses,
    required this.myPosition,
    required this.isLoading,
    required this.hasError,
    required this.onSelect,
    required this.onRetry,
  });

  /// 바깥('코스 탐색' 버튼, 지도 탭)에서 시트 높이를 움직일 때 쓴다.
  final DraggableScrollableController controller;

  final List<RunningCourse> courses;

  /// 정렬 기준이 되는 현위치. 없으면 서버가 준 순서 그대로 보여준다.
  final GeoPoint? myPosition;

  final bool isLoading;
  final bool hasError;

  final ValueChanged<RunningCourse> onSelect;
  final VoidCallback onRetry;

  /// 접힌 높이(px). 손잡이 + 제목 한 줄이 보이는 만큼.
  static const double peekHeight = 84;

  /// 펼친 높이. 목록을 훑는 화면이라 지도보다 목록에 무게를 둔다.
  static const double halfSize = 0.55;

  /// 최대 높이. 검색바는 가리지 않고 남겨 둔다.
  static const double fullSize = 0.82;

  @override
  State<CourseListSheet> createState() => _CourseListSheetState();
}

class _CourseListSheetState extends State<CourseListSheet> {
  /// 거리순으로 정렬해 둔 목록과, 그 정렬의 기준이 된 위치.
  ///
  /// 위치는 매초 갱신되는데 그때마다 다시 정렬하면 보고 있는 목록이 스크롤
  /// 중에 뒤섞인다. 기준 위치에서 [_resortDistance]보다 멀어졌을 때만 다시 줄 세운다.
  List<_NearbyCourse> _sorted = const [];
  GeoPoint? _anchor;

  static const double _resortDistance = 100;

  @override
  void initState() {
    super.initState();
    _resort();
  }

  @override
  void didUpdateWidget(covariant CourseListSheet old) {
    super.didUpdateWidget(old);
    final me = widget.myPosition;
    final anchor = _anchor;
    final moved =
        me != null &&
        (anchor == null ||
            GeoUtils.distanceBetween(anchor, me) > _resortDistance);
    if (!identical(old.courses, widget.courses) || moved) _resort();
  }

  void _resort() {
    final me = widget.myPosition;
    _anchor = me;
    final items = [
      for (final course in widget.courses)
        _NearbyCourse(
          course,
          me == null || course.startPoint == null
              ? null
              : GeoUtils.distanceBetween(me, course.startPoint!),
        ),
    ];
    if (me != null) {
      // 거리를 모르는 코스(시작점 없음)는 맨 뒤로.
      items.sort((a, b) {
        final da = a.distance, db = b.distance;
        if (da == null) return db == null ? 0 : 1;
        if (db == null) return -1;
        return da.compareTo(db);
      });
    }
    _sorted = items;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final peek = CourseListSheet.peekHeight / constraints.maxHeight;
        return DraggableScrollableSheet(
          controller: widget.controller,
          initialChildSize: peek,
          minChildSize: peek,
          maxChildSize: CourseListSheet.fullSize,
          snap: true,
          snapSizes: const [CourseListSheet.halfSize],
          builder: (context, scrollController) => DecoratedBox(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 16,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                const SheetHandle(),
                _Header(
                  count: widget.courses.length,
                  hasLocation: widget.myPosition != null,
                ),
                const Divider(height: 1, color: AppColors.lineSoft),
                Expanded(child: _body(scrollController)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _body(ScrollController scrollController) {
    if (_sorted.isEmpty) {
      // 비어 있어도 스크롤이 되어야 시트를 손가락으로 다시 내릴 수 있다.
      return ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
        children: [_emptyState()],
      );
    }

    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      itemCount: _sorted.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = _sorted[index];
        return CourseCard(
          course: item.course,
          distanceLabel: item.distance == null
              ? null
              : Formatters.awayDistance(item.distance!),
          onTap: () => widget.onSelect(item.course),
        );
      },
    );
  }

  Widget _emptyState() {
    if (widget.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (widget.hasError) {
      return _Empty(
        icon: Icons.cloud_off_rounded,
        title: '코스를 불러오지 못했어요',
        message: '잠시 후 다시 시도해 주세요',
        action: OutlinedButton.icon(
          onPressed: widget.onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('다시 시도'),
        ),
      );
    }

    return const _Empty(
      icon: Icons.route_rounded,
      title: '아직 등록된 코스가 없어요',
      message: '코스가 올라오면 여기에 보여요',
    );
  }
}

class _NearbyCourse {
  const _NearbyCourse(this.course, this.distance);

  final RunningCourse course;

  /// 현위치에서 시작점까지(m). 위치나 시작점이 없으면 null.
  final double? distance;
}

class _Header extends StatelessWidget {
  const _Header({required this.count, required this.hasLocation});

  final int count;
  final bool hasLocation;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Row(
        children: [
          Text(
            hasLocation ? '내 주변 코스' : '코스 탐색',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$count',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 36, color: const Color(0xFFC3C9D2)),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: AppColors.textSubtle),
        ),
        if (action != null) ...[const SizedBox(height: 20), action!],
      ],
    );
  }
}
