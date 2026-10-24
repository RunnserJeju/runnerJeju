import 'package:flutter/material.dart';

import '../../models/running_course.dart';
import '../../services/service_locator.dart';
import '../../theme/app_theme.dart';
import '../../widgets/async_view.dart';
import '../../widgets/course_card.dart';

/// 찜한 코스. 카드를 누르면 이 화면을 닫고 러닝 탭에서 그 코스를 연다.
class FavoriteCoursesScreen extends StatefulWidget {
  const FavoriteCoursesScreen({super.key, required this.onOpenCourse});

  final ValueChanged<String> onOpenCourse;

  @override
  State<FavoriteCoursesScreen> createState() => _FavoriteCoursesScreenState();
}

class _FavoriteCoursesScreenState extends State<FavoriteCoursesScreen> {
  late Future<List<RunningCourse>> _future = Services.instance.favorite
      .loadFavoriteCourses();

  Future<void> _refresh() async {
    setState(() {
      _future = Services.instance.favorite.loadFavoriteCourses();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(title: const Text('찜한 코스')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<RunningCourse>>(
          future: _future,
          builder: (context, snapshot) => AsyncView<List<RunningCourse>>(
            snapshot: snapshot,
            onRetry: _refresh,
            isEmpty: (courses) => courses.isEmpty,
            emptyTitle: '찜한 코스가 없어요',
            emptyIcon: Icons.favorite_border_rounded,
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
