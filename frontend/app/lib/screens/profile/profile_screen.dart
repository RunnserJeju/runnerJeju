import 'package:flutter/material.dart';

import '../../models/run_record.dart';
import '../../models/running_course.dart';
import '../../models/running_program.dart';
import '../../services/service_locator.dart';
import '../../utils/formatters.dart';
import '../../widgets/async_view.dart';
import '../../widgets/course_card.dart';
import '../../widgets/metric_tile.dart';
import '../auth/login_screen.dart';
import '../connection_test_screen.dart';
import '../course/course_detail_screen.dart';
import '../run/run_detail_screen.dart';

/// 프로필: 최근 한 달 러닝 요약 + 찜한 코스 + 참여한 프로그램.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<_ProfileData> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = _ProfileData.load();
  }

  Future<void> _refresh() async {
    setState(_load);
    await _future.catchError((_) => _ProfileData.empty);
  }

  Future<void> _logout() async {
    await Services.instance.auth.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('마이페이지'),
        actions: [
          IconButton(
            tooltip: '서버 연결 테스트',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ConnectionTestScreen()),
            ),
            icon: const Icon(Icons.settings_ethernet_rounded),
          ),
          IconButton(
            tooltip: '로그아웃',
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<_ProfileData>(
          future: _future,
          builder: (context, snapshot) => AsyncView<_ProfileData>(
            snapshot: snapshot,
            onRetry: _refresh,
            builder: (context, data) => _ProfileBody(data: data),
          ),
        ),
      ),
    );
  }
}

/// 마이페이지가 그리는 세 갈래 데이터. 서로 독립이라 한 번에 받아 둔다.
class _ProfileData {
  const _ProfileData({
    required this.recentRuns,
    required this.favorites,
    required this.programs,
  });

  /// 최근 한 달 러닝만. 요약과 목록이 같은 집합을 본다.
  final List<RunRecord> recentRuns;
  final List<RunningCourse> favorites;
  final List<RunningProgram> programs;

  static const empty = _ProfileData(
    recentRuns: [],
    favorites: [],
    programs: [],
  );

  static Future<_ProfileData> load() async {
    final results = await Future.wait([
      Services.instance.run.loadMyRecords(limit: 50),
      Services.instance.favorite.loadFavoriteCourses(),
      Services.instance.program.loadMyPrograms(),
    ]);

    final since = DateTime.now().subtract(const Duration(days: 30));
    final recentRuns = (results[0] as List<RunRecord>)
        .where((r) => r.startedAt.isAfter(since))
        .toList();

    return _ProfileData(
      recentRuns: recentRuns,
      favorites: results[1] as List<RunningCourse>,
      programs: results[2] as List<RunningProgram>,
    );
  }
}

class _ProfileBody extends StatefulWidget {
  const _ProfileBody({required this.data});

  final _ProfileData data;

  @override
  State<_ProfileBody> createState() => _ProfileBodyState();
}

class _ProfileBodyState extends State<_ProfileBody> {
  /// 러닝 목록은 처음 5개만 보여주고, '더보기'마다 10개씩 늘린다.
  static const int _initialRunCount = 5;
  static const int _moreRunStep = 10;

  int _visibleRunCount = _initialRunCount;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final runs = data.recentRuns;
    final totalDistance = runs.fold<double>(
      0,
      (sum, r) => sum + r.distanceMeters,
    );
    final totalDuration = runs.fold<Duration>(
      Duration.zero,
      (sum, r) => sum + r.duration,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: MetricTile(
                    label: '총 거리',
                    value: Formatters.distanceKm(totalDistance),
                    unit: 'km',
                  ),
                ),
                Expanded(
                  child: MetricTile(
                    label: '총 시간',
                    value: Formatters.duration(totalDuration),
                  ),
                ),
                Expanded(
                  child: MetricTile(
                    label: '러닝',
                    value: '${runs.length}',
                    unit: '회',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),
        const _SectionTitle('최근 한 달 러닝'),
        const SizedBox(height: 12),
        if (runs.isEmpty)
          const _EmptyNote(
            icon: Icons.directions_run_rounded,
            message: '최근 한 달 러닝 기록이 없어요',
          )
        else ...[
          for (final record in runs.take(_visibleRunCount)) ...[
            _RecordTile(record: record),
            const SizedBox(height: 10),
          ],
          if (runs.length > _visibleRunCount)
            Center(
              child: TextButton.icon(
                onPressed: () =>
                    setState(() => _visibleRunCount += _moreRunStep),
                icon: const Icon(Icons.expand_more_rounded),
                label: Text('더보기 (${runs.length - _visibleRunCount}개)'),
              ),
            ),
        ],
        const SizedBox(height: 28),
        const _SectionTitle('찜한 코스'),
        const SizedBox(height: 12),
        if (data.favorites.isEmpty)
          const _EmptyNote(
            icon: Icons.favorite_border_rounded,
            message: '찜한 코스가 없어요',
          )
        else
          for (final course in data.favorites) ...[
            CourseCard(
              course: course,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CourseDetailScreen(courseId: course.id),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        const SizedBox(height: 28),
        const _SectionTitle('참여한 프로그램'),
        const SizedBox(height: 12),
        if (data.programs.isEmpty)
          const _EmptyNote(
            icon: Icons.groups_rounded,
            message: '참여한 프로그램이 없어요',
          )
        else
          for (final program in data.programs) ...[
            _ProgramTile(program: program),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
      ),
    );
  }
}

/// 섹션이 비었을 때의 짧은 안내. 화면 전체를 덮는 대신 자리만 채운다.
class _EmptyNote extends StatelessWidget {
  const _EmptyNote({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(
      alpha: 0.45,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: muted),
          const SizedBox(width: 8),
          Text(
            message,
            style: TextStyle(fontSize: 14, color: muted),
          ),
        ],
      ),
    );
  }
}

class _ProgramTile extends StatelessWidget {
  const _ProgramTile({required this.program});

  final RunningProgram program;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final period = _period(program);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(
              Icons.groups_rounded,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    program.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  if (period != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      period,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.55,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 진행 기간. 둘 다 없으면(상시 모집) 표기하지 않는다.
  String? _period(RunningProgram program) {
    final start = program.startDate;
    final end = program.endDate;
    if (start == null && end == null) return null;
    if (start != null && end != null) {
      return '${Formatters.date(start)} ~ ${Formatters.date(end)}';
    }
    return Formatters.date((start ?? end)!);
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.record});

  final RunRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => RunDetailScreen(record: record)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(
                record.isCourseRun
                    ? Icons.route_rounded
                    : Icons.directions_run_rounded,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      record.courseName ?? '자유 러닝',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      Formatters.dateTime(record.startedAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.55,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${Formatters.distanceKm(record.distanceMeters)}km',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    Formatters.pace(record.paceSecondsPerKm),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.55,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
