import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/coupon.dart';
import '../theme/app_theme.dart';
import 'coupon_card.dart';

/// 쿠폰 획득 팝업. 스탬프(쾅 찍힘·색종이)와 달리, 티켓이 아래에서 미끄러져 올라와 한 번
/// 뒤집히며 앞면을 보여주고, 앞면 위로 빛줄기가 한 번 훑고 지나간다. 가벼운 진동 한 번.
Future<void> showCouponCelebration(BuildContext context, Coupon coupon) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '닫기',
    barrierColor: Colors.black.withValues(alpha: 0.7),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, _, _) => _CouponCelebration(coupon: coupon),
    transitionBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

class _CouponCelebration extends StatefulWidget {
  const _CouponCelebration({required this.coupon});

  final Coupon coupon;

  @override
  State<_CouponCelebration> createState() => _CouponCelebrationState();
}

class _CouponCelebrationState extends State<_CouponCelebration>
    with SingleTickerProviderStateMixin {
  // 구간은 ms로 적는다. 전체 길이는 광택이 끝나는 시점.
  static const _totalMs = 1770;
  static const _riseMs = (0, 600);
  static const _flipMs = (450, 1125);
  static const _shineMs = (1020, 1770); // 0.75초
  static const _captionMs = (1050, 1425);

  /// 티켓이 뒤집혀 앞면이 보이는 시점(진동).
  static const _revealAt = 825 / _totalMs;

  static Interval _interval((int, int) ms, Curve curve) =>
      Interval(ms.$1 / _totalMs, ms.$2 / _totalMs, curve: curve);

  late final AnimationController _controller;
  bool _revealed = false;

  // 올라오기: 화면 아래에서 제자리로.
  late final Animation<double> _rise;
  // 뒤집기: 뒷면(π)에서 앞면(0)으로.
  late final Animation<double> _flip;
  // 광택: 앞면이 보인 뒤 빛줄기가 왼쪽에서 오른쪽으로 지나간다(0→1).
  late final Animation<double> _shine;
  // 문구·버튼 등장.
  late final Animation<double> _caption;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _totalMs),
    );

    _rise = Tween(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: _interval(_riseMs, Curves.easeOutCubic),
      ),
    );
    _flip = Tween(begin: pi, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: _interval(_flipMs, Curves.easeInOutBack),
      ),
    );
    _shine = CurvedAnimation(
      parent: _controller,
      curve: _interval(_shineMs, Curves.easeInOut),
    );
    _caption = CurvedAnimation(
      parent: _controller,
      curve: _interval(_captionMs, Curves.easeOutCubic),
    );

    _controller.addListener(_onTick);
    _controller.forward();
  }

  void _onTick() {
    if (_revealed || _controller.value < _revealAt) return;
    _revealed = true;
    HapticFeedback.lightImpact();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // 뒤집히는 동안 뒷면(앞면의 거울상)을 보여주는 대신 뒷면 카드를 따로 그린다.
        final showingBack = _flip.value > pi / 2;

        return Center(
          child: Material(
            type: MaterialType.transparency,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Transform.translate(
                    offset: Offset(0, height * 0.6 * _rise.value),
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.0015)
                        ..rotateY(_flip.value),
                      child: showingBack
                          ? const _TicketBack()
                          : _TicketFront(
                              coupon: widget.coupon,
                              shine: _shine.value,
                            ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Opacity(
                    opacity: _caption.value,
                    child: Transform.translate(
                      offset: Offset(0, 16 * (1 - _caption.value)),
                      child: _Caption(
                        onClose: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 앞면. 목록과 같은 카드에 빛나는 테두리와 지나가는 광택을 더한다.
class _TicketFront extends StatelessWidget {
  const _TicketFront({required this.coupon, required this.shine});

  final Coupon coupon;

  /// 광택 진행(0~1). 0이면 시작 전, 1이면 다 지나감 — 둘 다 안 보인다.
  final double shine;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.55),
            blurRadius: 36,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Stack(
        children: [
          CouponCard(coupon: coupon),
          if (shine > 0 && shine < 1)
            Positioned.fill(
              child: IgnorePointer(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: const Alignment(-1, -0.6),
                        end: const Alignment(1, 0.6),
                        // 넓은 은은한 띠 + 가운데 선명한 심.
                        colors: [
                          Colors.white.withValues(alpha: 0),
                          Colors.white.withValues(alpha: 0.4),
                          Colors.white.withValues(alpha: 0.9),
                          Colors.white.withValues(alpha: 0.4),
                          Colors.white.withValues(alpha: 0),
                        ],
                        stops: const [0.22, 0.4, 0.5, 0.6, 0.78],
                        // 빛줄기를 카드 왼쪽 밖(-1)에서 오른쪽 밖(+1)까지 민다.
                        transform: _SlideGradient(shine * 2 - 1),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 그라디언트를 가로로 카드 폭 × dx만큼 민다.
class _SlideGradient extends GradientTransform {
  const _SlideGradient(this.dx);

  final double dx;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * dx, 0, 0);
}

/// 뒷면. 내용이 안 보이는 단색 티켓이라 뒤집히는 순간 "열린다"는 느낌을 준다.
class _TicketBack extends StatelessWidget {
  const _TicketBack();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 96,
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(18),
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.confirmation_number_rounded,
        color: Colors.white,
        size: 36,
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text(
          '쿠폰을 받았어요!',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          '마이페이지 > 내 쿠폰에서 쓸 수 있어요',
          style: TextStyle(
            color: AppColors.accent,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: 160,
          child: FilledButton(onPressed: onClose, child: const Text('확인')),
        ),
      ],
    );
  }
}
