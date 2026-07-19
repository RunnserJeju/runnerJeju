import 'package:flutter_test/flutter_test.dart';

import 'package:runners_jeju/main.dart';

void main() {
  testWidgets('연결 테스트 화면이 초기 상태로 표시된다', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('아직 테스트하지 않음'), findsOneWidget);
    expect(find.text('서버 연결 테스트'), findsOneWidget);
  });
}
