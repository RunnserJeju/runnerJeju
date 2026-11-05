import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/geo_point.dart';
import '../models/run_record.dart';

/// 러닝 중 기록을 기기에 이어 쓰는 일지. 앱이 죽어도 여기까지 달린 것은 남는다.
///
/// JSONL 한 줄이 이벤트 하나다. 점이 들어올 때마다 덮어쓰지 않고 끝에 붙이므로
/// 한 번 쓰기가 수십 바이트고, 쓰기는 I/O 스레드에서 돌아 화면을 막지 않는다.
/// 쓰는 도중 죽으면 마지막 줄만 잘릴 수 있어 읽을 때 파싱 안 되는 줄은 버린다.
///
/// 수명: 러닝 시작에 만들고, 업로드가 서버에 받아들여지면 지운다. 종료와 업로드
/// 사이에 죽어도 기록이 남아야 하므로 종료 시점에는 지우지 않는다.
class RunJournal {
  static const _fileName = 'active_run.jsonl';

  IOSink? _sink;

  /// 러닝이 진행 중인지(시작~종료). 종료된 러닝의 업로드가 늦게 끝났을 때 그새
  /// 시작한 다음 러닝의 일지를 지우지 않으려고 본다.
  bool _active = false;

  /// 파일을 여는 중이면 그 작업. 쓰기는 전부 이 뒤에 줄을 선다 — 열리기 전에
  /// 들어온 점도 순서대로 남는다.
  Future<void> _ready = Future.value();

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// 새 러닝. 이전 일지가 남아 있으면 버린다(이미 처리된 것).
  void begin({String? courseId, String? courseName}) {
    _active = true;
    _ready = _open();
    write({
      't': 'start',
      'at': _now(),
      'course_id': ?courseId,
      'course_name': ?courseName,
    });
  }

  Future<void> _open() async {
    await _close();
    try {
      final file = await _file();
      _sink = file.openWrite(mode: FileMode.write);
    } catch (_) {
      _sink = null; // 일지를 못 열어도 러닝은 계속된다.
    }
  }

  void write(Map<String, Object?> event) {
    _ready = _ready.then((_) {
      try {
        _sink?.writeln(jsonEncode(event));
      } catch (_) {}
    });
  }

  void point(GeoPoint point, {required double distanceMeters}) {
    write({'t': 'p', ...point.toJson(), 'd': distanceMeters});
  }

  void startedAt(DateTime at) => write({'t': 'started', 'at': _iso(at)});
  void pause() => write({'t': 'pause', 'at': _now()});
  void resume() => write({'t': 'resume', 'at': _now()});

  void finish({
    required DateTime startedAt,
    required DateTime endedAt,
    required double distanceMeters,
    required Duration duration,
  }) {
    _active = false;
    write({
      't': 'finish',
      'started_at': _iso(startedAt),
      'ended_at': _iso(endedAt),
      'd': distanceMeters,
      'duration_sec': duration.inSeconds,
    });
  }

  /// 멈춤·종료처럼 "지금 디스크에 있어야 하는" 순간에 부른다.
  Future<void> flush() async {
    await _ready;
    try {
      await _sink?.flush();
    } catch (_) {}
  }

  Future<void> _close() async {
    await _ready;
    final sink = _sink;
    _sink = null;
    try {
      await sink?.flush();
      await sink?.close();
    } catch (_) {}
  }

  /// 업로드가 끝난 일지를 지운다. 다음 러닝이 이미 시작됐으면 그 일지라 건드리지 않는다.
  ///
  /// 지금 열린 싱크만 닫고, 기다리는 동안 새 러닝이 열었을 수 있는 싱크와 파일은
  /// 손대지 않는다 — 지난 러닝의 늦은 업로드 응답이 새 러닝의 일지를 지우지 않게.
  Future<void> discardIfIdle() async {
    if (_active) return;
    final sink = _sink;
    _sink = null;
    await _ready;
    try {
      await sink?.flush();
      await sink?.close();
    } catch (_) {}
    if (_active) return;
    await _delete();
  }

  /// 일지를 지운다. 기록이 너무 짧거나 이미 서버에 있을 때.
  Future<void> discard() async {
    _active = false;
    await _close();
    await _delete();
  }

  Future<void> _delete() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// 남아 있는 일지를 기록으로 읽는다. 없으면 null.
  ///
  /// 종료까지 됐으면 종료 줄의 값을 쓰고, 달리던 중 죽었으면 마지막으로 기록된
  /// 시각까지를 러닝으로 친다. 첫 위치도 못 잡은 일지는 기록이 아니므로 지운다.
  Future<RunRecord?> read() async {
    final File file;
    try {
      file = await _file();
      if (!await file.exists()) return null;
    } catch (_) {
      return null;
    }

    final List<String> lines;
    try {
      lines = await file.readAsLines();
    } catch (_) {
      await _delete(); // 못 읽는 파일은 남겨 둬도 영원히 못 읽는다.
      return null;
    }
    String? courseId;
    String? courseName;
    DateTime? startedAt;
    DateTime? endedAt;
    Duration? duration;
    final points = <GeoPoint>[];
    var distance = 0.0;
    var pausedTotal = Duration.zero;
    DateTime? pausedAt;
    DateTime? lastAt;

    for (final line in lines) {
      final Map<String, dynamic> e;
      try {
        e = jsonDecode(line) as Map<String, dynamic>;
      } catch (_) {
        continue; // 잘린 마지막 줄
      }
      final at = e['at'] == null ? null : DateTime.tryParse(e['at'] as String);
      switch (e['t']) {
        case 'start':
          courseId = e['course_id'] as String?;
          courseName = e['course_name'] as String?;
        case 'started':
          startedAt = at;
        case 'p':
          try {
            points.add(GeoPoint.fromJson(e));
            distance = (e['d'] as num?)?.toDouble() ?? distance;
            lastAt = points.last.recordedAt ?? lastAt;
          } catch (_) {}
        case 'pause':
          if (at != null) pausedAt ??= at;
        case 'resume':
          if (at != null && pausedAt != null) {
            pausedTotal += at.difference(pausedAt);
            pausedAt = null;
          }
        case 'finish':
          startedAt = DateTime.tryParse(e['started_at'] as String? ?? '');
          endedAt = DateTime.tryParse(e['ended_at'] as String? ?? '');
          distance = (e['d'] as num?)?.toDouble() ?? distance;
          final sec = e['duration_sec'] as int?;
          if (sec != null) duration = Duration(seconds: sec);
      }
      if (at != null) lastAt = at;
    }

    if (startedAt == null || points.isEmpty) {
      await _delete();
      return null;
    }
    // 멈춘 채 죽었으면 멈춘 시각까지, 달리다 죽었으면 마지막 점까지.
    final to = endedAt ?? pausedAt ?? lastAt ?? startedAt;
    final ran = duration ?? to.difference(startedAt) - pausedTotal;
    return RunRecord(
      courseId: courseId,
      courseName: courseName,
      startedAt: startedAt,
      endedAt: to,
      distanceMeters: distance,
      duration: ran.isNegative ? Duration.zero : ran,
      path: points,
    );
  }

  static String _now() => _iso(DateTime.now());
  static String _iso(DateTime at) => at.toUtc().toIso8601String();
}
