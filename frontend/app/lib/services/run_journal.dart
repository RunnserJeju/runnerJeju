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

  /// 새 러닝. 이전 일지가 남아 있으면 버린다(이미 처리됐거나 복구를 거절한 것).
  void begin({String? courseId, String? courseName}) {
    _active = true;
    _ready = _open(truncate: true);
    write({
      't': 'start',
      'at': _now(),
      'course_id': ?courseId,
      'course_name': ?courseName,
    });
  }

  /// 복구한 러닝을 이어 쓴다. 죽어 있던 시간은 읽을 때 멈춤으로 친다.
  void reopen() {
    _active = true;
    _ready = _open(truncate: false);
    write({'t': 'recover', 'at': _now()});
  }

  Future<void> _open({required bool truncate}) async {
    await _close();
    try {
      final file = await _file();
      _sink = file.openWrite(
        mode: truncate ? FileMode.write : FileMode.append,
      );
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

  /// 일지를 지운다. 복구할 것이 없거나 기록이 너무 짧을 때.
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

  /// 남아 있는 일지를 읽는다. 없거나 시작 줄조차 없으면 null.
  Future<RunJournalSnapshot?> read() async {
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
    var seenStart = false;
    var finished = false;

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
          seenStart = true;
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
        case 'recover':
          // 죽어 있던 시간은 멈춤이다. 멈춘 채 죽었으면 그 멈춤이 이어진 것이고,
          // 달리다 죽었으면 마지막 점부터 멈춘 것으로 본다. 복구 직후는 멈춤 상태.
          if (at != null) {
            final from = pausedAt ?? lastAt;
            if (from != null) pausedTotal += at.difference(from);
            pausedAt = at;
          }
        case 'finish':
          finished = true;
          startedAt = DateTime.tryParse(e['started_at'] as String? ?? '');
          endedAt = DateTime.tryParse(e['ended_at'] as String? ?? '');
          distance = (e['d'] as num?)?.toDouble() ?? distance;
          final sec = e['duration_sec'] as int?;
          if (sec != null) duration = Duration(seconds: sec);
      }
      if (at != null) lastAt = at;
    }
    if (!seenStart) return null;

    return RunJournalSnapshot(
      courseId: courseId,
      courseName: courseName,
      startedAt: startedAt,
      endedAt: endedAt,
      duration: duration,
      points: points,
      distanceMeters: distance,
      pausedTotal: pausedTotal,
      pausedAt: pausedAt,
      lastAt: lastAt,
      finished: finished,
    );
  }

  static String _now() => _iso(DateTime.now());
  static String _iso(DateTime at) => at.toUtc().toIso8601String();
}

/// 일지를 읽어 만든 스냅샷. 러닝 중이었으면 [RunTracker.restore]에, 종료 뒤
/// 업로드 전에 죽었으면([finished]) [record]로 바로 제출한다.
class RunJournalSnapshot {
  const RunJournalSnapshot({
    required this.courseId,
    required this.courseName,
    required this.startedAt,
    required this.endedAt,
    required this.duration,
    required this.points,
    required this.distanceMeters,
    required this.pausedTotal,
    required this.pausedAt,
    required this.lastAt,
    required this.finished,
  });

  final String? courseId;
  final String? courseName;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final Duration? duration;
  final List<GeoPoint> points;
  final double distanceMeters;
  final Duration pausedTotal;

  /// 멈춘 채 죽었으면 그 시각. 달리다 죽었으면 null.
  final DateTime? pausedAt;

  /// 마지막으로 기록된 시각. 달리다 죽었으면 여기까지가 달린 시간이다.
  final DateTime? lastAt;
  final bool finished;

  /// 복구할 만한 러닝인지. 첫 위치도 못 잡고 죽은 건 복구할 것이 없다.
  bool get isResumable => !finished && startedAt != null && points.isNotEmpty;

  /// 복구 시점 기준 달린 시간(죽어 있던 시간 제외).
  Duration get elapsed {
    final from = startedAt;
    if (from == null) return Duration.zero;
    final until = pausedAt ?? lastAt ?? from;
    final ran = until.difference(from) - pausedTotal;
    return ran.isNegative ? Duration.zero : ran;
  }

  /// 달리던 중 죽은 러닝을 "여기까지"로 끝낸 기록. 마지막으로 기록된 시각이 종료 시각이다.
  RunRecord? get recordUntilNow {
    final from = startedAt;
    if (from == null || points.isEmpty) return null;
    return RunRecord(
      courseId: courseId,
      courseName: courseName,
      startedAt: from,
      endedAt: pausedAt ?? lastAt ?? from,
      distanceMeters: distanceMeters,
      duration: elapsed,
      path: points,
    );
  }

  /// 종료까지 됐던 러닝의 기록. [finished]가 아니면 null.
  RunRecord? get record {
    final from = startedAt;
    final to = endedAt;
    if (!finished || from == null || to == null) return null;
    return RunRecord(
      courseId: courseId,
      courseName: courseName,
      startedAt: from,
      endedAt: to,
      distanceMeters: distanceMeters,
      duration: duration ?? to.difference(from) - pausedTotal,
      path: points,
    );
  }
}
