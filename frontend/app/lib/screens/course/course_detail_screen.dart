import 'package:flutter/material.dart';

import '../../models/running_course.dart';
import '../../services/service_locator.dart';
import '../../utils/formatters.dart';
import '../../widgets/async_view.dart';
import '../../widgets/metric_tile.dart';
import '../../widgets/run_map_view.dart';
import '../run/run_screen.dart';

/// 코스 상세: 지도에 코스 경로를 그리고, 이 코스로 러닝을 시작할 수 있다.
class CourseDetailScreen extends StatefulWidget {
  const CourseDetailScreen({super.key, required this.courseId});

  final String courseId;

  @override
  State<CourseDetailScreen> createState() => _CourseDetailScreenState();
}

class _CourseDetailScreenState extends State<CourseDetailScreen> {
  late Future<RunningCourse> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = Services.instance.course.loadCourse(widget.courseId);
  }

  void _startCourseRun(RunningCourse course) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => RunScreen(course: course)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('코스 상세')),
      body: FutureBuilder<RunningCourse>(
        future: _future,
        builder: (context, snapshot) => AsyncView<RunningCourse>(
          snapshot: snapshot,
          onRetry: () => setState(_load),
          builder: (context, course) => _CourseDetailBody(
            course: course,
            onStart: () => _startCourseRun(course),
          ),
        ),
      ),
    );
  }
}

class _CourseDetailBody extends StatelessWidget {
  const _CourseDetailBody({required this.course, required this.onStart});

  final RunningCourse course;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              SizedBox(
                height: 280,
                child: RunMapView(coursePath: course.path),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      course.name,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                      ),
                    ),
                    if (course.region != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        course.region!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: MetricTile(
                            label: '거리',
                            value: Formatters.distanceKm(course.distanceMeters),
                            unit: 'km',
                          ),
                        ),
                        Expanded(
                          child: MetricTile(
                            label: '예상 시간',
                            value: course.estimatedDuration == null
                                ? '--:--'
                                : Formatters.duration(course.estimatedDuration!),
                          ),
                        ),
                        Expanded(
                          child: MetricTile(
                            label: '난이도',
                            value: course.difficulty.label,
                          ),
                        ),
                      ],
                    ),
                    if (course.description != null) ...[
                      const SizedBox(height: 24),
                      Text(
                        course.description!,
                        style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                      ),
                    ],
                    const SizedBox(height: 24),
                    _CompletionRow(course: course),
                  ],
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          minimum: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: FilledButton.icon(
            onPressed: course.path.length >= 2 ? onStart : null,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('이 코스로 달리기'),
          ),
        ),
      ],
    );
  }
}

class _CompletionRow extends StatelessWidget {
  const _CompletionRow({required this.course});

  final RunningCourse course;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          course.isCompletedByMe
              ? Icons.workspace_premium_rounded
              : Icons.people_alt_outlined,
          size: 18,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        ),
        const SizedBox(width: 6),
        Text(
          course.isCompletedByMe
              ? '완주 스탬프를 이미 받았어요'
              : '${course.completedCount}명이 완주했어요',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}
