import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runners_jeju/models/geo_point.dart';
import 'package:runners_jeju/models/run_record.dart';
import 'package:runners_jeju/widgets/share/run_share_card.dart';

/// 인스타 스토리로 내보낼 공유 카드.
///
/// 이 카드는 화면에서 읽히는 게 아니라 **이미지로 구워져 나가므로**, 화면에서
/// 괜찮아 보이는 것만으로는 검증이 안 된다. 여기서 보는 것은 셋이다.
///
/// 1. 인스타가 가리는 영역(상단 260 / 하단 320)을 침범하지 않는다.
/// 2. 요소가 카드 밖으로 나가지 않는다.
/// 3. 경로가 어떻게 생겼든(한 점, 두 점, 끊긴 구간) 그리다 죽지 않는다.
void main() {
  /// 사계해안도로를 왕복한 모양의 경로. 실제 GPX처럼 시작점과 끝점이 같다.
  List<GeoPoint> outAndBack() {
    const start = GeoPoint(latitude: 33.22849, longitude: 126.30641);
    final outbound = [
      for (var i = 0; i < 20; i++)
        GeoPoint(
          latitude: start.latitude - i * 0.0004,
          longitude: start.longitude - i * 0.0002,
        ),
    ];
    return [...outbound, ...outbound.reversed];
  }

  RunRecord courseRun({List<GeoPoint>? path}) => RunRecord(
    id: 'run-1',
    courseId: 'course-1',
    courseName: '사계해안도로',
    startedAt: DateTime(2026, 9, 24, 19, 12),
    endedAt: DateTime(2026, 9, 24, 19, 51),
    distanceMeters: 6233,
    duration: const Duration(minutes: 38, seconds: 57),
    path: path ?? outAndBack(),
  );

  RunRecord freeRun() => RunRecord(
    startedAt: DateTime(2026, 9, 24, 19, 12),
    endedAt: DateTime(2026, 9, 24, 19, 32),
    distanceMeters: 3000,
    duration: const Duration(minutes: 20),
    path: outAndBack(),
  );

  /// 카드를 설계 크기(1080×1920) 그대로 띄운다. [FittedBox] 없이 올려야
  /// [WidgetTester.getRect]가 설계 좌표를 돌려준다.
  Future<void> pumpCard(
    WidgetTester tester,
    RunRecord record, {
    ShareCardTheme theme = ShareCardTheme.dark,
  }) async {
    await tester.binding.setSurfaceSize(
      const Size(RunShareCard.width, RunShareCard.height),
    );
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Center(child: RunShareCard(record: record, theme: theme)),
      ),
    );
  }

  group('내용', () {
    testWidgets('코스 러닝은 코스명·완주 인증·지표를 보여준다', (tester) async {
      await pumpCard(tester, courseRun());

      expect(find.text('사계해안도로'), findsOneWidget);
      expect(find.text('완주 인증'), findsOneWidget);

      // 거리 6.23km, 시간 38:57, 페이스 6'15"/km, 속도 9.6km/h.
      expect(find.text('6.23'), findsOneWidget);
      expect(find.text('KM'), findsOneWidget);
      expect(find.text('38:57'), findsOneWidget);
      expect(find.textContaining("6'15"), findsOneWidget);
      expect(find.text('9.6'), findsOneWidget);
    });

    testWidgets('자유 러닝은 인증 배지 대신 출발 시각이 온다', (tester) async {
      await pumpCard(tester, freeRun());

      expect(find.text('자유 러닝'), findsOneWidget);
      expect(find.text('완주 인증'), findsNothing);
      expect(find.text('오후 7:12 출발'), findsOneWidget);
    });

    testWidgets('속도 단위는 값과 라벨 어느 쪽에도 합쳐지지 않는다', (tester) async {
      // 단위를 값에 같은 크기로 붙이면 값이 칸(306px)을 넘어 잘리고,
      // 라벨에 '(km/h)'로 넣으면 라벨이 두 줄로 감겨 세이프존을 넘는다.
      // 그래서 값 옆에 작은 글씨로 따로 둔다.
      await pumpCard(tester, courseRun());

      expect(find.text('평균 속도'), findsOneWidget);
      expect(find.text('km/h'), findsOneWidget);
      expect(find.text('9.6'), findsOneWidget);
      expect(find.textContaining('9.6 km/h'), findsNothing);
      expect(find.textContaining('(km/h)'), findsNothing);
    });
  });

  group('세이프존', () {
    /// 카드 위의 모든 [RenderBox]를 훑어 y 범위를 본다. 텍스트 하나하나를
    /// 나열하면 나중에 요소를 더할 때 검사에서 빠진다.
    void expectWithinSafeArea(WidgetTester tester) {
      final card = tester.getRect(find.byType(RunShareCard));

      for (final element in find
          .descendant(
            of: find.byType(RunShareCard),
            matching: find.byWidgetPredicate((w) => w is Text || w is Container),
          )
          .evaluate()) {
        final box = element.renderObject as RenderBox?;
        if (box == null || !box.hasSize || box.size.isEmpty) continue;

        final rect = tester.getRect(find.byElementPredicate((e) => e == element));
        final top = rect.top - card.top;
        final bottom = rect.bottom - card.top;

        expect(
          top,
          greaterThanOrEqualTo(RunShareCard.safeTop),
          reason: '${element.widget.runtimeType}가 상단 세이프존을 침범한다',
        );
        expect(
          bottom,
          lessThanOrEqualTo(RunShareCard.height - RunShareCard.safeBottom),
          reason: '${element.widget.runtimeType}가 하단 세이프존을 침범한다',
        );
        expect(
          rect.left - card.left,
          greaterThanOrEqualTo(0),
          reason: '${element.widget.runtimeType}가 카드 왼쪽으로 나간다',
        );
        expect(
          rect.right - card.left,
          lessThanOrEqualTo(RunShareCard.width),
          reason: '${element.widget.runtimeType}가 카드 오른쪽으로 나간다',
        );
      }
    }

    testWidgets('코스 러닝의 모든 요소가 가려지지 않는 범위 안에 있다', (tester) async {
      await pumpCard(tester, courseRun());
      expectWithinSafeArea(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('자유 러닝도 같은 범위 안에 있다', (tester) async {
      await pumpCard(tester, freeRun());
      expectWithinSafeArea(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('긴 코스명도 카드 밖으로 넘치지 않는다', (tester) async {
      final record = RunRecord(
        courseId: 'c',
        courseName: '러닝아일랜드 우도런 13.7km + 소머리오름 코스',
        startedAt: DateTime(2026, 9, 24, 19, 12),
        endedAt: DateTime(2026, 9, 24, 20, 30),
        distanceMeters: 13700,
        duration: const Duration(minutes: 78),
        path: outAndBack(),
      );

      await pumpCard(tester, record);
      expectWithinSafeArea(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('경로 그리기', () {
    /// 경로가 [path]일 때 카드를 그려 본다. 예외가 없으면 통과.
    Future<void> expectDraws(WidgetTester tester, List<GeoPoint> path) async {
      await pumpCard(tester, courseRun(path: path));
      expect(tester.takeException(), isNull);
    }

    testWidgets('빈 경로에도 죽지 않는다', (tester) async {
      // 시작 직후 GPS를 한 번도 못 받고 끝난 기록.
      await expectDraws(tester, const []);
    });

    testWidgets('한 점에 머문 경로에도 죽지 않는다', (tester) async {
      // 좌표 범위가 0이라 확대 배율이 무한이 되는 경우.
      await expectDraws(tester, const [
        GeoPoint(latitude: 33.22849, longitude: 126.30641),
        GeoPoint(latitude: 33.22849, longitude: 126.30641),
      ]);
    });

    testWidgets('일시정지로 끊긴 경로도 그린다', (tester) async {
      final path = [
        const GeoPoint(latitude: 33.228, longitude: 126.306),
        const GeoPoint(latitude: 33.229, longitude: 126.307),
        // 재개한 첫 점. 직전 점과 이어 그리면 안 된다.
        const GeoPoint(
          latitude: 33.240,
          longitude: 126.320,
          startsNewSegment: true,
        ),
        const GeoPoint(latitude: 33.241, longitude: 126.321),
      ];

      await expectDraws(tester, path);
    });

    testWidgets('재개하자마자 끝난 한 점짜리 조각도 그린다', (tester) async {
      final path = [
        const GeoPoint(latitude: 33.228, longitude: 126.306),
        const GeoPoint(latitude: 33.229, longitude: 126.307),
        const GeoPoint(
          latitude: 33.240,
          longitude: 126.320,
          startsNewSegment: true,
        ),
      ];

      await expectDraws(tester, path);
    });
  });

  group('이미지 내보내기', () {
    testWidgets('줄여 놓은 미리보기에서도 1080px 폭으로 캡처된다', (tester) async {
      // 실제 화면과 같은 조건: 카드를 FittedBox로 줄여 RepaintBoundary로 감싼다.
      // ShareCardRenderer가 이 축소분을 역산해 1080px을 얻는다.
      final key = GlobalKey();
      const previewWidth = 320.0;

      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: previewWidth,
              child: AspectRatio(
                aspectRatio: RunShareCard.width / RunShareCard.height,
                child: RepaintBoundary(
                  key: key,
                  child: FittedBox(child: RunShareCard(record: courseRun())),
                ),
              ),
            ),
          ),
        ),
      );
      // pumpAndSettle은 여기서 끝나지 않는다(SVG 로딩이 프레임을 계속 요청).
      // 그릴 것이 다 올라오도록 몇 프레임만 명시적으로 돌린다.
      await tester.pump(const Duration(milliseconds: 100));

      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      expect(boundary.size.width, moreOrLessEquals(previewWidth, epsilon: 1));

      // 래스터화는 실제 비동기다. 그냥 await하면 테스트 바인딩의 가짜 시계가
      // 돌지 않아 영영 끝나지 않으므로 runAsync 안에서 돌려야 한다.
      final ui.Image image = (await tester.runAsync(
        () => boundary.toImage(pixelRatio: 1080 / boundary.size.width),
      ))!;
      addTearDown(image.dispose);

      expect(image.width, 1080);
      // 9:16을 유지한다. 미리보기 폭이 나누어떨어지지 않아 1px 오차는 허용한다.
      expect(image.height, closeTo(1920, 2));

      final png = await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.png),
      );
      expect(png, isNotNull);
      expect(png!.lengthInBytes, greaterThan(0));
      // 스토리 권장 최소(720×1280)를 넉넉히 넘는다.
      expect(math.min(image.width, image.height), greaterThanOrEqualTo(720));
    });
  });
}
