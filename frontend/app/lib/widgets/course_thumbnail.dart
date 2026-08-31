import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 코스 대표 썸네일. 주어진 자리를 꽉 채우므로 호출부가 크기를 정한다.
///
/// URL이 없거나 받아오지 못해도 같은 크기의 플레이스홀더를 그린다 — 목록에서
/// 카드 높이가 들쭉날쭉해지는 걸 막는다. 아직 썸네일이 없는 코스가 대부분이라
/// 이 상태가 예외가 아니라 기본이다.
class CourseThumbnail extends StatelessWidget {
  const CourseThumbnail({super.key, required this.url, this.iconSize = 32});

  final String? url;

  /// 플레이스홀더 아이콘 크기. 썸네일 자리가 클수록 키운다.
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final url = this.url;
    if (url == null || url.isEmpty) return _Placeholder(iconSize: iconSize);

    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      // 디스크 캐시가 비어 있는 첫 로딩에도 빈 칸이 번쩍이지 않게 한다.
      placeholder: (_, _) => _Placeholder(iconSize: iconSize),
      errorWidget: (_, _, _) => _Placeholder(iconSize: iconSize),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.iconSize});

  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.paper,
      alignment: Alignment.center,
      child: Icon(
        Icons.directions_run_rounded,
        size: iconSize,
        color: AppColors.ink.withValues(alpha: 0.12),
      ),
    );
  }
}
