import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/geo_point.dart';
import '../models/run_record.dart';
import '../models/running_course.dart';
import '../utils/course_coverage.dart';
import '../utils/geo_utils.dart';
import 'current_location.dart';
import 'location_service.dart';
import 'motion_service.dart';

enum RunStatus { idle, running, paused, finished }

/// 러닝 1회의 진행 상태를 들고 있는 컨트롤러.
///
/// 위치 스트림을 구독해 경로/거리/시간을 누적하고, 화면은 여기만 바라본다.
/// 서버 전송은 [RunTracker]의 책임이 아니라 [buildRecord] 결과를 받아 처리한다.
class RunTracker extends ChangeNotifier {
  RunTracker(this._locationService, this._motionService, this._currentLocation);

  final LocationService _locationService;
  final MotionService _motionService;

  /// 앱 전역의 최신 현위치. 실제 GPS 러닝은 위치 스트림을 여기서 가져갔다
  /// 돌려주고, 받은 점을 흘려 넣는다([CurrentLocation] 참고). 시뮬레이션은
  /// geolocator를 안 쓰므로 건드리지 않는다.
  final CurrentLocation _currentLocation;

  /// 이번 러닝이 실제 GPS인지(시뮬레이션이 아닌지). 모션 게이트와 전역 현위치
  /// 교대는 실제 GPS일 때만 한다 — 시뮬레이션은 폰을 가만히 둔 채 돌리므로
  /// 모션 게이트를 켜면 거리가 영원히 안 쌓이고, geolocator도 안 쓴다.
  bool _isRealGps = false;

  StreamSubscription<GeoPoint>? _positionSubscription;
  Timer? _ticker;

  RunStatus _status = RunStatus.idle;
  final List<GeoPoint> _path = [];
  double _distanceMeters = 0;
  DateTime? _startedAt;
  DateTime? _endedAt;

  /// 지금까지 멈춰 있던 시간의 합. [elapsed]가 시작 시각에서 이만큼을 뺀다.
  Duration _pausedTotal = Duration.zero;

  /// 지금 멈춰 있다면 그 멈춤이 시작된 시각. 달리는 중이면 null.
  DateTime? _pausedAt;
  RunningCourse? _targetCourse;

  /// [_targetCourse]의 경로를 실측한 길이(m). 진행률 분모라 매 틱 다시 재지 않고
  /// 코스를 잡을 때 한 번만 계산한다.
  double _courseLengthMeters = 0;
  GeoPoint? _lastPosition;
  GeoPoint? _commitAnchor;
  CourseCoverageTracker? _coverage;

  /// 이번 러닝이 쓰는 위치원. 시뮬레이션이면 그쪽이 들어온다.
  ///
  /// [start]가 받은 것을 들고 있는 이유는 재개 때문이다. 위치가 끊겨서 멈춘
  /// 경우에는 구독이 이미 죽어 있어서, 다시 달리려면 같은 위치원에 다시 붙어야 한다.
  LocationService? _activeLocation;

  /// 위치 수집이 끊긴 이유. 끊기지 않았으면 null.
  LocationInterruption? _interruption;

  /// 경로·거리·커버리지에 점을 반영하는 최소 이동 거리(m).
  ///
  /// 위치 자체는 1m마다 들어온다([LocationService]) — 현위치 마커를 부드럽게
  /// 움직이려면 그만큼 촘촘해야 한다. 하지만 그 해상도를 그대로 누적하면
  /// 제자리에 서 있어도 GPS 지터(보통 2~5m)가 거리로 쌓인다. 화면 갱신은
  /// 촘촘하게, 기록은 이 게이트를 지난 점만.
  static const double _commitMeters = 5;

  // ── 위치 샘플 걸러내기 ──────────────────────────────────────────────
  //
  // 아래 넷은 전부 "페이스가 틀리는" 원인을 하나씩 막는다. 걸러낸 점은 마커에도
  // 쓰지 않는다 — 라이브 지도의 선은 [currentPosition]으로 그려지므로, 기록만
  // 거르고 마커는 그대로 두면 지도의 선과 저장되는 경로가 서로 달라진다.

  /// 이보다 오차가 큰 점은 버린다. 도심에서 흔한 15~25m는 통과시키되, 첫
  /// 고정 직후나 건물 사이에서 나오는 50m+ 튐은 걸러낸다. 그런 점 하나가
  /// 수십 m를 순식간에 거리로 만든다.
  static const double _maxAccuracyMeters = 30;

