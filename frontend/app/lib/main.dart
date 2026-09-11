import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:kakao_map_sdk/kakao_map_sdk.dart' show KakaoMapSdk;

import 'config/app_config.dart';
import 'screens/auth/auth_gate.dart';
import 'services/service_locator.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 키가 비어 있으면(dart-define으로 비운 경우) 지도는 안내 화면으로 대체된다.
  if (AppConfig.hasKakaoNativeAppKey) {
    KakaoSdk.init(nativeAppKey: AppConfig.kakaoNativeAppKey);
    await KakaoMapSdk.instance.initialize(AppConfig.kakaoNativeAppKey);
  }

  // clientId는 iOS에서만 필요하다 — Android는 패키지명+SHA-1로 콘솔이 자동 매칭한다.
  await GoogleSignIn.instance.initialize(
    clientId: Platform.isIOS ? AppConfig.googleIosClientId : null,
    serverClientId: AppConfig.googleServerClientId,
  );

  // 현위치 스트림. 권한이 이미 있으면 여기서 바로 열리고, 아니면 지도 탭에서
  // 권한을 물은 뒤 열린다. 기다리지 않는다 — 첫 화면은 위치 없이도 뜬다.
  unawaited(Services.instance.currentLocation.start());

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
