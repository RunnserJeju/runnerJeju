import 'dart:async';

import 'package:flutter/foundation.dart';

/// 러닝 화면·결과 화면이 떠 있는지. 러닝 탭은 그동안 자기 지도를 트리에서 뺀다.
///
/// 라우트를 밀어 올려도 아래 화면은 살아 있어서, 가만히 두면 카카오맵 엔진이 둘이
/// 된다 — 하나는 달리는 사람이 보고 있고, 하나는 아무도 못 보는 채로 메모리만 쓴다.
/// 러닝 중 메모리가 크면 OS가 백그라운드에 있는 앱을 먼저 종료하므로 줄일수록 좋다.
///
/// 화면이 스스로 들어오고 나가며 센다. 러닝 화면을 여는 곳이 여럿이라(러닝 탭,
/// 마이페이지 미완주 기록, 결과 화면의 이어 달리기) 여는 쪽이 아니라 열리는 쪽이
/// 알려야 빠지는 경로가 없다. 러닝 화면이 결과 화면으로 바뀔 때는 결과 화면이 먼저
/// 들어오고 러닝 화면이 나중에 나가서 0을 거치지 않는다 — 지도가 그사이 되살아나지 않는다.
class RunFlowPresence extends ChangeNotifier {
  int _screens = 0;

  bool get isOpen => _screens > 0;

  /// 화면의 initState에서.
  void enter() {
    _screens++;
    if (_screens == 1) _notifyLater();
  }

  /// 화면의 dispose에서.
  void leave() {
    if (_screens == 0) return;
    _screens--;
    if (_screens == 0) _notifyLater();
  }

  // initState·dispose는 빌드·정리 도중이라 여기서 바로 알리면 다른 화면의 setState가
  // "빌드 중 setState"로 터진다. 이번 프레임이 끝난 뒤에 알린다.
  void _notifyLater() => scheduleMicrotask(notifyListeners);
}