  /// 이보다 오래된 점은 버린다. Android 위치 제공자는 구독 직후 마지막으로
  /// 알려진(몇 분 전일 수 있는) 위치를 먼저 주는데, 그걸 출발점으로 삼으면
  /// 실제 현위치까지의 거리가 첫 구간으로 잡힌다.
  static const Duration _maxSampleAge = Duration(seconds: 10);

  /// 직전 확정점에서 이 속도를 넘는 이동은 GPS 튐으로 본다(m/s). 8m/s는
  /// 2'05"/km — 러닝 코스에서 나올 수 없는 값이다.
  static const double _maxPlausibleSpeed = 8;

  /// [_maxPlausibleSpeed]로 연속 이만큼 거르면 튐이 아니라 기준점이 낡은 것
  /// (터널·지하도를 지나 진짜 이동했다)으로 보고 기준점을 갈아 끼운다. 그때의
  /// 이동은 확실치 않으므로 거리에 넣지 않는다.
  static const int _maxJumpRejections = 3;

  /// GPS가 이 속도 미만이라 하면 서 있는 것으로 본다(m/s). 걷기가 1.2m/s
  /// 안팎이라 여유가 있다. 서 있는 동안의 지터는 [_commitMeters]를 넘어도
  /// 거리에 넣지 않는다.
  static const double _stationarySpeed = 0.5;

  /// 최근 페이스의 창(m). 러닝 앱들이 흔히 쓰는 "최근 1km".
  static const double _recentPaceWindowMeters = 1000;

  /// 이 거리 전에는 페이스를 내지 않는다(평균·최근 둘 다). 확정 게이트가 5m라
  /// 30m면 확정점 여섯 개 남짓인데, 그 전에는 점 하나의 오차가 그대로 숫자가 된다.
  static const double _minPaceMeters = 30;

  /// [_maxPlausibleSpeed]에 연속으로 걸린 횟수.
  int _jumpRejections = 0;

  /// 확정점마다의 (누적 거리, 경과 시간). 최근 페이스가 여기서 창을 자른다.
  final List<({double meters, Duration elapsed})> _paceSamples = [];

  RunStatus get status => _status;

  /// 위치가 끊겨서 기록이 멈춰 있다면 그 사유. 화면이 이걸 보고 알린다.
  LocationInterruption? get interruption => _interruption;

  /// 읽기 전용 스냅샷. 점이 늘 때만 새로 만든다 — 화면이 매 빌드마다 읽는데
  /// 그때마다 수천 점을 복사하면 낭비다.
  List<GeoPoint> get path => _pathSnapshot ??= List.unmodifiable(_path);
  List<GeoPoint>? _pathSnapshot;
  double get distanceMeters => _distanceMeters;

  /// 실제로 달린 시간(멈춰 있던 시간 제외).
  ///
  /// 시작 시각은 시작 버튼이 아니라 **첫 유효 위치**다([_onPosition]). 버튼
  /// 시각으로 재면 GPS가 잡히기까지의 5~30초가 거리 0인 채로 흘러, 첫 5m가
  /// 확정되는 순간 페이스가 60분/km 같은 값으로 시작한다.
  ///
  /// 1초 타이머로 세지 않고 시각을 뺀다. 타이머는 앱이 백그라운드로 내려가면
  /// 느려지거나 아예 멈추는데, 그동안에도 위치는 계속 들어오고 거리는 쌓인다.
  /// 그래서 예전에는 화면을 끄고 달린 만큼 시간이 덜 세어졌고, 그 값이 그대로
  /// duration_sec와 페이스로 나가서 "3분 페이스" 같은 기록이 남았다.
  Duration get elapsed {
    final startedAt = _startedAt;
    if (startedAt == null) return Duration.zero;

    // 멈춰 있는 동안에는 시간이 흐르지 않아야 하므로 멈춘 시각에서 끊는다.
    // 끝난 뒤에는 종료 시각에서 끊는다(finish가 멈춤을 먼저 정산한다).
    final until = _pausedAt ?? _endedAt ?? DateTime.now();
    final ran = until.difference(startedAt) - _pausedTotal;

    // 기기 시계가 뒤로 돌아가는 경우까지 음수로 내보내지는 않는다.
    return ran.isNegative ? Duration.zero : ran;
  }

