import 'package:flutter/material.dart';

import '../features/running_week/running_week.dart';
import '../features/running_week/running_week_screen.dart';
import '../models/run_stamp.dart';
import '../theme/app_theme.dart';

/// 러닝위크 빙고판 미리보기. 서버·로그인 없이 칸이 채워진 모습만 본다.
///
///   flutter run -t lib/dev/bingo_preview.dart
///
/// 위 칩으로 채움 상태를 바꾼다. 도안은 넣지 않아 받은 칸은 기본 도안(별)으로 보인다.
void main() => runApp(
  MaterialApp(
    theme: AppTheme.light,
    debugShowCheckedModeBanner: false,
    home: const _Preview(),
  ),
);

/// 채움 상태. 칸 번호(0~24)는 왼쪽 위부터 가로로 센다.
enum _Preset {
  empty('빈 판', {}),
  scattered('띄엄띄엄', {0, 6, 8, 13, 17, 21}),
  oneRow('가로 1줄', {10, 11, 12, 13, 14, 3, 19}),
  diagonal('대각선', {0, 6, 12, 18, 24, 4, 20}),
  threeLines('3줄', {0, 1, 2, 3, 4, 7, 12, 17, 22, 6, 18, 24}),
  full('전부', {
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, //
    13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24,
  });

  const _Preset(this.label, this.acquired);

  final String label;
  final Set<int> acquired;
}

class _Preview extends StatefulWidget {
  const _Preview();

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  _Preset _preset = _Preset.threeLines;

  // 이름 길이를 섞어 둔다 — 긴 이름이 한 줄로 잘리는지 본다.
  static const _names = [
    'No1. 사려니숲길',
    'No2. 용눈이오름 둘레길 러닝 코스',
    'No3. 탑동',
    'No4. 함덕',
    'No5. 서귀포 칠십리 해안 산책로',
  ];

  RunningWeek _weekFor(_Preset preset) {
    final cells = [
      for (var i = 0; i < Bingo.size * Bingo.size; i++)
        BingoCell(
          position: i,
          acquired: preset.acquired.contains(i),
          stamp: StampDefinition(
            id: 'preview-$i',
            name: i % 6 == 5
                ? '임시 스탬프 ${i ~/ 6 + 1}'
                : _names[i % _names.length],
            conditionType: i % 6 == 5 ? 'manual' : 'course_complete',
            courseId: i % 6 == 5 ? null : 'preview-course-$i',
            description: '미리보기용 스탬프예요.',
          ),
        ),
    ];
    return RunningWeek(
      id: 'preview',
      title: '러닝위크 미리보기',
      participated: true,
      bingo: Bingo(
        cells: cells,
        completedLines: _completedLines([for (final c in cells) c.acquired]),
      ),
    );
  }

  /// 서버 routers/running_weeks.completed_lines와 같은 계산.
  static int _completedLines(List<bool> acquired) {
    const n = Bingo.size;
    final lines = [
      for (var r = 0; r < n; r++) [for (var c = 0; c < n; c++) r * n + c],
      for (var c = 0; c < n; c++) [for (var r = 0; r < n; r++) r * n + c],
      [for (var i = 0; i < n; i++) i * n + i],
      [for (var i = 0; i < n; i++) i * n + (n - 1 - i)],
    ];
    return lines.where((line) => line.every((i) => acquired[i])).length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            // 프리셋을 바꿀 때마다 화면 상태를 새로 만든다.
            child: RunningWeekScreen(
              key: ValueKey(_preset),
              week: _weekFor(_preset),
              onOpenCourse: (courseId) => ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('코스 안내로 이동: $courseId'))),
            ),
          ),
          SafeArea(
            top: false,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  for (final preset in _Preset.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(preset.label),
                        selected: preset == _preset,
                        onSelected: (_) => setState(() => _preset = preset),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
