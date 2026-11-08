import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../api/crash_api.dart';
import '../utils/uuid.dart';
import 'run_tracker.dart';
import 'user_log_service.dart';

/// 크래시 콜스택을 서버로 올린다.
///
/// 수집은 네이티브가 한다 — Android CrashCollector.kt(Kotlin 크래시, OS 종료 기록의 C++
/// 크래시·ANR 덤프), iOS CrashDiagnostics(MetricKit). 둘 다 기기 안 보관함(crash_outbox)에
/// `<id>.json` + `<id>.dump`로 쌓고, 여기서 앱을 켤 때마다 비운다. Dart 예외는 앱을 죽이지
/// 않지만 스택을 보려고 같은 보관함에 넣는다.
///
/// 크래시 순간의 러닝 상태는 그때 남길 수 없어서, 상태가 바뀔 때마다 run_state.json에
/// 적어 두고 다음 실행 때 리포트에 붙인다.
class CrashReporter {
  CrashReporter(this._api, this._userLog, this._tracker);

  final CrashApi _api;
  final UserLogService _userLog;
  final RunTracker _tracker;

  static const MethodChannel _channel = MethodChannel('runners_jeju/crash');

  static const int _maxDartErrorsPerSession = 5;
  static const int _maxUploadsPerPass = 10;
  static const Duration _dropAfter = Duration(days: 30);
  static const int _stackMaxChars = 64 * 1024;

  Directory? _outbox;
  File? _runStateFile;

  /// 지난 실행이 마지막으로 남긴 러닝 상태. 이번 실행이 덮어쓰기 전에 읽어 둔다.
  Map<String, Object?>? _previousRun;
  RunStatus? _writtenStatus;

  final Set<String> _seenDartErrors = {};
  final List<Map<String, Object?>> _pendingDartErrors = [];
  bool _uploading = false;

  Future<void> start() async {
    _installDartHooks();
    try {
      final outbox = await _channel.invokeMethod<String>('outboxDir');
      if (outbox == null) return;
      _outbox = Directory(outbox);
      final support = await getApplicationSupportDirectory();
      _runStateFile = File('${support.path}/run_state.json');
      _previousRun = await _readRunState();
      // 지난 상태를 읽었으니 바로 이번 실행 상태로 덮는다. 안 그러면 지난번에 달리다
      // 죽은 '러닝 중'이 남아, 이번 실행의 크래시에도 잘못 붙는다.
      _tracker.addListener(_onTrackerChanged);
      _onTrackerChanged();
      for (final meta in _pendingDartErrors) {
        await _write(meta);
      }
      _pendingDartErrors.clear();
      await _channel.invokeMethod<int>('collect');
    } catch (_) {
      return; // 수집을 못 해도 앱은 그대로 돈다.
    }
    await upload();
  }

  /// 디버그 확인용. 앱이 실제로 죽는다(type: java | native | anr, iOS는 무시하고 크래시).
  Future<void> debugCrash(String type) =>
      _channel.invokeMethod('testCrash', {'type': type});

  // --- 러닝 상태 ------------------------------------------------------------

  Future<Map<String, Object?>?> _readRunState() async {
    try {
      final file = _runStateFile;
      if (file == null || !await file.exists()) return null;
      return jsonDecode(await file.readAsString()) as Map<String, Object?>;
    } catch (_) {
      return null;
    }
  }

  Map<String, Object?> _runSnapshot() => {
    'status': _tracker.status.name,
    'course_id': ?_tracker.targetCourse?.id,
    'started_at': ?_tracker.startedAt?.toUtc().toIso8601String(),
    'interrupted': _tracker.interruption != null,
    'at': DateTime.now().toUtc().toIso8601String(),
  };

  void _onTrackerChanged() {
    if (_tracker.status == _writtenStatus) return;
    _writtenStatus = _tracker.status;
    final file = _runStateFile;
    if (file == null) return;
    unawaited(file.writeAsString(jsonEncode(_runSnapshot())).catchError((_) => file));
  }

  // --- Dart 예외 ------------------------------------------------------------