  DateTime? get startedAt => _startedAt;

  /// 가장 최근에 들어온 위치. [path]와 달리 게이트를 거치지 않은 원본이라
  /// 1m마다 갱신된다 — 지도의 현위치 마커가 이걸 본다.
  GeoPoint? get currentPosition => _lastPosition;

  /// 따라 달리는 중인 코스. 자유 러닝이면 null.
  RunningCourse? get targetCourse => _targetCourse;

  bool get isActive =>
      _status == RunStatus.running || _status == RunStatus.paused;

  /// 달리는 중인데 아직 유효한 위치가 한 점도 안 들어왔는지. 그동안 시간은
  /// 흐르지 않는다([elapsed]). 화면이 이걸 보고 "GPS 잡는 중"을 띄운다.
  bool get isAwaitingFix => _status == RunStatus.running && _startedAt == null;

  /// 러닝 전체의 평균 페이스(km당 초). [_minPaceMeters] 전에는 null.
  ///
  /// 최근 페이스와 같은 문턱을 쓴다. 화면의 주 지표는 최근 페이스이고 평균은
  /// 그 아래 보조로 붙는데, 문턱이 다르면 주 지표는 "--"인데 보조만 먼저 숫자가
  /// 뜨고, 그 숫자가 바로 문턱으로 가리려던 초반 오차다.
  double? get paceSecondsPerKm {
    if (_distanceMeters < _minPaceMeters) return null;
    return elapsed.inMilliseconds / 1000 / (_distanceMeters / 1000);
  }

  /// 최근 1km의 페이스(km당 초). 1km를 아직 못 뛰었으면 지금까지 전체가 창이라
  /// [paceSecondsPerKm]와 같은 값이다 — 1km를 넘는 순간부터 둘이 갈라진다.
  /// [_minPaceMeters] 전에는 null.
  ///
  /// 창의 시작점은 확정점 중에서 고르므로 정확히 1000m가 아니라 그 언저리의
  /// 확정점부터다. 끝은 지금 이 순간이라, 서 있으면 페이스가 천천히 느려진다.
  double? get recentPaceSecondsPerKm {
    if (_distanceMeters < _minPaceMeters || _paceSamples.isEmpty) return null;

    final nowElapsed = elapsed;
    final windowStart = _distanceMeters - _recentPaceWindowMeters;
    var from = _paceSamples.first;
    for (final sample in _paceSamples) {
      if (sample.meters >= windowStart) {
        from = sample;
        break;
      }
    }

    final meters = _distanceMeters - from.meters;
    if (meters <= 0) return null;
    return (nowElapsed - from.elapsed).inMilliseconds / 1000 / (meters / 1000);
  }

  /// 코스 커버리지 0.0~1.0(코스 점 중 실제로 지나간 비율). 자유 러닝이면 null.
  ///
  /// 서버 검증의 match_rate와 같은 개념·같은 로직이다(CourseCoverageTracker 참고).
  double? get courseCoverage => _targetCourse == null ? null : _coverage?.ratio;

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
    // _startedAt은 여기서 잡지 않는다. 첫 유효 위치가 들어올 때 잡는다(elapsed 참고).
    _status = RunStatus.running;
    _activeLocation = location;

    _isRealGps = source == null;
    if (_isRealGps) {
      _motionService.start();
      // 평상시 스트림을 먼저 닫아야 아래 구독이 러닝 설정으로 열린다.
      _currentLocation.yieldToRun();
    }

    _subscribeToPositions(location);
    _startTicker();
    notifyListeners();

