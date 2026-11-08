import 'dart:io' show Platform;

import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel('runners_jeju/exit_info');

/// 직전 프로세스의 종료 사유(Android 11+, ExitInfoChannel.kt). 그 밖에는 null.
Future<Map<String, Object?>?> lastExitInfo() async {
  if (!Platform.isAndroid) return null;
  try {
    final info = await _channel.invokeMapMethod<String, Object?>('lastExit');
    if (info == null) return null;
    final at = info['at'];
    return {
      ...info,
      if (at is int)
        'at': DateTime.fromMillisecondsSinceEpoch(at).toUtc().toIso8601String(),
    };
  } catch (_) {
    return null;
  }
}
