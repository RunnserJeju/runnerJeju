import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 상세 시트 맨 위의 사진 갤러리. 옆으로 넘기고, 여러 장이면 오른쪽 아래에 "2/5"를 띄운다.
///
/// 코스·협력업체 상세가 같이 쓴다. [urls]가 비어 있으면 아무것도 그리지 않으므로
/// 호출부가 유무를 따로 가르지 않아도 된다.
class ImageGallery extends StatefulWidget {
  const ImageGallery({super.key, required this.urls, this.aspectRatio = 16 / 10});

  final List<String> urls;
  final double aspectRatio;

  @override
  State<ImageGallery> createState() => _ImageGalleryState();
}

class _ImageGalleryState extends State<ImageGallery> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final urls = widget.urls;
    if (urls.isEmpty) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              itemCount: urls.length,
              onPageChanged: (index) => setState(() => _page = index),
              itemBuilder: (context, index) => CachedNetworkImage(
                imageUrl: urls[index],
                fit: BoxFit.cover,
                placeholder: (_, _) => const _Placeholder(),
                errorWidget: (_, _, _) => const _Placeholder(),
              ),
            ),
            if (urls.length > 1)
              Positioned(
                right: 10,
                bottom: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${_page + 1}/${urls.length}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return Container(
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
