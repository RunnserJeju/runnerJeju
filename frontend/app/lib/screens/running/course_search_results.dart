import 'package:flutter/material.dart';

import '../../models/running_course.dart';
import '../../theme/app_theme.dart';

/// 검색바 아래에 붙는 코스 이름 검색 결과.
///
/// 지도 마커는 검색과 무관하게 전부 남겨 두고, 이 목록만 서버 검색 결과를
/// 따른다. 항목을 고르면 지도가 그 코스로 이동한다.
class CourseSearchResults extends StatelessWidget {
  const CourseSearchResults({
    super.key,
    required this.results,
    required this.isLoading,
    required this.hasError,
    required this.onSelect,
    required this.onRetry,
  });

  final List<RunningCourse> results;
  final bool isLoading;
  final bool hasError;
  final ValueChanged<RunningCourse> onSelect;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    // body가 키보드에 맞춰 줄지 않으므로(지도 깨짐 방지) 목록 높이를 직접 잰다.
    final media = MediaQuery.of(context);
    final available = media.size.height - media.viewInsets.bottom - 180;
    final maxHeight = available.clamp(160.0, media.size.height * 0.45);

    return Material(
      color: Colors.white,
      elevation: 3,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: _body(),
      ),
    );
  }

  Widget _body() {
    if (isLoading && results.isEmpty) {
      return const _Message(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (hasError) {
      return _Message(
        child: TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('검색에 실패했어요. 다시 시도'),
        ),
      );
    }

    if (results.isEmpty) {
      return const _Message(
        child: Text(
          '검색 결과가 없어요',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF7A8593),
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 6),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: results.length,
      separatorBuilder: (_, _) => const Divider(
        height: 1,
        indent: 16,
        endIndent: 16,
        color: Color(0xFFEDEFF2),
      ),
      itemBuilder: (context, index) => _ResultTile(
        course: results[index],
        onTap: () => onSelect(results[index]),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.course, required this.onTap});

  final RunningCourse course;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            const Icon(Icons.route_rounded, size: 18, color: AppColors.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    course.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${course.distanceKm}km · ${course.address}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF7A8593),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Center(child: child),
    );
  }
}
