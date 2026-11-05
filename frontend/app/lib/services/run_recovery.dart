import 'dart:async';

/// 앱 시작 시 "지난 러닝 복구"가 화면을 차지하는지 알려주는 신호.
///
/// AppShell이 일지를 읽고 결정하면 [settle]로 알리고, 실행 시 공지 팝업처럼
/// 시작 직후 뜨는 것들은 [takesOverLaunch]를 기다렸다가 true면 건너뛴다 —
/// 복구 팝업이나 결과 화면 위에 공지가 겹쳐 뜨지 않게.
class RunRecovery {
  Completer<bool> _decision = Completer();

  /// AppShell이 뜰 때마다 새로 판단한다(재로그인으로 다시 뜨는 경우 포함).
  void begin() {
    if (_decision.isCompleted) _decision = Completer();
  }

  void settle(bool takesOver) {
    if (!_decision.isCompleted) _decision.complete(takesOver);
  }

  Future<bool> get takesOverLaunch => _decision.future;
}
