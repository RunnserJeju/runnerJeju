import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/coupon.dart';
import '../theme/app_theme.dart';
import 'coupon_card.dart';

/// 쿠폰 뽑기 팝업. 스탬프(쾅 찍힘·색종이)와 달리, 티켓이 아래에서 미끄러져 올라와 잠깐
/// 흔들리다(두구두구) 한 번 뒤집히며 앞면을 보여준다.
/// - 당첨: 쿠폰 앞면 위로 빛줄기가 한 번 훑고 지나간다. 가벼운 진동 한 번.
/// - 낙첨·재고 소진: 회색 티켓에 '다음 기회에..'. 광택 없음. 둘 다 같은 연출.
/// 뒷면은 결과와 상관없이 같은 색이라 뒤집히기 전에는 결과를 알 수 없다.
/// 연출 중에 화면 어디를 눌러도(티켓 안팎 구분 없이) 끝 장면으로 건너뛰고, 끝난 뒤에
/// 바깥을 누르면 닫힌다. 바깥을 눌렀다고 결과를 못 보고 닫히는 일은 없다.
Future<void> showCouponCelebration(BuildContext context, Coupon coupon) =>
    _show(context, _Won(coupon));

Future<void> showCouponMiss(
  BuildContext context, {
  required String name,
  required String benefit,
}) => _show(context, _Miss(name: name, benefit: benefit));

Future<void> _show(BuildContext context, _Outcome outcome) {
  return showGeneralDialog<void>(
    context: context,
    // 바깥 터치는 닫기가 아니라 건너뛰기(_CouponCelebrationState._onTap)로 받는다.
    barrierDismissible: false,
    barrierLabel: '닫기',
    barrierColor: Colors.black.withValues(alpha: 0.7),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, _, _) => _CouponCelebration(outcome: outcome),
    transitionBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

sealed class _Outcome {
  const _Outcome();
}

class _Won extends _Outcome {
  const _Won(this.coupon);

  final Coupon coupon;
}

class _Miss extends _Outcome {
  const _Miss({required this.name, required this.benefit});

  final String name;
  final String benefit;
}

class _CouponCelebration extends StatefulWidget {
  const _CouponCelebration({required this.outcome});

  final _Outcome outcome;

  @override
  State<_CouponCelebration> createState() => _CouponCelebrationState();
}

class _CouponCelebrationState extends State<_CouponCelebration>
    with SingleTickerProviderStateMixin {
  // 구간은 ms로 적는다. 전체 길이는 광택이 끝나는 시점. 낙첨은 광택이 없어 캡션에서 끝난다.
  static const _totalMs = 2320;
  static const _riseMs = (0, 600);
  static const _wobbleMs = (450, 1050);
  static const _flipMs = (1000, 1675);
  static const _shineMs = (1570, 2320); // 0.75초
  static const _captionMs = (1600, 1975);

  /// 티켓이 뒤집혀 앞면이 보이는 시점(진동).
  static const _revealAt = 1337 / _totalMs;

  static Interval _interval((int, int) ms, Curve curve) =>
      Interval(ms.$1 / _totalMs, ms.$2 / _totalMs, curve: curve);

  late final AnimationController _controller;
  bool _revealed = false;

  // 올라오기: 화면 아래에서 제자리로.
  late final Animation<double> _rise;
  // 흔들기: 뒤집히기 전 두구두구. 0→1 진행을 사인파로 바꿔 쓴다.
  late final Animation<double> _wobble;
  // 뒤집기: 뒷면(π)에서 앞면(0)으로.
  late final Animation<double> _flip;
  // 광택: 앞면이 보인 뒤 빛줄기가 왼쪽에서 오른쪽으로 지나간다(0→1). 당첨만.
  late final Animation<double> _shine;
  // 문구·버튼 등장.
  late final Animation<double> _caption;

  bool get _won => widget.outcome is _Won;

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
    _wobble = CurvedAnimation(
      parent: _controller,
      curve: _interval(_wobbleMs, Curves.linear),
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
    if (_won) {
      HapticFeedback.lightImpact();
    } else {
      HapticFeedback.selectionClick();
    }
  }

  /// 연출 중이면 끝 장면으로 건너뛰고, 끝났으면 닫는다. 확인 버튼은 자기 탭을 먼저 먹는다.
  void _onTap() {
    if (_controller.isCompleted) {
      Navigator.of(context).pop();
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 흔들림 각도(rad). 세 번 좌우로 흔들고, 시작·끝은 0이 되게 사인 포락선을 씌운다.
  double get _wobbleAngle {
    final t = _wobble.value;
    if (t <= 0 || t >= 1) return 0;
    return sin(t * pi * 6) * sin(t * pi) * 0.07;
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // 뒤집히는 동안 뒷면(앞면의 거울상)을 보여주는 대신 뒷면 카드를 따로 그린다.
        final showingBack = _flip.value > pi / 2;

        // 화면 전체가 탭을 받는다. 티켓은 IgnorePointer로 감싸 카드 안쪽 탭도 여기로 온다.
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _onTap,
          child: Center(
            child: Material(
              type: MaterialType.transparency,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    IgnorePointer(
                      child: Transform.translate(
                        offset: Offset(0, height * 0.6 * _rise.value),
                        child: Transform.rotate(
                          angle: _wobbleAngle,
                          child: Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.identity()
                              ..setEntry(3, 2, 0.0015)
                              ..rotateY(_flip.value),
                            child: showingBack
                                ? const _TicketBack()
                                : switch (widget.outcome) {
                                    _Won(:final coupon) => _TicketFront(
                                      coupon: coupon,
                                      shine: _shine.value,
                                    ),
                                    _Miss(:final name, :final benefit) =>
                                      _MissTicketFront(
                                        name: name,
                                        benefit: benefit,
                                      ),
                                  },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Opacity(
                      opacity: _caption.value,
                      child: Transform.translate(
                        offset: Offset(0, 16 * (1 - _caption.value)),
                        child: _Caption(
                          won: _won,
                          onClose: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 당첨 앞면. 목록과 같은 카드에 빛나는 테두리와 지나가는 광택을 더한다.
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

/// 낙첨 앞면. 쿠폰 카드와 같은 티켓 모양이지만 전부 회색이고 빛나지 않는다.
class _MissTicketFront extends StatelessWidget {
  const _MissTicketFront({required this.name, required this.benefit});

  final String name;
  final String benefit;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.line),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textFaint,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        benefit,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.muted,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '이번엔 당첨되지 않았어요',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textFaint,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const CouponPerforation(),
              Container(
                width: 84,
                color: AppColors.muted.withValues(alpha: 0.25),
                alignment: Alignment.center,
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.sentiment_neutral_rounded,
                      color: AppColors.muted,
                    ),
                    SizedBox(height: 6),
                    Text(
                      '다음 기회에..',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
/// 당첨·낙첨 모두 같은 색 — 뒤집히기 전에 결과가 새면 뽑기가 아니다.
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
  const _Caption({required this.won, required this.onClose});

  final bool won;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          won ? '쿠폰을 받았어요!' : '다음 기회에..',
          style: TextStyle(
            color: won ? Colors.white : AppColors.textFaint,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          won ? '마이페이지 > 내 쿠폰에서 쓸 수 있어요' : '아쉽지만 이번엔 당첨되지 않았어요',
          style: TextStyle(
            color: won ? AppColors.accent : AppColors.muted,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: 160,
          child: won
              ? FilledButton(onPressed: onClose, child: const Text('확인'))
              : FilledButton(
                  onPressed: onClose,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.muted,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('확인'),
                ),
        ),
      ],
    );
  }
}
