import 'package:flutter/material.dart';

import '../../models/running_course.dart';
import '../../theme/app_theme.dart';
import '../../widgets/sheet_handle.dart';

/// 지도에서 코스 라벨을 눌렀을 때 아래에서 올라오는 시트.
///
/// 접힌 상태에서 이름·거리·난이도와 시작 버튼까지 보이고, 끌어올리면 설명과
/// 주차·화장실 안내가 이어진다. 상세를 별도 화면으로 띄우지 않는 이유는 지도가
/// 계속 보여야 하기 때문이다 — 코스를 몇 개 눌러 보며 고르는 화면이라,
/// 화면을 갈아 끼우면 매번 지도로 돌아오는 왕복이 생긴다.
///
/// 시트가 모달이 아니라 [Stack]에 얹히는 위젯인 것도 같은 이유다. 모달이면
/// 뒤에 장막이 깔려 지도를 만질 수 없다.
class CoursePreviewSheet extends StatelessWidget {
  const CoursePreviewSheet({
    super.key,
    required this.course,
    required this.detail,
    required this.detailError,
    required this.onClose,
    required this.onRetryDetail,
    required this.onStart,
  });

  /// 목록에서 온 코스. 이름·거리처럼 시트에 바로 보여줄 값은 여기 다 있다.
  final RunningCourse course;

  /// 경로까지 담긴 상세. 아직 받아오는 중이면 null이고, 그동안 시작 버튼이 잠긴다.
  final RunningCourse? detail;

  final Object? detailError;

  final VoidCallback onClose;
  final VoidCallback onRetryDetail;
  final VoidCallback onStart;

  /// 접힌 높이. 시작 버튼까지는 끌어올리지 않아도 보여야 한다.
  static const double _collapsedSize = 0.36;

  /// 펼친 높이. 검색바와 지도 일부는 남겨 둔다.
  static const double _expandedSize = 0.88;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: _collapsedSize,
      minChildSize: _collapsedSize,
      maxChildSize: _expandedSize,
      // 접힘/펼침 두 자리만 있다. 중간에서 손을 떼면 가까운 쪽으로 붙는다
      // (min·max는 스냅 지점에 저절로 포함되므로 snapSizes를 따로 주지 않는다).
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
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            children: [
              const Center(child: SheetHandle()),
              const SizedBox(height: 14),
              _Header(course: course, onClose: onClose),
              const SizedBox(height: 12),
              _MetaChips(course: course),
              const SizedBox(height: 16),
              _StartButton(
                isReady: detail != null,
                hasError: detailError != null,
                onStart: onStart,
                onRetry: onRetryDetail,
              ),
              const SizedBox(height: 20),
              const Divider(height: 1, color: Color(0xFFEDEFF2)),
              const SizedBox(height: 20),
              ..._details(context),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _details(BuildContext context) {
    final description = course.description;

    return [
      if (description != null && description.isNotEmpty) ...[
        const _SectionTitle('코스 소개'),
        const SizedBox(height: 8),
        Text(
          description,
          style: const TextStyle(
            fontSize: 14,
            height: 1.6,
            color: Color(0xFF3D4552),
          ),
        ),
        const SizedBox(height: 20),
      ],
      const _SectionTitle('위치'),
      const SizedBox(height: 8),
      _InfoRow(icon: Icons.place_outlined, label: '출발지', value: course.address),
      _InfoRow(
        icon: Icons.local_parking_rounded,
        label: '주차',
        value: course.parkingAddress,
      ),
      _InfoRow(
        icon: Icons.wc_rounded,
        label: '화장실',
        value: course.restroomAddress,
      ),
      if (course.tagList.isNotEmpty) ...[
        const SizedBox(height: 20),
        const _SectionTitle('태그'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final tag in course.tagList) _Chip(label: tag),
          ],
        ),
      ],
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.course, required this.onClose});

  final RunningCourse course;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      course.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  if (course.isCompletedByMe) ...[
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.verified_rounded,
                      size: 20,
                      color: AppColors.success,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                course.address,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: Color(0xFF7A8593)),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded),
          tooltip: '닫기',
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

class _MetaChips extends StatelessWidget {
  const _MetaChips({required this.course});

  final RunningCourse course;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _Chip(icon: Icons.straighten_rounded, label: '왕복 ${course.distanceKm}km'),
        _Chip(icon: Icons.trending_up_rounded, label: course.difficulty.label),
        _Chip(
          icon: Icons.emoji_events_outlined,
          label: '완주 ${course.completedCount}명',
        ),
      ],
    );
  }
}

/// 시작 버튼. 경로가 있어야 코스를 따라 달릴 수 있어서, 상세를 받아오는 동안은
/// 눌러도 아무 일이 없는 대신 기다리는 중임을 버튼 자체가 보여준다.
class _StartButton extends StatelessWidget {
  const _StartButton({
    required this.isReady,
    required this.hasError,
    required this.onStart,
    required this.onRetry,
  });

  final bool isReady;
  final bool hasError;
  final VoidCallback onStart;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (hasError) {
      return OutlinedButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('코스 정보를 불러오지 못했어요. 다시 시도'),
      );
    }

    if (!isReady) {
      return FilledButton(
        onPressed: null,
        child: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }

    return FilledButton.icon(
      onPressed: onStart,
      icon: const Icon(Icons.directions_run_rounded),
      label: const Text('이 코스로 달리기'),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w800,
        color: AppColors.ink,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;

  /// 명단에 값이 없는 코스가 있어서 비어 있을 수 있다.
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: const Color(0xFF7A8593)),
          const SizedBox(width: 10),
          SizedBox(
            width: 48,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF7A8593),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value?.isNotEmpty == true ? value! : '정보 없음',
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: value?.isNotEmpty == true
                    ? const Color(0xFF3D4552)
                    : const Color(0xFFA3ABB6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: const Color(0xFF5B6472)),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF3D4552),
            ),
          ),
        ],
      ),
    );
  }
}
