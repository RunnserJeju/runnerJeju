import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runners_jeju/models/course_facility.dart';
import 'package:runners_jeju/models/running_course.dart';
import 'package:runners_jeju/screens/course/gpx_upload_screen.dart';

/// 등록 화면의 주차장/화장실 동적 목록 UI만 본다. "확인"/제출은 네트워크(geo)를
/// 타므로 여기서 건드리지 않는다 — 그 검증 로직은 course_facility_test.dart가 본다.
void main() {
  // 화면이 길어서 기본 뷰포트(800px)엔 다 안 들어온다. 모든 행이 빌드되도록
  // 큰 뷰포트를 준다(ListView는 화면 밖 항목을 지연 생성하기 때문).
  void useTallView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('주차장/화장실 섹션이 각각 빈 줄 하나로 시작한다', (tester) async {
    useTallView(tester);
    await tester.pumpWidget(const MaterialApp(home: GpxUploadScreen()));
    await tester.pumpAndSettle();

    expect(find.text('근처 주차장'), findsOneWidget);
    expect(find.text('근처 화장실'), findsOneWidget);
    // 주차장1 + 화장실1 = 이름 필드 2개, 확인 버튼 2개.
    expect(find.text('이름 (선택)'), findsNWidgets(2));
    expect(find.widgetWithText(OutlinedButton, '확인'), findsNWidgets(2));
  });

  testWidgets('추가 버튼이 행을 하나 늘린다', (tester) async {
    useTallView(tester);
    await tester.pumpWidget(const MaterialApp(home: GpxUploadScreen()));
    await tester.pumpAndSettle();

    // 첫 번째 '추가'(주차장) 탭 → 이름 필드 3개.
    await tester.tap(find.widgetWithText(TextButton, '추가').first);
    await tester.pumpAndSettle();

    expect(find.text('이름 (선택)'), findsNWidgets(3));
  });

  testWidgets('삭제 버튼이 행을 하나 줄인다', (tester) async {
    useTallView(tester);
    await tester.pumpWidget(const MaterialApp(home: GpxUploadScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();

    // 주차장 행이 지워져 이름 필드가 1개(화장실만) 남는다.
    expect(find.text('이름 (선택)'), findsNWidgets(1));
  });

  testWidgets('수정 모드: 기존 값 프리필 + GPX 섹션 숨김 + 확인됨 상태', (tester) async {
    useTallView(tester);
    const course = RunningCourse(
      id: 'c1',
      name: '테스트 코스',
      distanceKm: 7,
      address: '제주시 어딘가',
      difficulty: CourseDifficulty.hard,
      tags: '해안,서쪽',
      parkings: [
        CourseFacility(name: '주차장A', address: '제주 A', lat: 33.5, lng: 126.5),
      ],
      restrooms: [],
      path: [],
    );

    await tester.pumpWidget(
      const MaterialApp(home: GpxUploadScreen(existing: course)),
    );
    await tester.pumpAndSettle();

    // 제목·버튼이 수정용으로 바뀐다.
    expect(find.text('코스 수정'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '수정 완료'), findsOneWidget);
    // 기존 값이 채워진다(이름·주소).
    expect(find.text('테스트 코스'), findsOneWidget);
    expect(find.text('제주시 어딘가'), findsOneWidget);
    // 경로는 못 바꾸므로 GPX 파일 칸은 없다.
    expect(find.text('GPX 파일'), findsNothing);
    expect(find.text('파일 선택'), findsNothing);
    // 기존 주차장은 좌표가 있으니 다시 확인하지 않아도 "확인됨"으로 시작한다.
    expect(find.text('✓ 좌표 확인됨'), findsOneWidget);
  });
}
