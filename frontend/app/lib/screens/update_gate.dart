import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../services/service_locator.dart';
import '../utils/app_version.dart';
import '../widgets/confirm_popup.dart';

/// 필수 업데이트 관문(MaterialApp.builder). 앱 버전이 서버의 최소 버전(app_settings)보다
/// 낮으면 [child](내비게이터 전체) 대신 시작 화면 배경 위에 닫을 수 없는 안내만 띄운다.
///
/// 시작을 늦추지 않는다 — 지난번 받아 둔 값으로 먼저 판단하고, 새 값이 오면 다시 본다.
/// 서버에 못 닿으면 가진 값 그대로라, 처음 설치했거나 오프라인이면 통과한다.
class UpdateGate extends StatefulWidget {
  const UpdateGate({super.key, required this.child});

  final Widget child;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  /// 시작 화면(네이티브 launch_background)과 같은 색.
  static const _splashRed = Color(0xFFD33216);

  String? _version;
  bool _blocked = false;

  @override
  void initState() {
    super.initState();
    Services.instance.appSettings.revision.addListener(_check);
    _readVersion();
  }

  @override
  void dispose() {
    Services.instance.appSettings.revision.removeListener(_check);
    super.dispose();
  }

  Future<void> _readVersion() async {
    try {
      _version = (await PackageInfo.fromPlatform()).version;
    } catch (_) {
      return; // 버전을 못 읽으면 막지 않는다.
    }
    _check();
  }

  void _check() {
    final version = _version;
    final minimum = Services.instance.appSettings.minVersion;
    if (!mounted || _blocked || version == null || minimum == null) return;
    if (!AppVersion.isBelow(version, minimum)) return;
    // 늦게 온 응답이 달리는 중인 러닝을 끊지 않게 한다. 다음 실행부터 막힌다.
    if (Services.instance.runFlow.isOpen) return;
    setState(() => _blocked = true);
  }

  Future<void> _openStore() async {
    if (Platform.isIOS) {
      await _launch(AppConfig.appStoreUrl);
      return;
    }
    if (!await _launch(AppConfig.playStoreAppUrl)) {
      await _launch(AppConfig.playStoreWebUrl);
    }
  }

  static Future<bool> _launch(String url) async {
    try {
      return await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_blocked) return widget.child;

    return Scaffold(
      backgroundColor: _splashRed,
      body: PopupFrame(
        title: '업데이트 안내',
        message: '안정적인 앱 기능 제공을 위해\n업데이트를 부탁드립니다',
        confirmLabel: '스토어로 이동',
        onConfirm: _openStore,
      ),
    );
  }
}