    return availability;
  }

  void _subscribeToPositions(LocationService location) {
    _positionSubscription?.cancel(); //재구독 방어
    _positionSubscription = location.trackPosition().listen(
      (point) {
        // 일시정지 중에도(아래 _onPosition은 버린다) 최신 위치는 갱신한다.
        if (_isRealGps) _currentLocation.report(point);
        _onPosition(point);
      },
      // 에러를 받지 않으면 스트림이 끊긴 채로 앱이 진행되기 때문에 사용자가 에러가 난 줄도 모른다.
      onError: (Object error) =>
          _handlePositionLost(location.interruptionFrom(error)),
      onDone: () => _handlePositionLost(LocationInterruption.lost),
    );
  }

  /// 위치가 끊겼다. 기록을 멈추고 사유를 남긴다.
  ///
  /// 러닝을 끝내지는 않는다 — 여기까지 달린 것은 그대로 살아 있고, 위치 서비스를
  /// 다시 켜면 이어 달릴 수 있어야 한다. 화면에 나오는 상태는 사용자가 직접
  /// 일시정지를 누른 것과 같아서, 이어서·종료 버튼이 그대로 쓰인다.
  void _handlePositionLost(LocationInterruption reason) {
    // 일시정지 중에도 스트림은 살아 있어 끊길 수 있다. 상태와 무관하게 죽은
    // 구독을 버리고 사유를 남겨야 resume()이 다시 붙고, 화면이 사유를 알린다.
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _interruption = reason;

    if (_status == RunStatus.running) {
      _status = RunStatus.paused;
      _beginPause();
      _ticker?.cancel();
    }
    notifyListeners();
  }

  void pause() {
    if (_status != RunStatus.running) return;

    _status = RunStatus.paused;
    _beginPause();
    _ticker?.cancel();
    notifyListeners();
  }

  void _beginPause() => _pausedAt ??= DateTime.now();

  /// 멈춰 있던 시간을 합계에 넣고 멈춤을 닫는다.
  void _endPause() {
    final pausedAt = _pausedAt;
    if (pausedAt == null) return;

    _pausedTotal += DateTime.now().difference(pausedAt);
    _pausedAt = null;
  }

  void resume() {
    if (_status != RunStatus.paused) return;

    _status = RunStatus.running;
    _endPause();
    // 일시정지 중 이동은 거리에 반영하지 않는다. 기준점만 버리고 _lastPosition은
    // 남긴다 — 그걸 비우면 지도에서 현위치 마커가 잠깐 사라진다.
    _commitAnchor = null;
    _interruption = null;

    // 끊겨서 멈춘 경우라면 구독이 없다. 같은 위치원에 다시 붙는다. 원인이
    // 그대로면(위치 서비스가 여전히 꺼져 있으면) 곧바로 다시 멈추고 사유가
    // 다시 뜬다 — 그게 "아직 안 됐다"를 알리는 가장 솔직한 방법이다.
    final location = _activeLocation;
    if (_positionSubscription == null && location != null) {
      _subscribeToPositions(location);
    }

    _startTicker();
    notifyListeners();
  }

  /// 러닝 종료. 이후 [buildRecord]로 서버에 올릴 기록을 만든다.
  void finish() {
    if (!isActive) return;

    // 멈춘 채로 끝내는 경우가 보통이다(종료 버튼이 일시정지 상태에서만 나온다).
    // 그 마지막 멈춤까지 정산해야 elapsed가 종료 시각 기준으로 맞는다.
    _endPause();

    _status = RunStatus.finished;
    _interruption = null;
    _endedAt = DateTime.now();
    // 위치를 한 점도 못 받고 끝냈으면 시작 시각이 없다. 기록은 남겨야 하므로
    // 종료 시각으로 채운다 — 시간 0, 거리 0인 기록이 된다.
    _startedAt ??= _endedAt;
    _ticker?.cancel();
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _motionService.stop();
    // 러닝 구독이 끊긴 뒤에 돌려준다. 순서가 바뀌면 평상시 스트림이 러닝
    // 설정을 물려받는다.
    if (_isRealGps) _currentLocation.reclaimFromRun();
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
      duration: elapsed,
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
    if (!_isUsable(point)) return;

    final anchor = _commitAnchor;
    if (anchor == null) {
      // 러닝 시작 후, 또는 일시정지 해제 후 첫 point인 경우
      // 재개한 경우라면 직전 점과 이 점 사이가 "일시정지 동안 이동한 구간"이다.
      // 그 구간은 거리에 넣지 않는다.
      if (_startedAt == null) {
        _startedAt = point.recordedAt ?? DateTime.now();
        // 위치가 잡히기 전에 멈췄다 풀었으면 그 멈춤은 시작 전의 일이다.
        _pausedTotal = Duration.zero;
      }
      _lastPosition = point;
      _jumpRejections = 0;
      _commit(_path.isEmpty ? point : point.asSegmentStart());
      notifyListeners();
      return;
    }

    // 기기가 물리적으로 정지해 있으면 이 점은 GPS 지터다. 마커도 기록도
    // 갱신하지 않는다 — 서 있는 동안 마커가 돌아다니고 경로가 자라는 것을 막는다.
    // 첫 유효 위치(위의 anchor == null)는 게이트보다 먼저 처리한다: 출발선에
    // 가만히 서서 GPS를 기다리는 동안에도 마커와 시작 시각은 잡혀야 한다.
    if (_isRealGps && _motionService.isStill) return;

    final moved = GeoUtils.distanceBetween(anchor, point);

    if (_isImplausibleJump(anchor, point, moved)) {
      if (++_jumpRejections < _maxJumpRejections) return;
      // 계속 같은 곳을 가리킨다 — 튐이 아니라 우리가 뒤처진 것이다. 그 사이는
      // 잰 것이 아니므로 끊긴 구간으로 표시하고 여기서 다시 시작한다.
      _jumpRejections = 0;
      _lastPosition = point;
      _commit(point.asSegmentStart());
      notifyListeners();
      return;
    }
    _jumpRejections = 0;

    // 마커용 최신 위치는 걸러낸 점만 빼고 갱신한다.
    _lastPosition = point;

    if (moved >= _commitMeters && !_isStationary(point)) {
      _distanceMeters += moved;
      _commit(point);
    }

    notifyListeners();
  }

  /// 점을 경로·커버리지·페이스 표본에 확정한다. 거리는 부르는 쪽이 먼저 더한다.
  void _commit(GeoPoint point) {
    _commitAnchor = point;
    _path.add(point);
    _pathSnapshot = null;
    _coverage?.add(point);
    _paceSamples.add((meters: _distanceMeters, elapsed: elapsed));

    // 창 밖으로 완전히 나간 표본은 버린다. 창 경계 직전 표본 하나는 남겨야
    // 창의 시작점으로 쓸 수 있다.
    final windowStart = _distanceMeters - _recentPaceWindowMeters;
    while (_paceSamples.length > 1 && _paceSamples[1].meters <= windowStart) {
      _paceSamples.removeAt(0);
    }
  }

  /// 오차가 크거나 오래된 점은 쓰지 않는다. 정보가 없는 점(시뮬레이션)은 통과.
  bool _isUsable(GeoPoint point) {
    final accuracy = point.accuracy;
    if (accuracy != null && accuracy > _maxAccuracyMeters) return false;

    final recordedAt = point.recordedAt;
    if (recordedAt != null &&
        DateTime.now().difference(recordedAt) > _maxSampleAge) {
      return false;
    }
    return true;
  }

  /// 직전 확정점에서 여기까지가 사람이 뛸 수 없는 속도인지. 시각이 없으면
  /// 판단할 수 없으므로 통과시킨다.
  bool _isImplausibleJump(GeoPoint anchor, GeoPoint point, double moved) {
    final from = anchor.recordedAt;
    final to = point.recordedAt;
    if (from == null || to == null) return false;

    final seconds = to.difference(from).inMilliseconds / 1000;
    if (seconds <= 0) return false;
    return moved / seconds > _maxPlausibleSpeed;
  }

  /// GPS 자체가 "서 있다"고 하는지. 속도를 못 잰 점(null)은 모르는 것으로 둔다.
  bool _isStationary(GeoPoint point) {
    final speed = point.speed;
    return speed != null && speed < _stationarySpeed;
  }

  /// 화면 갱신용 시계. 경과 시간을 여기서 세지는 않는다([elapsed] 참고) —
  /// "1초마다 다시 그려라"는 신호일 뿐이라, 타이머가 밀려도 값은 틀리지 않는다.
  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => notifyListeners(),
    );
  }

  void _reset() {
    _ticker?.cancel();
    _ticker = null;
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _motionService.stop();
    _isRealGps = false;

    _status = RunStatus.idle;
    _path.clear();
    _pathSnapshot = null;
    _distanceMeters = 0;
    _startedAt = null;
    _endedAt = null;
    _pausedTotal = Duration.zero;
    _pausedAt = null;
    _targetCourse = null;
    _courseLengthMeters = 0;
    _lastPosition = null;
    _commitAnchor = null;
    _coverage = null;
    _activeLocation = null;
    _interruption = null;
    _jumpRejections = 0;
    _paceSamples.clear();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _positionSubscription?.cancel();
    _motionService.stop();
    super.dispose();
  }
}