  void _installDartHooks() {
    final previousFlutter = FlutterError.onError;
    FlutterError.onError = (details) {
      previousFlutter?.call(details);
      _recordDartError(details.exception, details.stack);
    };
    final previousPlatform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      _recordDartError(error, stack);
      return previousPlatform?.call(error, stack) ?? false;
    };
  }

  void _recordDartError(Object error, StackTrace? stack) {
    final trace = stack?.toString() ?? '';
    final key = '${error.runtimeType}:${trace.split('\n').first}';
    if (!_seenDartErrors.add(key) ||
        _seenDartErrors.length > _maxDartErrorsPerSession) {
      return;
    }
    final summary = '${error.runtimeType}: $error';
    final meta = <String, Object?>{
      'id': newUuidV4(),
      'kind': 'dart_error',
      'occurred_at': DateTime.now().toUtc().toIso8601String(),
      'summary': summary.length > 500 ? summary.substring(0, 500) : summary,
      'stack': trace.length > _stackMaxChars
          ? trace.substring(0, _stackMaxChars)
          : trace,
      'device': _userLog.device,
      'os_version': Platform.operatingSystemVersion,
      'context': {'run': _runSnapshot()},
    };
    if (_outbox == null) {
      _pendingDartErrors.add(meta);
      return;
    }
    unawaited(_write(meta).then((_) => upload()).catchError((_) {}));
  }

  Future<void> _write(Map<String, Object?> meta) async {
    final dir = _outbox;
    if (dir == null) return;
    final tmp = File('${dir.path}/${meta['id']}.json.tmp');
    await tmp.writeAsString(jsonEncode(meta));
    await tmp.rename('${dir.path}/${meta['id']}.json');
  }

  // --- 업로드 ---------------------------------------------------------------

  /// 보관함을 비운다. 실패하면 남겨 두고 다음 실행 때 다시 올린다.
  Future<void> upload() async {
    final dir = _outbox;
    if (dir == null || _uploading) return;
    _uploading = true;
    try {
      final metas = (await dir.list().toList())
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .take(_maxUploadsPerPass)
          .toList();
      for (final file in metas) {
        if (!await _uploadOne(file)) break;
      }
    } catch (_) {
      // 다음 실행 때 다시.
    } finally {
      _uploading = false;
    }
  }

  /// 한 건을 올린다. 계속 진행해도 되면 true, 네트워크 등으로 멈춰야 하면 false.
  Future<bool> _uploadOne(File metaFile) async {
    final base = metaFile.path.substring(0, metaFile.path.length - '.json'.length);
    final dumpFile = File('$base.dump');

    Future<void> discard() async {
      for (final file in [metaFile, dumpFile]) {
        if (await file.exists()) await file.delete();
      }
    }

    final Map<String, Object?> meta;
    try {
      meta = jsonDecode(await metaFile.readAsString()) as Map<String, Object?>;
    } catch (_) {
      await discard(); // 못 읽는 파일은 남겨 둬도 영원히 못 읽는다.
      return true;
    }

    final occurredAt = DateTime.tryParse(meta['occurred_at'] as String? ?? '');
    if (occurredAt == null || DateTime.now().difference(occurredAt) > _dropAfter) {
      await discard();
      return true;
    }

    // 네이티브가 남긴 크래시에는 지난 실행의 러닝 상태를 붙인다. 그 상태가 크래시보다
    // 나중에 적힌 것이면(크래시 뒤 다른 실행에서 달렸으면) 그 크래시의 상태가 아니라 뺀다.
    final context = Map<String, Object?>.from(
      meta['context'] as Map? ?? const {},
    );
    final previousRun = _previousRun;
    final runAt = DateTime.tryParse(previousRun?['at'] as String? ?? '');
    if (!context.containsKey('run') &&
        previousRun != null &&
        runAt != null &&
        !runAt.isAfter(occurredAt)) {
      context['run'] = previousRun;
    }
    meta['context'] = context;

    try {
      final dumpGz = await dumpFile.exists()
          ? await Isolate.run(() => gzip.encode(File(dumpFile.path).readAsBytesSync()))
          : null;
      await _api.upload(meta: jsonEncode(meta), dumpGz: dumpGz);
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      // 형식 오류·너무 큼은 다시 보내도 같다. 버린다.
      if (status == 413 || status == 422) {
        await discard();
        return true;
      }
      return false;
    }
    await discard();
    return true;
  }
}
