import 'package:flutter/material.dart';

/// 짧은 안내(스낵바)를 겹치지 않게 하나씩만 띄운다.
///
/// [ScaffoldMessenger]는 요청을 **큐에 쌓아** 하나가 사라지면 다음 것을 보여준다.
/// 그래서 "준비 중이에요" 같은 버튼을 여러 번 누르면 같은 안내가 누른 횟수만큼
/// 줄지어 나오고, 그동안 화면이 계속 가려진다. 안내는 지금 무슨 일이 있었는지
/// 알려주는 것이라 같은 말을 다섯 번 이어 붙일 이유가 없다.
///
/// 그래서 여기서는 **이미 떠 있으면 새 요청을 버린다.** 뒤엣것으로 갈아 끼우지도
/// 않는다 — 방금 읽기 시작한 문장이 같은 문장으로 교체되면서 타이머만 늘어나는
/// 편이 더 어색하기 때문이다.
class TransientMessenger {
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _current;

  void show(BuildContext context, String message) {
    if (_current != null) return;

    final controller = ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));

    _current = controller;

    // 사용자가 밀어서 지웠든 시간이 다 됐든, 사라지면 다음 안내를 받는다.
    controller.closed.whenComplete(() {
      if (identical(_current, controller)) _current = null;
    });
  }
}
