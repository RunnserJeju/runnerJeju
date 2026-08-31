import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

/// 기기가 물리적으로 정지해 있는지를 가속도계로 판정한다.
///
/// GPS 좌표는 서 있어도 지터로 계속 흔들리지만, 가속도계는 서 있으면 확실히
/// 조용해진다. [RunTracker]가 이 신호로 정지 중의 GPS 지터를 기록에서 거른다.
///
/// 판정은 비대칭이다 — 정지는 [_stillDelay]만큼 조용해야 인정하고, 움직임은
/// 유의미한 가속도 한 번에 즉시 인정한다. 달리는 중에 잠깐 조용한 샘플이 껴도
/// 기록이 끊기지 않고, 다시 뛰면 첫 걸음부터 기록되게 하기 위해서다.
class MotionService {
  StreamSubscription<UserAccelerometerEvent>? _subscription;

  DateTime _lastMovementAt = DateTime.now();

  /// 이 크기(m/s², 중력 제거됨)를 넘는 가속도를 움직임으로 본다. 서 있는 폰의
  /// 센서 노이즈는 0.05 안팎, 달리기는 수 m/s²라 여유가 크다. 서서 폰을
  /// 조작하는 정도도 대부분 이 값을 넘는데, 그때는 게이트가 열리고 기존
  /// speed 게이트가 2차 방어선이 된다.
  static const double _movementThreshold = 0.4;

  /// 이 시간 동안 유의미한 가속도가 없어야 정지로 판정한다.
  static const Duration _stillDelay = Duration(seconds: 2);

  /// 기기가 [_stillDelay] 이상 조용한지. 구독 전이거나 센서를 못 쓰면 false —
  /// 게이트가 없던 동작으로 돌아갈 뿐, 기록을 막지는 않는다.
  bool get isStill =>
      _subscription != null &&
      DateTime.now().difference(_lastMovementAt) > _stillDelay;

  void start() {
    if (_subscription != null) return;
    // 시작 직후를 "움직임"으로 초기화한다 — 구독하자마자 정지로 판정하는 것보다
    // _stillDelay만큼 기다렸다 들어가는 쪽이 안전하다.
    _lastMovementAt = DateTime.now();
    _subscription =
        userAccelerometerEventStream(
          samplingPeriod: SensorInterval.uiInterval,
        ).listen(
          (event) {
            final magnitude = math.sqrt(
              event.x * event.x + event.y * event.y + event.z * event.z,
            );
            if (magnitude > _movementThreshold) {
              _lastMovementAt = DateTime.now();
            }
          },
          // 센서가 없는 기기(에뮬레이터 등)에서는 스트림이 에러를 낸다.
          // 구독을 접어 isStill이 항상 false가 되게 한다.
          onError: (Object _) => stop(),
          cancelOnError: true,
        );
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }
}
