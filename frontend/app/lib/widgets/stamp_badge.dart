import 'package:flutter/material.dart';

import '../models/run_stamp.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

/// 완주 스탬프 도안. 획득/미획득 두 상태를 그린다.
///
/// 획득이면 색상 도안 + 코스명 + (기본 도안 한정) 획득일, 미획득이면 회색 도안을
/// 흐릿하게(난이도별 색 도안을 흑백 처리하면 진하기가 제각각이라 회색 도안을
/// 따로 쓴다). [stamp]가 있으면 도안/획득일 출처로 쓰고, 미획득처럼
/// 스탬프가 없을 땐 [courseName]/[acquired]만으로 그린다.
class StampBadge extends StatelessWidget {
  const StampBadge({
    super.key,
    this.stamp,
    this.courseName,
    this.acquired,
    this.size = 104,
    this.onTap,
    this.showLabel = true,
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

  /// 미획득일 때의 회색 도안. 코스 도안 대신 늘 이걸 쓴다.
  static const String _lockedAsset = 'assets/images/stamp_locked.png';

  final double size;
  final VoidCallback? onTap;

  /// 코스명 라벨을 그릴지. 팝업처럼 문구를 따로 두는 곳에서 끈다.
  final bool showLabel;

  String get _name => courseName ?? stamp!.courseName;
  bool get _isAcquired => acquired ?? (stamp != null);

  /// 원 안에 그릴 도안 URL. 획득한 스탬프의 도안.
  String? get _designUrl => stamp?.imageUrl;

  @override
  Widget build(BuildContext context) {
    final circle = _isAcquired
        ? _circle()
        : Opacity(
            opacity: 0.5,
            child: Image.asset(_lockedAsset, width: size, height: size),
          );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(size),
          child: circle,
        ),
        if (showLabel) ...[
          const SizedBox(height: 8),
          SizedBox(width: size + 8, child: _label()),
        ],
      ],
    );
  }

  Widget _circle() {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.paper,
      ),
      clipBehavior: Clip.antiAlias,
      child: _designUrl != null
          ? Image.network(
              _designUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _DefaultFace(
                acquiredAt: _isAcquired ? stamp?.acquiredAt : null,
              ),
            )
          : _DefaultFace(acquiredAt: _isAcquired ? stamp?.acquiredAt : null),
    );
  }

  Widget _label() {
    return Text(
      _name,
      maxLines: 2,
      textAlign: TextAlign.center,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: _isAcquired ? AppColors.ink : AppColors.muted,
      ),
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
                : Icons.star_rounded,
            size: 30,
            color: acquiredAt != null ? AppColors.ink : AppColors.accent,
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
