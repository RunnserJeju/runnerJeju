import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../api/user_log_api.dart';
import '../models/user_log.dart';
import 'service_locator.dart';

/// 행동 로그를 남긴다. 화면에서 부르는 유일한 진입점.
///
/// 즉시 반환하고 절대 throw하지 않는다 — 로그가 화면 흐름을 막거나 깨면 안 된다.
/// 세션·플랫폼·앱 버전은 [UserLogService]가 채우므로 이름과 detail만 넘긴다.
///
/// ```dart
/// writeLog(LogName.bannerClick, detail: {LogKeys.noticeId: notice.id});
/// ```
void writeLog(LogName name, {Map<String, dynamic> detail = const {}}) {
  Services.instance.userLog.writeLog(name, detail: detail);
}

/// 행동 로그 큐·세션 관리. 로그는 모아서 배치로 보낸다([UserLogApi.writeUserLog]).
///
/// - 큐: 메모리 버퍼. [_flushCount]건이 차거나 [_flushEvery]마다, 그리고 앱이
///   백그라운드로 갈 때 보낸다. 실패하면 남겨 뒀다 다음에 재시도하고, [_queueCap]을
///   넘으면 오래된 것부터 버린다(로그 때문에 메모리가 자라면 안 된다).
/// - 세션: 앱 실행마다 새 id. 백그라운드에 [_sessionGap] 넘게 있다 돌아오면 새
///   세션으로 끊는다. 단 러닝 중이면 끊지 않는다(러닝 중 화면을 꺼 두는 게 보통).
/// - 러닝 이탈 감지: 러닝 시작 때 로컬에 표시를 남기고 종료 때 지운다. 다음 실행
///   때 표시가 남아 있으면 앱이 러닝 중 죽은 것이므로 run_abandon으로 기록한다.
class UserLogService with WidgetsBindingObserver {
  UserLogService(this._api, {FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final UserLogApi _api;
  final FlutterSecureStorage _storage;

  static const _flushCount = 20;
  static const _flushEvery = Duration(seconds: 5);
  static const _queueCap = 200;
  static const _sessionGap = Duration(minutes: 30);
  static const _activeRunKey = 'user_log.active_run';

  final List<UserLog> _queue = [];
  Timer? _flushTimer;
  bool _flushing = false;

  String _sessionId = _newSessionId();
  DateTime? _backgroundedAt;
  String _appVersion = '';

  /// 러닝 중인지. 세션을 끊을지 판단할 때 본다(러닝 화면이 시작/종료 때 알려 준다).
  bool _runActive = false;

  String get sessionId => _sessionId;
  String get appVersion => _appVersion;
  String get platform => Platform.isIOS ? 'ios' : 'android';

  /// 앱 시작 시 한 번. 앱 버전을 읽고 생명주기를 구독한 뒤 app_open을 남긴다.
  /// 지난 실행이 러닝 중 죽었으면 run_abandon도 여기서 남긴다.
  Future<void> start() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _appVersion = '${info.version}+${info.buildNumber}';
    } catch (_) {
      // 버전을 못 읽어도 로그는 남긴다(빈 문자열).
    }
    WidgetsBinding.instance.addObserver(this);

    final abandoned = await _readActiveRun();
    if (abandoned != null) {
      await _storage.delete(key: _activeRunKey);
      writeLog(
        LogName.runAbandon,
        detail: {
          LogKeys.reason: 'app_killed',
          if (abandoned.isNotEmpty) LogKeys.courseId: abandoned,
        },
      );
    }
    writeLog(LogName.appOpen, detail: {'os': Platform.operatingSystemVersion});
  }

  /// 로그 한 건을 큐에 넣는다. 즉시 반환하고 throw하지 않는다.
  void writeLog(LogName name, {Map<String, dynamic> detail = const {}}) {
    _queue.add(
      UserLog(
        name: name,
        detail: detail,
        sessionId: _sessionId,
        platform: platform,
        appVersion: _appVersion,
      ),
    );
    if (_queue.length > _queueCap) {
      _queue.removeRange(0, _queue.length - _queueCap);
    }

    if (_queue.length >= _flushCount) {
      unawaited(flush());
    } else {
      _flushTimer ??= Timer(_flushEvery, () => unawaited(flush()));
    }
  }

  /// 큐를 서버로 보낸다. 실패하면 큐에 남겨 다음에 다시 시도한다.
  Future<void> flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_flushing || _queue.isEmpty) return;
    _flushing = true;

    final batch = List<UserLog>.of(_queue.take(100));
    try {
      await _api.writeUserLog(batch);
      _queue.removeRange(0, batch.length);
    } catch (e) {
      debugPrint('[user_log] 전송 실패(${batch.length}건 보류): $e');
    } finally {
      _flushing = false;
    }
    // 남은 게 있으면(실패했거나 100건 넘게 쌓였으면) 다음 주기에 다시.
    if (_queue.isNotEmpty) {
      _flushTimer ??= Timer(_flushEvery, () => unawaited(flush()));
    }
  }

  // --- 러닝 이탈 감지 ------------------------------------------------------

  /// 러닝 화면이 시작 직후 부른다. 로컬 표시를 남겨 앱이 죽어도 흔적이 남게 한다.
  Future<void> markRunStarted({String? courseId}) async {
    _runActive = true;
    try {
      await _storage.write(key: _activeRunKey, value: courseId ?? '');
    } catch (_) {}
  }

  /// 러닝 화면이 정상 종료 직후 부른다.
  Future<void> markRunEnded() async {
    _runActive = false;
    try {
      await _storage.delete(key: _activeRunKey);
    } catch (_) {}
  }

  Future<String?> _readActiveRun() async {
    try {
      return await _storage.read(key: _activeRunKey);
    } catch (_) {
      return null;
    }
  }

  // --- 세션 ----------------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        _backgroundedAt = DateTime.now();
        // 백그라운드에서 죽을 수 있으니 지금 보낸다.
        unawaited(flush());
      case AppLifecycleState.resumed:
        final away = _backgroundedAt;
        _backgroundedAt = null;
        if (away != null &&
            !_runActive &&
            DateTime.now().difference(away) > _sessionGap) {
          _sessionId = _newSessionId();
          writeLog(LogName.appOpen, detail: {'resumed': true});
        }
      default:
        break;
    }
  }

  /// UUID v4. 패키지 없이 만든다 — 식별자 하나에 의존성을 늘리지 않으려고.
  static String _newSessionId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
