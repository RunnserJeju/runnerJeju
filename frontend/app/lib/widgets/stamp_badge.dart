import 'package:flutter/material.dart';

import '../models/run_stamp.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

/// 완주 스탬프 도안. 서버 이미지가 없으면 코스 이름으로 기본 도안을 그린다.
class StampBadge extends StatelessWidget {
  const StampBadge({
    super.key,
    required this.stamp,
    this.size = 104,
    this.onTap,
  });

  final RunStamp stamp;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(size),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accent,
              border: Border.all(color: AppColors.ink, width: 2.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: stamp.imageUrl != null
                ? Image.network(
                    stamp.imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _DefaultFace(stamp: stamp),
                  )
                : _DefaultFace(stamp: stamp),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: size + 8,
          child: Text(
            stamp.courseName,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _DefaultFace extends StatelessWidget {
  const _DefaultFace({required this.stamp});

  final RunStamp stamp;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.directions_run_rounded,
            size: 30,
            color: AppColors.ink,
          ),
          const SizedBox(height: 2),
          Text(
            Formatters.date(stamp.acquiredAt),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// 아직 획득하지 않은 스탬프 자리를 표시하는 빈 슬롯.
class EmptyStampSlot extends StatelessWidget {
  const EmptyStampSlot({super.key, this.size = 104});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: const Color(0xFFD3D8DF),
          width: 2,
          strokeAlign: BorderSide.strokeAlignInside,
        ),
      ),
      child: const Icon(
        Icons.lock_outline_rounded,
        color: Color(0xFFB8BFC8),
      ),
    );
  }
}
