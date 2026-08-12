import 'package:flutter/material.dart';

import '../../models/running_course.dart';
import '../../services/service_locator.dart';
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
                    if (course.tagList.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final tag in course.tagList)
                            Chip(
                              label: Text(tag),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: MetricTile(
                            label: '거리 (왕복)',
                            value: '${course.distanceKm}',
                            unit: 'km',
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
                    _InfoRow(
                      icon: Icons.place_outlined,
                      label: '주소',
                      value: course.address,
                    ),
                    if (course.parkingAddress != null)
                      _InfoRow(
                        icon: Icons.local_parking_outlined,
                        label: '근처 주차장',
                        value: course.parkingAddress!,
                      ),
                    if (course.restroomAddress != null)
                      _InfoRow(
                        icon: Icons.wc_outlined,
                        label: '근처 화장실',
                        value: course.restroomAddress!,
                      ),
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

/// 주소·주차장·화장실처럼 "이름: 값" 한 줄로 보여주는 정보.
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: muted),
          const SizedBox(width: 8),
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
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
