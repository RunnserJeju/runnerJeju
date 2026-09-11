import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../config/app_config.dart';
import '../../services/service_locator.dart';
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

/// 시안 배경색(러너스제주 브랜드 레드). 로고 이미지의 배경도 같은 값이라
/// 이미지와 배경의 경계가 보이지 않는다.
const Color _brandRed = Color(0xFFD33216);

class _LoginScreenState extends State<LoginScreen> {
  bool _loading = false;

  Future<void> _login(Future<bool> Function() action) async {
    setState(() => _loading = true);
    try {
      final needsNickname = await action();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              needsNickname ? const NicknameSetupScreen() : const AppShell(),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 시안의 소셜 로그인 배지 — 52pt 정사각형에 반경 8.
  /// 배경이 진한 레드라 흰 배지가 그 자체로 충분히 떠 보여서, 시안대로
  /// 그림자와 테두리는 두지 않는다.
  Widget _providerBadge({
    required Color background,
    required Widget icon,
    required VoidCallback? onPressed,
  }) {
    return Material(
      color: background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onPressed,
        child: SizedBox(width: 52, height: 52, child: Center(child: icon)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 시안(폭 390pt)의 로고 폭은 273pt. 좁은 기기에서도 좌우 여백이 남도록
    // 비율로 잡되, 태블릿에서 과하게 커지지 않게 상한만 둔다.
    final width = MediaQuery.sizeOf(context).width;
    final logoWidth = math.min(width * 0.7, 320.0);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // 배경이 진한 레드여서 상태바 아이콘은 밝은 쪽이어야 읽힌다.
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _brandRed,
        body: Stack(
          children: [
            SafeArea(
              child: Stack(
                children: [
                  // 로고와 로그인 배지를 한 덩어리로 묶어 배치한다. 시안에서 이 덩어리는
                  // 정중앙보다 살짝 위에 있어서(중심이 화면 높이의 약 48% 지점) 그만큼
                  // 올려 잡았다. 약관 문구는 아래에 따로 고정되므로 이 높이와 무관하다.
                  Align(
                    alignment: const Alignment(0, -0.1),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/images/login_logo.png',
                          width: logoWidth,
                        ),
                        const SizedBox(height: 43),
                        // 개발자용 안내라 디버그 빌드에서만 보인다.
                        if (kDebugMode && !AppConfig.hasKakaoNativeAppKey)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
                            child: Text(
                              '카카오 로그인 키가 비어 있어요.\nconfig/app_config.dart의 kakaoNativeAppKey를 확인해 주세요.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (AppConfig.hasKakaoNativeAppKey)
                              _providerBadge(
                                background: const Color(0xFFFEE500),
                                icon: const SizedBox(
                                  width: 28,
                                  height: 26,
                                  child: CustomPaint(
                                    painter: _KakaoBubblePainter(
                                      color: Color(0xFF000000),
                                    ),
                                  ),
                                ),
                                onPressed: _loading
                                    ? null
                                    : () => _login(
                                        Services.instance.auth.loginWithKakao,
                                      ),
                              ),
                            if (AppConfig.hasKakaoNativeAppKey)
                              const SizedBox(width: 11),
                            _providerBadge(
                              background: Colors.white,
                              icon: SvgPicture.asset(
                                'assets/icons/google_logo.svg',
                                width: 25,
                                height: 25,
                              ),
                              onPressed: _loading
                                  ? null
                                  : () => _login(
                                      Services.instance.auth.loginWithGoogle,
                                    ),
                            ),
                            if (Platform.isIOS) ...[
                              const SizedBox(width: 11),
                              _providerBadge(
                                background: Colors.white,
                                icon: const Icon(
                                  Icons.apple,
                                  color: Colors.black,
                                  size: 30,
                                ),
                                onPressed: _loading
                                    ? null
                                    : () => _login(
                                        Services.instance.auth.loginWithApple,
                                      ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
                      child: Text(
                        '계속 진행 시 서비스 이용약관 및\n개인정보처리방침에 동의합니다',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFE0E0E0),
                          fontSize: 12,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 진행 표시는 배지마다 스피너를 돌리는 대신 화면을 덮는 팝업 하나로
            // 보여준다 — 배지 세 개에서 스피너가 동시에 도는 게 어색하고,
            // 처리 중에 다른 제공자를 눌러 로그인이 겹치는 것도 막아야 한다.
            if (_loading) ...[
              const Positioned.fill(
                child: ModalBarrier(
                  color: Color(0x8A000000),
                  dismissible: false,
                ),
              ),
              const Center(child: _LoginProgressCard()),
            ],
          ],
        ),
      ),
    );
  }
}

/// 로그인 처리 중 화면 가운데 뜨는 진행 팝업.
class _LoginProgressCard extends StatelessWidget {
  const _LoginProgressCard();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _brandRed,
              ),
            ),
            SizedBox(width: 12),
            Text(
              '로그인 중...',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF101114),
              ),
            ),
          ],
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
