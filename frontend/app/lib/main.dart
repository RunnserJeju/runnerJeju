import 'package:flutter/material.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:kakao_map_sdk/kakao_map_sdk.dart' show KakaoMapSdk;

import 'config/app_config.dart';
import 'screens/auth/auth_gate.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();


  // 키가 없으면 지도는 안내 화면으로 대체
  if (AppConfig.hasKakaoNativeAppKey) {
    KakaoSdk.init(nativeAppKey: AppConfig.kakaoNativeAppKey);
    await KakaoMapSdk.instance.initialize(AppConfig.kakaoNativeAppKey);
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
