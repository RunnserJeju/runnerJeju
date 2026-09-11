import 'package:flutter/material.dart';

import '../../services/service_locator.dart';
import '../app_shell.dart';
import 'login_screen.dart';

/// 앱 시작점: 저장된 토큰이 있으면 바로 홈으로, 없으면 로그인 화면으로 보낸다.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  /// 한 번만 묻는다. build마다 다시 물으면 리빌드 때마다 스피너가 뜨고 그
  /// 아래 AppShell(탭·지도)이 통째로 다시 만들어진다.
  late final Future<bool> _isLoggedIn = Services.instance.auth.isLoggedIn;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isLoggedIn,
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
