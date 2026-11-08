import 'package:flutter_test/flutter_test.dart';
import 'package:runners_jeju/services/run_flow_presence.dart';

void main() {
  test('첫 화면이 들어오고 마지막 화면이 나갈 때만 알린다', () async {
    final presence = RunFlowPresence();
    var notified = 0;
    presence.addListener(() => notified++);

    presence.enter();
    expect(presence.isOpen, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(notified, 1);

    presence.leave();
    expect(presence.isOpen, isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(notified, 2);
  });

  test('러닝 화면이 결과 화면으로 바뀌는 동안(들어온 뒤 나감) 닫히지 않는다', () async {
    final presence = RunFlowPresence();
    var notified = 0;
    presence.addListener(() => notified++);

    presence.enter(); // 러닝 화면
    await Future<void>.delayed(Duration.zero);
    presence.enter(); // 결과 화면이 먼저 들어오고
    presence.leave(); // 러닝 화면이 나중에 나간다
    await Future<void>.delayed(Duration.zero);

    expect(presence.isOpen, isTrue);
    expect(notified, 1);
  });

  test('들어온 적 없이 나가도 음수가 되지 않는다', () {
    final presence = RunFlowPresence()..leave();
    expect(presence.isOpen, isFalse);
    presence.enter();
    expect(presence.isOpen, isTrue);
  });
}
