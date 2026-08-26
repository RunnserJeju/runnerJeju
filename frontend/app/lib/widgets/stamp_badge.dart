import 'package:flutter/material.dart';

import '../models/run_stamp.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

/// 미획득(흑백) 상태의 코스명/자물쇠 색.
const Color _lockedInk = Color(0xFF9AA1AC);

/// 완주 스탬프 도안. 획득/미획득 두 상태를 그린다.
///
/// 획득이면 색상 도안 + 코스명 + (기본 도안 한정) 획득일, 미획득이면 grayscale로
/// 흐릿하게 + 자물쇠 느낌. [stamp]가 있으면 도안/획득일 출처로 쓰고, 미획득처럼
/// 스탬프가 없을 땐 [courseName]/[acquired]만으로 그린다.
class StampBadge extends StatelessWidget {
  const StampBadge({
    super.key,
    this.stamp,
    this.courseName,
    this.acquired,
    this.size = 104,
    this.onTap,
  }) : assert(
         stamp != null || courseName != null,
         'stamp 또는 courseName 중 하나는 있어야 한다',
       );

  /// 획득 스탬프. 도안 이미지·획득일 출처. 미획득이면 null일 수 있다.
  final RunStamp? stamp;

  /// 코스명. 없으면 [stamp]에서 가져온다.
  final String? courseName;

  /// 획득 여부. 없으면 [stamp] 유무로 판단한다.
  final bool? acquired;

  final double size;
  final VoidCallback? onTap;

  String get _name => courseName ?? stamp!.courseName;
  bool get _isAcquired => acquired ?? (stamp != null);

  /// 휘도 기반 grayscale 매트릭스.
  static const ColorFilter _grayscale = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    Widget circle = _circle();
    if (!_isAcquired) {
      // 흑백 + 흐릿하게
      circle = Opacity(
        opacity: 0.5,
        child: ColorFiltered(colorFilter: _grayscale, child: circle),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(size),
          child: circle,
        ),
        const SizedBox(height: 8),
        SizedBox(width: size + 8, child: _label()),
      ],
    );
  }

  Widget _circle() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.accent,
        border: Border.all(color: AppColors.ink, width: 2.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: _isAcquired && stamp?.imageUrl != null
          ? Image.network(
              stamp!.imageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  _DefaultFace(acquiredAt: stamp?.acquiredAt),
            )
          : _DefaultFace(acquiredAt: _isAcquired ? stamp?.acquiredAt : null),
    );
  }

  Widget _label() {
    if (_isAcquired) {
      return Text(
        _name,
        maxLines: 2,
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      );
    }

    // 미획득: 잠김 느낌으로
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.lock_outline_rounded, size: 11, color: _lockedInk),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            _name,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _lockedInk,
            ),
          ),
        ),
      ],
    );
  }
}

/// 서버 도안이 없을 때 그리는 기본 얼굴. [acquiredAt]이 있으면 획득일도 찍는다.
class _DefaultFace extends StatelessWidget {
  const _DefaultFace({this.acquiredAt});

  final DateTime? acquiredAt;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            acquiredAt != null
                ? Icons.directions_run_rounded
                : Icons.lock_rounded,
            size: 30,
            color: AppColors.ink,
          ),
          if (acquiredAt != null) ...[
            const SizedBox(height: 2),
            Text(
              Formatters.date(acquiredAt!),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
