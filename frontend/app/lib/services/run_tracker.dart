import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/geo_point.dart';
import '../models/run_record.dart';
import '../models/running_course.dart';
import '../utils/geo_utils.dart';
import 'location_service.dart';

enum RunStatus { idle, running, paused, finished }

/// 러닝 1회의 진행 상태를 들고 있는 컨트롤러.
///
/// 위치 스트림을 구독해 경로/거리/시간을 누적하고, 화면은 여기만 바라본다.
/// 서버 전송은 [RunTracker]의 책임이 아니라 [buildRecord] 결과를 받아 처리한다.
class RunTracker extends ChangeNotifier {
  RunTracker(this._locationService);

  final LocationService _locationService;

  StreamSubscription<GeoPoint>? _positionSubscription;
  Timer? _ticker;

  RunStatus _status = RunStatus.idle;
  final List<GeoPoint> _path = [];
  double _distanceMeters = 0;
  Duration _elapsed = Duration.zero;
  DateTime? _startedAt;
  DateTime? _endedAt;
  RunningCourse? _targetCourse;
  GeoPoint? _lastPosition;

  /// 완주로 인정하는 코스 진행률(서버 판정 전 UI용 기준).
  static const double _completionRatio = 0.9;

  /// 코스 종료 지점으로 인정하는 반경(m).
  static const double _finishRadiusMeters = 60;

  RunStatus get status => _status;
  List<GeoPoint> get path => List.unmodifiable(_path);
  double get distanceMeters => _distanceMeters;
  Duration get elapsed => _elapsed;
  DateTime? get startedAt => _startedAt;
  GeoPoint? get currentPosition => _lastPosition;

  /// 따라 달리는 중인 코스. 자유 러닝이면 null.
  RunningCourse? get targetCourse => _targetCourse;

  bool get isActive =>
      _status == RunStatus.running || _status == RunStatus.paused;

  /// km당 초. 아직 움직이지 않았으면 null.
  double? get paceSecondsPerKm {
    if (_distanceMeters <= 0) return null;
    return _elapsed.inSeconds / (_distanceMeters / 1000);
  }

  /// 코스 진행률 0.0~1.0. 자유 러닝이면 null.
  double? get courseProgress {
    final course = _targetCourse;
    if (course == null || course.distanceMeters <= 0) return null;
    return (_distanceMeters / course.distanceMeters).clamp(0.0, 1.0);
  }

  /// 코스 완주 조건 충족 여부(거리 + 종료 지점 도달). 최종 판정은 서버가 한다.
  bool get hasReachedCourseGoal {
    final course = _targetCourse;
    final endPoint = course?.endPoint;
    final position = _lastPosition;
    if (course == null || endPoint == null || position == null) return false;

    final coveredEnough =
        _distanceMeters >= course.distanceMeters * _completionRatio;
    final atFinish =
        GeoUtils.distanceBetween(position, endPoint) <= _finishRadiusMeters;

    return coveredEnough && atFinish;
  }

  /// 러닝 시작. [course]를 주면 코스를 따라 달리는 러닝이 된다.
  /// 권한이 없으면 사유를 반환하고 시작하지 않는다.
  Future<LocationAvailability> start({RunningCourse? course}) async {
    final availability = await _locationService.ensurePermission();
    if (!availability.isReady) return availability;

    _reset();
    _targetCourse = course;
    _startedAt = DateTime.now();
    _status = RunStatus.running;

    _positionSubscription = _locationService.trackPosition().listen(
      _onPosition,
    );
    _startTicker();
    notifyListeners();

    return availability;
  }

  void pause() {
    if (_status != RunStatus.running) return;

    _status = RunStatus.paused;
    _ticker?.cancel();
    notifyListeners();
  }

  void resume() {
    if (_status != RunStatus.paused) return;

    _status = RunStatus.running;
    // 일시정지 중 이동은 거리에 반영하지 않는다.
    _lastPosition = null;
    _startTicker();
    notifyListeners();
  }

  /// 러닝 종료. 이후 [buildRecord]로 서버에 올릴 기록을 만든다.
  void finish() {
    if (!isActive) return;

    _status = RunStatus.finished;
    _endedAt = DateTime.now();
    _ticker?.cancel();
    _positionSubscription?.cancel();
    _positionSubscription = null;
    notifyListeners();
  }

  /// 종료된 러닝을 서버 전송용 기록으로 변환한다. 종료 전이면 null.
  RunRecord? buildRecord() {
    final startedAt = _startedAt;
    final endedAt = _endedAt;
    if (_status != RunStatus.finished || startedAt == null || endedAt == null) {
      return null;
    }

    return RunRecord(
      courseId: _targetCourse?.id,
      courseName: _targetCourse?.name,
      startedAt: startedAt,
      endedAt: endedAt,
      distanceMeters: _distanceMeters,
      duration: _elapsed,
      path: List.of(_path),
    );
  }

  /// 결과 화면을 벗어날 때 호출해 다음 러닝을 받을 수 있는 상태로 되돌린다.
  void reset() {
    _reset();
    notifyListeners();
  }

  void _onPosition(GeoPoint point) {
    if (_status != RunStatus.running) return;

    final previous = _lastPosition;
    if (previous != null) {
      _distanceMeters += GeoUtils.distanceBetween(previous, point);
    }

    _lastPosition = point;
    _path.add(point);
    notifyListeners();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsed += const Duration(seconds: 1);
      notifyListeners();
    });
  }

  void _reset() {
    _ticker?.cancel();
    _ticker = null;
    _positionSubscription?.cancel();
    _positionSubscription = null;

    _status = RunStatus.idle;
    _path.clear();
    _distanceMeters = 0;
    _elapsed = Duration.zero;
    _startedAt = null;
    _endedAt = null;
    _targetCourse = null;
    _lastPosition = null;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _positionSubscription?.cancel();
    super.dispose();
  }
}
