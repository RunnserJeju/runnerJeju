import 'dart:math';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/run_stamp.dart';
import '../theme/app_theme.dart';
import 'stamp_badge.dart';

/// 스탬프 획득 팝업. 도장이 쾅 찍히는 순간 진동·화면 흔들림·색종이가 같이 터진다.
Future<void> showStampCelebration(BuildContext context, RunStamp stamp) async {
  // 도안이 늦게 뜨면 빈 원이 찍히므로 먼저 받아 둔다. 실패해도 기본 도안으로 진행.
  final url = stamp.imageUrl;
  if (url != null) {
    try {
      await precacheImage(NetworkImage(url), context);
    } catch (_) {}
  }
  if (!context.mounted) return;

  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '닫기',
    barrierColor: Colors.black.withValues(alpha: 0.7),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, _, _) => _StampCelebration(stamp: stamp),
    transitionBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

class _StampCelebration extends StatefulWidget {
  const _StampCelebration({required this.stamp});

  final RunStamp stamp;

  @override
  State<_StampCelebration> createState() => _StampCelebrationState();
}

class _StampCelebrationState extends State<_StampCelebration>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 1400);

  /// 전체 진행(0~1) 중 도장이 바닥에 닿는 시점.
  static const _impactAt = 0.3;

  late final AnimationController _controller;
  late final ConfettiController _confetti;
  bool _impacted = false;

  // 내려찍기: 크고 기울어진 채로 떨어져 원래 크기로.
  late final Animation<double> _scale;
  late final Animation<double> _tilt;
  late final Animation<double> _fadeIn;
  // 찍힌 뒤 흔들림 세기(1→0).
  late final Animation<double> _shake;
  // 문구·버튼 등장.
  late final Animation<double> _caption;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration);
    _confetti = ConfettiController(duration: const Duration(milliseconds: 500));

    _scale = TweenSequence([
      TweenSequenceItem(
        tween: Tween(
          begin: 2.6,
          end: 0.92,
        ).chain(CurveTween(curve: Curves.easeInCubic)),
        weight: _impactAt,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.92,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 1 - _impactAt,
      ),
    ]).animate(_controller);
    _tilt = TweenSequence([
      TweenSequenceItem(
        tween: Tween(
          begin: -0.4,
          end: -0.12,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: _impactAt,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: -0.12,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 1 - _impactAt,
      ),
    ]).animate(_controller);
    _fadeIn = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, _impactAt * 0.5),
    );
    _shake = Tween(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(_impactAt, _impactAt + 0.25),
      ),
    );
    _caption = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.5, 0.8, curve: Curves.easeOutCubic),
    );

    _controller.addListener(_onTick);
    _controller.forward();
  }

  void _onTick() {
    if (_impacted || _controller.value < _impactAt) return;
    _impacted = true;
    _confetti.play();
    // 쿵-쿵 두 번. Android는 기기에 따라 약하게 느껴질 수 있다.
    HapticFeedback.heavyImpact();
    Future.delayed(
      const Duration(milliseconds: 120),
      HapticFeedback.mediumImpact,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _confetti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final shake = _controller.value < _impactAt
            ? 0.0
            : sin(_controller.value * 90) * 10 * _shake.value;

        return Transform.translate(
          offset: Offset(shake, 0),
          child: Center(
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      Opacity(
                        opacity: _fadeIn.value,
                        child: Transform.rotate(
                          angle: _tilt.value,
                          child: Transform.scale(
                            scale: _scale.value,
                            child: _StampFace(stamp: widget.stamp),
                          ),
                        ),
                      ),
                      ConfettiWidget(
                        confettiController: _confetti,
                        blastDirectionality: BlastDirectionality.explosive,
                        numberOfParticles: 40,
                        emissionFrequency: 0.6,
                        minBlastForce: 10,
                        maxBlastForce: 40,
                        gravity: 0.25,
                        colors: const [
                          AppColors.accent,
                          AppColors.tintAmber,
                          AppColors.tintBlue,
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
                        courseName: widget.stamp.courseName,
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

/// 팝업용 큰 도안. 라벨은 아래 문구가 대신하므로 원만 그린다.
class _StampFace extends StatelessWidget {
  const _StampFace({required this.stamp});

  final RunStamp stamp;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.6),
            blurRadius: 40,
            spreadRadius: 4,
          ),
        ],
      ),
      child: StampBadge(stamp: stamp, size: 180, showLabel: false),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption({required this.courseName, required this.onClose});

  final String courseName;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text(
          '완주 스탬프 획득!',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          courseName,
          style: const TextStyle(
            color: AppColors.accent,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 24),
        // 테마 버튼은 가로를 꽉 채우므로 폭을 줄인다.
        SizedBox(
          width: 160,
          child: FilledButton(onPressed: onClose, child: const Text('확인')),
        ),
      ],
    );
  }
}
