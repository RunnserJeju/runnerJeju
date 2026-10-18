import 'dart:math';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/coupon.dart';
import '../theme/app_theme.dart';
import 'coupon_card.dart';

/// 쿠폰 획득 팝업. 스탬프(쾅 찍힘)와 달리, 티켓이 아래에서 미끄러져 올라와 한 번
/// 뒤집히며 앞면을 보여준다. 가벼운 진동 한 번과 리본 모양 색종이.
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
  static const _duration = Duration(milliseconds: 1500);

  /// 전체 진행(0~1) 중 티켓이 뒤집혀 앞면이 보이는 시점.
  static const _revealAt = 0.55;

  late final AnimationController _controller;
  late final ConfettiController _confetti;
  bool _revealed = false;

  // 올라오기: 화면 아래에서 제자리로.
  late final Animation<double> _rise;
  // 뒤집기: 뒷면(π)에서 앞면(0)으로.
  late final Animation<double> _flip;
  // 문구·버튼 등장.
  late final Animation<double> _caption;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration);
    _confetti = ConfettiController(duration: const Duration(milliseconds: 600));

    _rise = Tween(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.4, curve: Curves.easeOutCubic),
      ),
    );
    _flip = Tween(begin: pi, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.3, 0.75, curve: Curves.easeInOutBack),
      ),
    );
    _caption = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.7, 0.95, curve: Curves.easeOutCubic),
    );

    _controller.addListener(_onTick);
    _controller.forward();
  }

  void _onTick() {
    if (_revealed || _controller.value < _revealAt) return;
    _revealed = true;
    _confetti.play();
    HapticFeedback.lightImpact();
  }

  @override
  void dispose() {
    _controller.dispose();
    _confetti.dispose();
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
                  Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
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
                              : _TicketFront(coupon: widget.coupon),
                        ),
                      ),
                      ConfettiWidget(
                        confettiController: _confetti,
                        blastDirectionality: BlastDirectionality.explosive,
                        numberOfParticles: 24,
                        emissionFrequency: 0.4,
                        minBlastForce: 8,
                        maxBlastForce: 30,
                        gravity: 0.3,
                        colors: const [
                          AppColors.accent,
                          AppColors.tintAmber,
                          Colors.white,
                        ],
                      ),
                    ],
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

/// 앞면. 목록과 같은 카드에 빛나는 테두리만 더한다.
class _TicketFront extends StatelessWidget {
  const _TicketFront({required this.coupon});

  final Coupon coupon;

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
      child: CouponCard(coupon: coupon),
    );
  }
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
