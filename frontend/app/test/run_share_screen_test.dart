import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runners_jeju/models/geo_point.dart';
import 'package:runners_jeju/models/run_record.dart';
import 'package:runners_jeju/screens/run/run_share_screen.dart';
import 'package:runners_jeju/services/jeju_basemap.dart';
import 'package:runners_jeju/widgets/share/run_share_card.dart';

/// 공유 화면.
///
/// 여기서 지키려는 것은 **지형을 기다리는 동안 공유되지 않는 것**이다. 캡처는
/// 화면에 그려진 것을 그대로 굽기 때문에, 지형이 아직 안 붙은 채로 공유하면
/// 배경이 빠진 이미지가 인스타로 나간다. 눌러 보기 전에는 드러나지 않는 종류라
/// 테스트로 잡아 둔다.
void main() {
  final record = RunRecord(
    id: 'run-1',
    courseId: 'course-1',
    courseName: '사계해안도로',
    startedAt: DateTime(2026, 9, 24, 19, 12),
    endedAt: DateTime(2026, 9, 24, 19, 51),
    distanceMeters: 6233,
    duration: const Duration(minutes: 38, seconds: 57),
    path: const [
      GeoPoint(latitude: 33.22849, longitude: 126.30641),
      GeoPoint(latitude: 33.21785, longitude: 126.29857),
    ],
  );

  Future<void> pumpScreen(
    WidgetTester tester, {
    required _StubBasemap basemap,
    ShareCardTheme initialTheme = ShareCardTheme.dark,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: RunShareScreen(
          record: record,
          initialTheme: initialTheme,
          loadBasemap: basemap.load,
        ),
      ),
    );
  }

  /// 화면에 실제로 올라간 카드.
  RunShareCard card(WidgetTester tester) =>
      tester.widget<RunShareCard>(find.byType(RunShareCard));

  Finder shareButton() => find.widgetWithText(FilledButton, '스토리로 공유');

  group('지형 로딩', () {
    testWidgets('지형을 읽는 동안에는 공유할 수 없다', (tester) async {
      final service = _StubBasemap.pending();
      await pumpScreen(tester, basemap: service);

      expect(find.text('지도를 그리는 중'), findsOneWidget);
      expect(shareButton(), findsNothing);

      // 버튼이 눌리지 않는 상태여야 한다.
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);

      service.finish(null);
      await tester.pump();
    });

    testWidgets('지형을 읽고 나면 공유할 수 있다', (tester) async {
      final service = _StubBasemap.pending();
      await pumpScreen(tester, basemap: service);

      service.finish(null);
      await tester.pump();

      expect(find.text('지도를 그리는 중'), findsNothing);
      expect(shareButton(), findsOneWidget);

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('지형을 못 읽어도 카드는 그려진다', (tester) async {
      // 에셋이 깨져도 공유 자체는 되어야 한다.
      await pumpScreen(tester, basemap: _StubBasemap.returns(null));
      await tester.pump();

      expect(find.byType(RunShareCard), findsOneWidget);
      expect(card(tester).basemap, isNull);
      expect(shareButton(), findsOneWidget);
    });

    testWidgets('지형 읽기가 실패해도 공유가 막히지 않는다', (tester) async {
      await pumpScreen(tester, basemap: _StubBasemap.throws());
      await tester.pump();

      expect(card(tester).basemap, isNull);
      expect(shareButton(), findsOneWidget);
    });
  });

  group('배색', () {
    testWidgets('initialTheme이 처음 배색을 정한다', (tester) async {
      await pumpScreen(
        tester,
        basemap: _StubBasemap.returns(null),
        initialTheme: ShareCardTheme.light,
      );
      await tester.pump();

      expect(card(tester).theme, ShareCardTheme.light);
    });

    testWidgets('칩을 누르면 배색이 바뀐다', (tester) async {
      await pumpScreen(tester, basemap: _StubBasemap.returns(null));
      await tester.pump();

      expect(card(tester).theme, ShareCardTheme.dark);

      await tester.tap(find.text('라이트'));
      await tester.pump();

      expect(card(tester).theme, ShareCardTheme.light);
    });

    testWidgets('배색 선택지가 둘 다 읽힌다', (tester) async {
      // 앱 전역 ChipTheme이 흰 배경을 지정하고 있어, 머티리얼 칩을 그대로 쓰면
      // 이 어두운 화면에서 비선택 칩이 흰 배경 + 흰 글씨가 되어 사라졌었다.
      await pumpScreen(tester, basemap: _StubBasemap.returns(null));
      await tester.pump();

      for (final label in ['다크', '라이트']) {
        final text = tester.widget<Text>(find.text(label));
        expect(text.style?.color, isNotNull, reason: '$label 칩에 글자색이 없다');
        expect(
          text.style!.color,
          isNot(text.style!.backgroundColor),
          reason: '$label 칩의 글자와 배경이 같은 색이다',
        );
      }
    });
  });
}

/// 에셋을 읽지 않는 지형 출처.
///
/// 지형 읽기는 실제로는 에셋 디코딩이라, 테스트에서 그걸 기다리면 "읽는 중"
/// 상태를 붙잡을 수 없다. 결과가 도착하는 시점을 [finish]로 직접 정한다.
class _StubBasemap {
  _StubBasemap._(this._completer, {this.fails = false});

  /// [finish]를 부를 때까지 끝나지 않는다.
  factory _StubBasemap.pending() => _StubBasemap._(Completer<JejuBasemap?>());

  /// 곧바로 [basemap]을 준다.
  factory _StubBasemap.returns(JejuBasemap? basemap) =>
      _StubBasemap._(Completer<JejuBasemap?>()..complete(basemap));

  /// 읽기가 터지는 경우.
  factory _StubBasemap.throws() =>
      _StubBasemap._(Completer<JejuBasemap?>(), fails: true);

  final Completer<JejuBasemap?> _completer;
  final bool fails;

  void finish(JejuBasemap? basemap) => _completer.complete(basemap);

  Future<JejuBasemap?> load() {
    if (fails) return Future.error(StateError('에셋을 읽지 못했어요'));
    return _completer.future;
  }
}
