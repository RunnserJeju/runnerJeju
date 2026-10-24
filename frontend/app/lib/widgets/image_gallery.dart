import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 상세 시트 맨 위의 사진 띠. 높이만 고정하고 사진마다 원본 비율대로 폭이 달라진다 —
/// 가로 사진은 넓게, 세로 사진은 좁게, 잘리는 부분 없이(네이버지도 장소 상세와 같은 방식).
/// 옆으로 밀어 넘긴다.
///
/// 코스·협력업체 상세가 같이 쓴다. [urls]가 비어 있으면 아무것도 그리지 않으므로
/// 호출부가 유무를 따로 가르지 않아도 된다.
class ImageGallery extends StatelessWidget {
  const ImageGallery({super.key, required this.urls, this.height = 180});

  final List<String> urls;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) return const SizedBox.shrink();

    // 사진 폭의 합이 칸보다 좁으면 가운데로 모으고, 넘치면 왼쪽부터 옆으로 민다.
    // Row의 최소 폭을 칸 폭으로 잡아 두면 남는 공간을 center가 양쪽에 나눠 준다.
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final (index, url) in urls.indexed) ...[
                  if (index > 0) const SizedBox(width: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: url,
                      height: height,
                      // 높이에 맞추고 폭은 사진 비율이 정한다.
                      fit: BoxFit.fitHeight,
                      placeholder: (_, _) => _Placeholder(height: height),
                      errorWidget: (_, _, _) => _Placeholder(height: height),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 받아오는 중·실패 자리. 폭을 모르니 16:10으로 잡아 둔다.
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: height * 1.6,
      height: height,
      color: AppColors.paper,
      alignment: Alignment.center,
      child: Icon(
        Icons.image_outlined,
        size: 32,
        color: AppColors.ink.withValues(alpha: 0.12),
      ),
    );
  }
}
