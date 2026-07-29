import 'package:flutter/material.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:kakao_map_plugin/kakao_map_plugin.dart';

import 'config/app_config.dart';
import 'screens/auth/auth_gate.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // 키가 없으면 지도 위젯이 안내 화면으로 대체되므로 앱 자체는 계속 뜬다.
  if (AppConfig.hasKakaoMapKey) {
    AuthRepository.initialize(appKey: AppConfig.kakaoMapKey);
  }

  // 키가 없으면 로그인 버튼에서 안내만 하고 실제 SDK 호출은 막는다.
  if (AppConfig.hasKakaoNativeAppKey) {
    KakaoSdk.init(nativeAppKey: AppConfig.kakaoNativeAppKey);
  }

  runApp(const RunnersJejuApp());
}

class RunnersJejuApp extends StatelessWidget {
  const RunnersJejuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Runners Jeju',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const AuthGate(),
    );
  }
}
