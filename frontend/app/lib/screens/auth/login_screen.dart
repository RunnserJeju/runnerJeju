import 'dart:io';

import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../services/service_locator.dart';
import '../../theme/app_theme.dart';
import '../app_shell.dart';
import 'nickname_setup_screen.dart';

/// 카카오/구글 로그인, iOS에서는 애플 로그인도 함께 보여주는 첫 화면.
///
/// 애플 로그인은 iOS에서만 노출한다 — Android에서 요구되는 기능이 아니고,
/// iOS 심사 가이드라인(4.8, 소셜 로그인 제공 시 애플 로그인 동반 요구) 대응 목적이다.
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
              const SizedBox(height: 56),
              if (!AppConfig.hasKakaoNativeAppKey)
                Text(
                  '카카오 로그인 키가 비어 있어요.\nconfig/app_config.dart의 kakaoNativeAppKey를 확인해 주세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                )
              else
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _loading
                        ? null
                        : () => _login(Services.instance.auth.loginWithKakao),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFEE500),
                      foregroundColor: Colors.black87,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            '카카오로 로그인',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                  ),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading
                      ? null
                      : () => _login(Services.instance.auth.loginWithGoogle),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    side: const BorderSide(color: Color(0xFFDADCE0)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'Google로 로그인',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                ),
              ),
              if (Platform.isIOS) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _loading
                        ? null
                        : () => _login(Services.instance.auth.loginWithApple),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'Apple로 로그인',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
