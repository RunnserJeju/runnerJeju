import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../api/app_settings_api.dart';

/// 서버 원격 설정(GET /app-settings). 재배포 없이 DB 값으로 켜고 끈다.
///
/// 지도는 앱이 켜지자마자 만들어질 수 있어서 응답을 기다리지 않는다. 지난번 받은 값을
/// 파일에 두고 먼저 쓰고, 새 값은 받은 뒤 새로 만드는 화면부터 적용된다.
class AppSettingsService {
  AppSettingsService(this._api);

  final AppSettingsApi _api;
  Map<String, Object?> _values = const {};

  /// 안드로이드 카카오맵을 하이브리드 방식(HC)으로 띄울지. 기본은 켬 — 끌 때만 false가 온다.
  bool get androidMapHybridComposition =>
      _values['android_map_hybrid_composition'] != false;

  /// 저장해 둔 값을 읽고, 새 값은 기다리지 않고 받아 둔다.
  Future<void> start() async {
    final file = await _file();
    try {
      if (file != null && await file.exists()) {
        _values = Map<String, Object?>.from(
          jsonDecode(await file.readAsString()) as Map,
        );
      }
    } catch (_) {
      // 못 읽는 파일은 기본값으로 시작한다.
    }
    unawaited(_refresh(file));
  }

  Future<void> _refresh(File? file) async {
    try {
      final values = await _api.fetch();
      _values = values;
      await file?.writeAsString(jsonEncode(values));
    } catch (e) {
      debugPrint('[app_settings] 받기 실패: $e');
    }
  }

  static Future<File?> _file() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return File('${dir.path}/app_settings.json');
    } catch (_) {
      return null;
    }
  }
}
