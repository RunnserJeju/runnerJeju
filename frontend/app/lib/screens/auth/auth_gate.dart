import 'package:flutter/material.dart';

import '../../services/service_locator.dart';
import '../app_shell.dart';
import 'login_screen.dart';

/// 앱 시작점: 저장된 토큰이 있으면 바로 홈으로, 없으면 로그인 화면으로 보낸다.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: Services.instance.auth.isLoggedIn,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return snapshot.data == true ? const AppShell() : const LoginScreen();
      },
    );
  }
}
