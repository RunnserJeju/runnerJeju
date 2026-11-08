import 'package:flutter/material.dart';

import '../../exceptions/app_exception.dart';
import '../../models/run_record.dart';
import '../../models/running_course.dart';
import '../../services/service_locator.dart';
import 'run_screen.dart';

/// [record]에 이어 달리는 러닝 화면을 연다. 마이페이지 미완주 기록과 결과 화면 팝업이 쓴다.
///
/// 러닝 화면에는 원래 경로(코스 진행률을 이어 세고 지도에 흐리게 깐다)와 코스가 둘 다
/// 필요해서 먼저 받는다. 받는 동안은 화면을 막아 두 번 눌리지 않게 한다.
///
/// [replace]면 지금 화면(결과 화면)을 러닝 화면으로 바꾼다.
Future<void> openContinuationRun(
  BuildContext context,
  RunRecord record, {
  bool replace = false,
}) async {
  final courseId = record.courseId;
  final runId = record.id;
  if (courseId == null || runId == null) return;

  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: Center(child: CircularProgressIndicator()),
    ),
  );

  final RunRecord base;
  final RunningCourse course;
  try {
    base = record.path.isEmpty
        ? await Services.instance.run.loadRecord(runId)
        : record;
    course = await Services.instance.course.loadCourse(courseId);
  } on AppException catch (e) {
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return;
  }
  navigator.pop();

  final route = MaterialPageRoute<void>(
    builder: (_) => RunScreen(course: course, continuation: base),
  );
  if (replace) {
    navigator.pushReplacement(route);
  } else {
    navigator.push(route);
  }
}
