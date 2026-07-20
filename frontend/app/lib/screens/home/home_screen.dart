import 'package:flutter/material.dart';

import '../../models/run_record.dart';
import '../../models/running_course.dart';
import '../../services/service_locator.dart';
import '../../utils/formatters.dart';
import '../../widgets/async_view.dart';
import '../../widgets/course_card.dart';
import '../../widgets/metric_tile.dart';
import '../course/course_detail_screen.dart';

/// 홈: 이번 주 요약 + 추천 코스.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<RunRecord>> _recordsFuture;
  late Future<List<RunningCourse>> _coursesFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _recordsFuture = Services.instance.run.loadMyRecords();
    _coursesFuture = Services.instance.course.loadCourses();
  }

  Future<void> _refresh() async {
    setState(_load);
    await Future.wait([
      _recordsFuture.catchError((_) => <RunRecord>[]),
      _coursesFuture.catchError((_) => <RunningCourse>[]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('오늘도 달려볼까요')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
          children: [
            _WeeklySummaryCard(future: _recordsFuture, onRetry: _refresh),
            const SizedBox(height: 28),
            const _SectionTitle('추천 코스'),
            const SizedBox(height: 12),
            _RecommendedCourses(future: _coursesFuture, onRetry: _refresh),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
      ),
    );
  }
}

/// 최근 7일 러닝을 합산해 보여준다. 합산은 서버 응답을 받아 앱에서 계산한다.
class _WeeklySummaryCard extends StatelessWidget {
  const _WeeklySummaryCard({required this.future, required this.onRetry});

  final Future<List<RunRecord>> future;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SizedBox(
          height: 116,
          child: FutureBuilder<List<RunRecord>>(
            future: future,
            builder: (context, snapshot) => AsyncView<List<RunRecord>>(
              snapshot: snapshot,
              onRetry: onRetry,
              isEmpty: (records) => records.isEmpty,
              emptyTitle: '이번 주 기록이 없어요',
              emptyMessage: '아래 버튼으로 첫 러닝을 시작해 보세요',
              emptyIcon: Icons.directions_run_rounded,
              builder: (context, records) => _SummaryContent(records: records),
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryContent extends StatelessWidget {
  const _SummaryContent({required this.records});

  final List<RunRecord> records;

  @override
  Widget build(BuildContext context) {
    final since = DateTime.now().subtract(const Duration(days: 7));
    final weekly = records.where((r) => r.startedAt.isAfter(since)).toList();

    final distance = weekly.fold<double>(0, (sum, r) => sum + r.distanceMeters);
    final duration = weekly.fold<Duration>(
      Duration.zero,
      (sum, r) => sum + r.duration,
    );
    final pace = distance > 0 ? duration.inSeconds / (distance / 1000) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '최근 7일 · ${weekly.length}회',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              flex: 2,
              child: MetricTile(
                label: '거리',
                value: Formatters.distanceKm(distance),
                unit: 'km',
              ),
            ),
            Expanded(
              child: MetricTile(
                label: '시간',
                value: Formatters.duration(duration),
              ),
            ),
            Expanded(
              child: MetricTile(
                label: '평균 페이스',
                value: Formatters.pace(pace),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RecommendedCourses extends StatelessWidget {
  const _RecommendedCourses({required this.future, required this.onRetry});

  final Future<List<RunningCourse>> future;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 210,
      child: FutureBuilder<List<RunningCourse>>(
        future: future,
        builder: (context, snapshot) => AsyncView<List<RunningCourse>>(
          snapshot: snapshot,
          onRetry: onRetry,
          isEmpty: (courses) => courses.isEmpty,
          emptyTitle: '아직 코스가 없어요',
          emptyMessage: '직접 달린 경로를 코스로 등록해 보세요',
          emptyIcon: Icons.route_rounded,
          builder: (context, courses) {
            final top = courses.take(5).toList();

            return ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: top.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) => CourseCard(
                course: top[index],
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CourseDetailScreen(courseId: top[index].id),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
