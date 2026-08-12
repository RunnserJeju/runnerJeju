import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/geo_point.dart';
import '../models/run_record.dart';
import '../models/running_course.dart';
import '../utils/course_coverage.dart';
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

  /// [_targetCourse]의 경로를 실측한 길이(m). 진행률 분모라 매 틱 다시 재지 않고
  /// 코스를 잡을 때 한 번만 계산한다.
  double _courseLengthMeters = 0;
  GeoPoint? _lastPosition;
  GeoPoint? _commitAnchor;
  CourseCoverageTracker? _coverage;

  /// 경로·거리·커버리지에 점을 반영하는 최소 이동 거리(m).
  ///
  /// 위치 자체는 1m마다 들어온다([LocationService]) — 현위치 마커를 부드럽게
  /// 움직이려면 그만큼 촘촘해야 한다. 하지만 그 해상도를 그대로 누적하면
  /// 제자리에 서 있어도 GPS 지터(보통 2~5m)가 거리로 쌓인다. 화면 갱신은
  /// 촘촘하게, 기록은 이 게이트를 지난 점만.
  static const double _commitMeters = 5;

  /// 인정에 필요한 커버리지와 주행 거리 비율. 서버 판정과 **같은 값이어야 한다**
  /// (verification.DEFAULT_MATCH_THRESHOLD / DEFAULT_MIN_DISTANCE_RATIO).
  /// [hasReachedCourseGoal]이 서버가 matched를 줄 상태를 정확히 미러링해야,
  /// 완주 버튼을 눌렀는데 서버가 거절하는 배신이 구조적으로 불가능해진다.
  static const double _matchThreshold = 0.85;
  static const double _minDistanceRatio = 0.85;

  RunStatus get status => _status;
  List<GeoPoint> get path => List.unmodifiable(_path);
  double get distanceMeters => _distanceMeters;
  Duration get elapsed => _elapsed;
  DateTime? get startedAt => _startedAt;

  /// 가장 최근에 들어온 위치. [path]와 달리 게이트를 거치지 않은 원본이라
  /// 1m마다 갱신된다 — 지도의 현위치 마커가 이걸 본다.
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

  /// 코스 커버리지 0.0~1.0(코스 점 중 실제로 지나간 비율). 자유 러닝이면 null.
  ///
  /// 서버 검증의 match_rate와 같은 개념·같은 로직이다(CourseCoverageTracker 참고).
  double? get courseCoverage =>
      _targetCourse == null ? null : _coverage?.ratio;

  /// 누적 주행 거리 ÷ 코스 거리 (1.0 초과 가능). 자유 러닝이면 null.
  ///
  /// 분모는 `course.distanceKm`이 아니라 **코스 경로를 실측한 길이**다. 서버
  /// 검증도 `courses` 컬럼이 아니라 `path`를 재서 같은 비율을 구하므로
  /// (verification.path_length_meters), 같은 기준을 써야 앱 진행률과 서버 판정이
  /// 어긋나지 않는다. distanceKm은 시트에 적힌 왕복 안내값(정수 km)이라 이 계산에
  /// 쓰면 최대 수백 m가 어긋난다.
  double? get _distanceRatio {
    if (_targetCourse == null || _courseLengthMeters <= 0) return null;
    return _distanceMeters / _courseLengthMeters;
  }

  /// 화면에 보여주는 코스 진행도 0.0~1.0. 자유 러닝이면 null.
  ///
  /// 서버가 보는 두 숫자(커버리지, 거리 비율) 중 **낮은 쪽**이다. 둘 다 85%를
  /// 넘어야 인정되므로 낮은 쪽이 곧 "인정까지의 진행도"다.
  ///
  /// 커버리지만 보여주면 왕복 코스에서 반환점(거리 절반)에 이미 100%가 떠서
  /// 혼란스럽다 — 복로가 왕로의 tolerance 안이라 편도만 뛰어도 코스 점이 전부
  /// 커버되기 때문. min을 취하면 반환점에 50%가 표시되고, 코스를 벗어나면
  /// 커버리지가 멈춰 바도 멈춘다.
  double? get courseProgress {
    final coverage = courseCoverage;
    final distanceRatio = _distanceRatio;
    if (coverage == null || distanceRatio == null) return null;
    return math.min(coverage, distanceRatio).clamp(0.0, 1.0);
  }

  /// 서버가 matched를 줄 조건(커버리지 85% + 거리 85%)을 채웠는지.
  ///
  /// 이 값이 true가 되면 화면에 완주(종료) 버튼이 나타난다. 자동으로 종료하지는
  /// 않는다 — 더 달리고 싶은 사람을 끊어버리고, 조건 판정의 잔버그가 곧바로
  /// "종료를 못 하는 버그"가 되기 때문이다. 종료는 항상 사용자의 버튼으로만.
  bool get hasReachedCourseGoal {
    final coverage = courseCoverage;
    final distanceRatio = _distanceRatio;
    if (coverage == null || distanceRatio == null) return false;

    return coverage >= _matchThreshold && distanceRatio >= _minDistanceRatio;
  }

  /// 러닝 시작. [course]를 주면 코스를 따라 달리는 러닝이 된다.
  /// 권한이 없으면 사유를 반환하고 시작하지 않는다.
  ///
  /// [source]를 주면 이번 러닝만 그 위치원을 쓴다. 디버그 빌드의 시뮬레이션
  /// 러닝이 유일한 사용처이고, 주지 않으면 평소대로 실제 GPS를 쓴다.
  Future<LocationAvailability> start({
    RunningCourse? course,
    LocationService? source,
  }) async {
    final location = source ?? _locationService;

    final availability = await location.ensurePermission();
    if (!availability.isReady) return availability;

    _reset();
    _targetCourse = course;
    _courseLengthMeters = course == null ? 0 : GeoUtils.pathLength(course.path);
    _coverage = course == null || course.path.isEmpty
        ? null
        : CourseCoverageTracker(course.path);
    _startedAt = DateTime.now();
    _status = RunStatus.running;

    _positionSubscription = location.trackPosition().listen(_onPosition);
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
    // 일시정지 중 이동은 거리에 반영하지 않는다. 기준점만 버리고 _lastPosition은
    // 남긴다 — 그걸 비우면 지도에서 현위치 마커가 잠깐 사라진다.
    _commitAnchor = null;
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

    // 마커용 최신 위치는 무조건 갱신한다.
    _lastPosition = point;

    final anchor = _commitAnchor;
    if (anchor == null) {
      // 러닝 시작 직후, 또는 일시정지에서 막 돌아온 첫 점. 기준점만 잡는다.
      _commitAnchor = point;
      _path.add(point);
      _coverage?.add(point);
    } else {
      final moved = GeoUtils.distanceBetween(anchor, point);
      if (moved >= _commitMeters) {
        _distanceMeters += moved;
        _commitAnchor = point;
        _path.add(point);
        _coverage?.add(point);
      }
    }

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
    _courseLengthMeters = 0;
    _lastPosition = null;
    _commitAnchor = null;
    _coverage = null;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _positionSubscription?.cancel();
    super.dispose();
  }
}
