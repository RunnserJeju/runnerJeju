import 'package:flutter/material.dart';

import '../../models/run_record.dart';
import '../../services/service_locator.dart';
import '../../utils/formatters.dart';
import '../../widgets/async_view.dart';
import '../../widgets/metric_tile.dart';
import '../connection_test_screen.dart';

/// 프로필: 누적 기록 요약 + 최근 러닝 목록.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<List<RunRecord>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = Services.instance.run.loadMyRecords(limit: 50);
  }

  Future<void> _refresh() async {
    setState(_load);
    await _future.catchError((_) => <RunRecord>[]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('프로필'),
        actions: [
          IconButton(
            tooltip: '서버 연결 테스트',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ConnectionTestScreen()),
            ),
            icon: const Icon(Icons.settings_ethernet_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<RunRecord>>(
          future: _future,
          builder: (context, snapshot) => AsyncView<List<RunRecord>>(
            snapshot: snapshot,
            onRetry: _refresh,
            isEmpty: (records) => records.isEmpty,
            emptyTitle: '아직 러닝 기록이 없어요',
            emptyMessage: '첫 러닝을 시작해 보세요',
            emptyIcon: Icons.directions_run_rounded,
            builder: (context, records) => _ProfileBody(records: records),
          ),
        ),
      ),
    );
  }
}

class _ProfileBody extends StatelessWidget {
  const _ProfileBody({required this.records});

  final List<RunRecord> records;

  @override
  Widget build(BuildContext context) {
    final totalDistance = records.fold<double>(
      0,
      (sum, r) => sum + r.distanceMeters,
    );
    final totalDuration = records.fold<Duration>(
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
                    value: '${records.length}',
                    unit: '회',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),
        const Text(
          '최근 러닝',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 12),
        for (final record in records) ...[
          _RecordTile(record: record),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.record});

  final RunRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
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
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
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
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
