import 'package:flutter/material.dart';

import '../models/run_stamp.dart';
import '../theme/app_theme.dart';
import '../widgets/stamp_celebration.dart';

/// 스탬프 획득 팝업 미리보기. 서버·로그인 없이 연출만 본다.
///
///   flutter run -t lib/dev/stamp_celebration_preview.dart
void main() => runApp(
  MaterialApp(
    theme: AppTheme.light,
    debugShowCheckedModeBanner: false,
    home: const _Preview(),
  ),
);

class _Preview extends StatefulWidget {
  const _Preview();

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  final _stamp = RunStamp(
    id: 'preview',
    courseId: 'preview',
    courseName: '사려니숲길 코스',
    acquiredAt: DateTime.now(),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _show());
  }

  void _show() => showStampCelebration(context, _stamp);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('스탬프 팝업 미리보기')),
      // 팝업 문구와 겹치지 않게 아래에 둔다.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: FilledButton(onPressed: _show, child: const Text('다시 보기')),
        ),
      ),
    );
  }
}
