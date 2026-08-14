import 'package:flutter/material.dart';

import '../../models/running_course.dart';
import '../../theme/app_theme.dart';
import '../../widgets/course_card.dart';
import '../../widgets/sheet_handle.dart';

/// 경로 탐색: 코스를 목록으로 훑어보는 시트.
///
/// 지도는 "어디에 있나"를 보여주지만 "어떤 코스인가"를 훑기에는 나쁘다 —
/// 라벨을 하나씩 눌러 봐야 설명이 나오기 때문이다. 그래서 같은 코스 목록을
/// 목록 형태로도 볼 수 있게 한다. 지도와 이 시트는 **같은 코스 목록의 두
/// 표현**이라, 검색어로 걸러진 결과도 양쪽이 똑같이 따른다.
///
/// 항목을 고르면 별도 상세 화면으로 가지 않고 시트를 닫으며 지도에서 그 코스를
/// 선택한다. 코스 상세는 [CoursePreviewSheet]가 이미 맡고 있고, 화면을 하나 더
/// 띄우면 "목록 → 상세 → 뒤로 → 목록"을 오가게 된다.
class CourseListSheet extends StatelessWidget {
  const CourseListSheet({
    super.key,
    required this.courses,
    required this.isLoading,
    required this.hasError,
    required this.isFiltered,
    required this.onSelect,
    required this.onClose,
    required this.onRetry,
  });

  final List<RunningCourse> courses;
  final bool isLoading;
  final bool hasError;

  /// 검색어가 걸려 있는지. 비어 있을 때 "코스가 없다"와 "검색 결과가 없다"는
  /// 사용자가 할 일이 다르다.
  final bool isFiltered;

  final ValueChanged<RunningCourse> onSelect;
  final VoidCallback onClose;
  final VoidCallback onRetry;

  /// 접힌 높이. 목록을 훑는 화면이라 지도보다 목록에 무게를 둔다.
  static const double _collapsedSize = 0.55;

  /// 펼친 높이. 검색바는 가리지 않고 남겨 둔다 — 목록을 훑다가 바로 걸러낼 수
  /// 있어야 하고, 검색은 지도와 이 목록에 동시에 걸린다.
  static const double _expandedSize = 0.82;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: _collapsedSize,
      minChildSize: _collapsedSize,
      maxChildSize: _expandedSize,
      snap: true,
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
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              const SizedBox(height: 10),
              const SheetHandle(),
              _Header(count: courses.length, onClose: onClose),
              const Divider(height: 1, color: Color(0xFFEDEFF2)),
              Expanded(
                child: _body(context, scrollController),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, ScrollController scrollController) {
    if (courses.isEmpty) {
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
      itemCount: courses.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) => CourseCard(
        course: courses[index],
        onTap: () => onSelect(courses[index]),
      ),
    );
  }

  Widget _emptyState() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (hasError) {
      return _Empty(
        icon: Icons.cloud_off_rounded,
        title: '코스를 불러오지 못했어요',
        message: '잠시 후 다시 시도해 주세요',
        action: OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('다시 시도'),
        ),
      );
    }

    if (isFiltered) {
      return const _Empty(
        icon: Icons.search_off_rounded,
        title: '조건에 맞는 코스가 없어요',
        message: '검색어를 바꿔보세요',
      );
    }

    return const _Empty(
      icon: Icons.route_rounded,
      title: '아직 등록된 코스가 없어요',
      message: '코스가 올라오면 여기에 보여요',
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.count, required this.onClose});

  final int count;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
      child: Row(
        children: [
          const Text(
            '경로 탐색',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$count',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFFA3ABB6),
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
            tooltip: '닫기',
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
          style: const TextStyle(fontSize: 13, color: Color(0xFF7A8593)),
        ),
        if (action != null) ...[const SizedBox(height: 20), action!],
      ],
    );
  }
}
