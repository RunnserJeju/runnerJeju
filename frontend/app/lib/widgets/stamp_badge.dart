import 'package:flutter/material.dart';

import '../models/run_stamp.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'stamp_tone.dart';

/// 스탬프 도안. 획득/미획득 두 상태를 그린다.
///
/// 획득이면 색상 도안 + 스탬프 이름 + (기본 도안 한정) 획득일, 미획득이면 같은 도안을
/// 흑백·반투명으로(도안이 없으면 회색 잠금 도안). [stamp]가 있으면 도안/획득일
/// 출처로 쓰고, 미획득처럼 스탬프가 없을 땐 [name]/[imageUrl]/[acquired]로 그린다.
class StampBadge extends StatelessWidget {
  const StampBadge({
    super.key,
    this.stamp,
    this.name,
    this.imageUrl,
    this.acquired,
    this.size = 104,
    this.onTap,
    this.showLabel = true,
  }) : assert(stamp != null || name != null, 'stamp 또는 name 중 하나는 있어야 한다');

  /// 획득 스탬프. 도안 이미지·획득일 출처. 미획득이면 null일 수 있다.
  final RunStamp? stamp;

  /// 스탬프 이름. 없으면 [stamp]에서 가져온다.
  final String? name;

  /// 도안 URL. [stamp]가 없을 때(미획득) 쓴다.
  final String? imageUrl;

  /// 획득 여부. 없으면 [stamp] 유무로 판단한다.
  final bool? acquired;

  /// 도안이 없는 미획득 스탬프의 회색 잠금 도안.
  static const String _lockedAsset = 'assets/images/stamp_locked.png';

  final double size;
  final VoidCallback? onTap;

  /// 이름 라벨을 그릴지. 팝업처럼 문구를 따로 두는 곳에서 끈다.
  final bool showLabel;

  String get _name => name ?? stamp!.name;
  bool get _isAcquired => acquired ?? (stamp != null);

  /// 원 안에 그릴 도안 URL.
  String? get _designUrl => stamp?.imageUrl ?? imageUrl;

  @override
  Widget build(BuildContext context) {
    final Widget circle;
    if (_isAcquired) {
      circle = _circle();
    } else if (_designUrl != null) {
      circle = stampLockedTone(_circle());
    } else {
      circle = Opacity(
        opacity: 0.5,
        child: Image.asset(_lockedAsset, width: size, height: size),
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
        if (showLabel) ...[
          const SizedBox(height: 8),
          SizedBox(width: size + 8, child: _label()),
        ],
      ],
    );
  }

  /// 도안이 있으면 도안만 그린다(도안이 자기 테두리를 가진 투명 PNG라 배경 원을 깔지
  /// 않는다). 도안이 없거나 못 받으면 회색 원에 기본 얼굴.
  Widget _circle() {
    final url = _designUrl;
    if (url == null) return _defaultCircle();
    return SizedBox(
      width: size,
      height: size,
      child: Image.network(
        url,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => _defaultCircle(),
      ),
    );
  }

  Widget _defaultCircle() {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.paper,
      ),
      child: _DefaultFace(acquiredAt: _isAcquired ? stamp?.acquiredAt : null),
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
