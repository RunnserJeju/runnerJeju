import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;

/// Firebase 프로젝트 연결 값. 푸시(FCM)에만 쓴다. Firebase 콘솔의 앱 설정과 같은 값이고
/// 비밀이 아니다(앱에 그대로 들어간다). 앱을 다시 등록하면 여기를 고친다.
abstract final class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => switch (defaultTargetPlatform) {
    TargetPlatform.android => android,
    TargetPlatform.iOS => ios,
    _ => throw UnsupportedError('Firebase는 Android와 iOS에서만 쓴다.'),
  };

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDGNXjVo4MCvPMM8qTUa4UakCdjdDS9jP0',
    appId: '1:1090471391353:android:5de25bcce5ecade64fa4a8',
    messagingSenderId: '1090471391353',
    projectId: 'runners-jeju-505808',
    storageBucket: 'runners-jeju-505808.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDoBdv9uPIxQT9eP5n8qDV3muZowSyt3Cg',
    appId: '1:1090471391353:ios:c6c9225a66a1a52c4fa4a8',
    messagingSenderId: '1090471391353',
    projectId: 'runners-jeju-505808',
    storageBucket: 'runners-jeju-505808.firebasestorage.app',
    iosBundleId: 'com.runnersjeju.runnersJeju',
  );
}
