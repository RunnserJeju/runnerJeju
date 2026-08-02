import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../config/app_config.dart';
import '../../services/service_locator.dart';
import '../../theme/app_theme.dart';
import '../app_shell.dart';
import 'nickname_setup_screen.dart';

/// 카카오/구글 로그인, iOS에서는 애플 로그인도 함께 보여주는 첫 화면.
///
/// 애플 로그인은 iOS에서만 노출한다 — Android에서 요구되는 기능이 아니고,
/// iOS 심사 가이드라인(4.8, 소셜 로그인 제공 시 애플 로그인 동반 요구) 대응 목적이다.
/// 정사각형 배지를 Row로 가운데 정렬해서, iOS(3개)/Android(2개)든 개수와 무관하게
/// 항상 중앙에 모이게 한다 — 플랫폼별로 폭을 따로 계산할 필요가 없다.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _loading = false;

  Future<void> _login(Future<bool> Function() action) async {
    setState(() => _loading = true);
    try {
      final needsNickname = await action();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => needsNickname
              ? const NicknameSetupScreen()
              : const AppShell(),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _providerBadge({
    required Color background,
    required Widget icon,
    required Color spinnerColor,
    Color? borderColor,
    required VoidCallback? onPressed,
  }) {
    return Opacity(
      opacity: onPressed == null ? 0.5 : 1,
      child: Material(
        color: background,
        elevation: 3,
        shadowColor: Colors.black45,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: borderColor != null
              ? BorderSide(color: borderColor)
              : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onPressed,
          child: SizedBox(
            width: 64,
            height: 64,
            child: Center(
              child: _loading
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: spinnerColor,
                      ),
                    )
                  : icon,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.directions_run_rounded,
                color: AppColors.accent,
                size: 64,
              ),
              const SizedBox(height: 20),
              const Text(
                'Runners Jeju',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 64),
              if (!AppConfig.hasKakaoNativeAppKey)
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Text(
                    '카카오 로그인 키가 비어 있어요.\nconfig/app_config.dart의 kakaoNativeAppKey를 확인해 주세요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                  ),
                ),
              Row(
                children: [
                  const Expanded(child: Divider(color: Colors.white24)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      '간편 로그인',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  const Expanded(child: Divider(color: Colors.white24)),
                ],
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (AppConfig.hasKakaoNativeAppKey)
                    _providerBadge(
                      background: const Color(0xFFFEE500),
                      spinnerColor: Colors.black87,
                      icon: const SizedBox(
                        width: 28,
                        height: 28,
                        child: CustomPaint(
                          painter: _KakaoBubblePainter(color: Color(0xFF000000)),
                        ),
                      ),
                      onPressed: _loading
                          ? null
                          : () => _login(Services.instance.auth.loginWithKakao),
                    ),
                  if (AppConfig.hasKakaoNativeAppKey) const SizedBox(width: 18),
                  _providerBadge(
                    background: Colors.white,
                    spinnerColor: const Color(0xFF4285F4),
                    borderColor: const Color(0xFFE8EAED),
                    icon: SvgPicture.asset(
                      'assets/icons/google_logo.svg',
                      width: 26,
                      height: 26,
                    ),
                    onPressed: _loading
                        ? null
                        : () => _login(Services.instance.auth.loginWithGoogle),
                  ),
                  if (Platform.isIOS) ...[
                    const SizedBox(width: 18),
                    _providerBadge(
                      background: Colors.white,
                      spinnerColor: Colors.black,
                      borderColor: const Color(0xFFE8EAED),
                      icon: const Icon(
                        Icons.apple,
                        color: Colors.black,
                        size: 32,
                      ),
                      onPressed: _loading
                          ? null
                          : () => _login(Services.instance.auth.loginWithApple),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 카카오톡 말풍선 모양(통통한 몸통 + 왼쪽 아래 꼬리)을 직접 그린다.
/// Material의 Icons.chat_bubble_rounded는 각지고 밋밋해서 실제 카카오 BI 느낌이
/// 안 나 — 몸통을 거의 캡슐에 가깝게 둥글리고 꼬리를 곡선으로 붙여서 흉내낸다.
class _KakaoBubblePainter extends CustomPainter {
  const _KakaoBubblePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;
    final d = w < h ? w : h;

    // 몸통은 실제 카카오톡 말풍선처럼 옆으로 넓적한 캡슐형 — 정원(正圓)으로
    // 그리면 그냥 동그라미로 보여서 말풍선 느낌이 안 난다.
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(w / 2, h * 0.44),
        width: d * 0.94,
        height: d * 0.72,
      ),
      Radius.circular(d * 0.36),
    );

    // 꼬리는 몸통 아랫변과 확실히 겹치게 그린 뒤 union으로 합쳐서, winding
    // 방향에 따라 이가 빠지거나 이중선이 생기는 문제 없이 매끈한 실루엣
    // 하나로 붙게 한다.
    final tail = Path()
      ..moveTo(w * 0.30, h * 0.66)
      ..quadraticBezierTo(w * 0.28, h * 0.88, w * 0.16, h * 0.95)
      ..quadraticBezierTo(w * 0.38, h * 0.92, w * 0.42, h * 0.70)
      ..close();

    final path = Path.combine(
      PathOperation.union,
      Path()..addRRect(body),
      tail,
    );

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _KakaoBubblePainter oldDelegate) =>
      oldDelegate.color != color;
}
