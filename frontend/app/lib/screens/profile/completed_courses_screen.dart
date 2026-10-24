import 'package:flutter/material.dart';

import '../../models/running_course.dart';
import '../../services/service_locator.dart';
import '../../theme/app_theme.dart';
import '../../widgets/async_view.dart';
import '../../widgets/course_card.dart';

/// 완주 코스: 완주 인증을 통과한 코스 목록. 카드를 누르면 이 화면을 닫고 러닝 탭에서
/// 그 코스를 연다.
class CompletedCoursesScreen extends StatefulWidget {
  const CompletedCoursesScreen({super.key, required this.onOpenCourse});

  final ValueChanged<String> onOpenCourse;

  @override
  State<CompletedCoursesScreen> createState() => _CompletedCoursesScreenState();
}

class _CompletedCoursesScreenState extends State<CompletedCoursesScreen> {
  late Future<List<RunningCourse>> _future = _load();

  static Future<List<RunningCourse>> _load() async {
    final courses = await Services.instance.course.loadCourses();
    return courses.where((c) => c.isCompletedByMe).toList();
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(title: const Text('완주 코스')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<RunningCourse>>(
          future: _future,
          builder: (context, snapshot) => AsyncView<List<RunningCourse>>(
            snapshot: snapshot,
            onRetry: _refresh,
            isEmpty: (courses) => courses.isEmpty,
            emptyTitle: '아직 완주한 코스가 없어요',
            emptyIcon: Icons.flag_outlined,
            builder: (context, courses) => ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              itemCount: courses.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final course = courses[index];
                return CourseCard(
                  course: course,
                  onTap: () {
                    Navigator.of(context).pop();
                    widget.onOpenCourse(course.id);
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
