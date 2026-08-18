import 'package:flutter/material.dart';

import '../../models/run_record.dart';
import '../../utils/formatters.dart';
import '../../widgets/metric_tile.dart';
import '../../widgets/run_map_view.dart';

/// 러닝 상세: 마이페이지에서 지난 기록을 눌렀을 때 뛴 경로와 간단한 정보를 보여준다.
/// 이미 로드된 [RunRecord]를 그대로 받아 추가 네트워크 요청 없이 렌더링한다.
class RunDetailScreen extends StatelessWidget {
  const RunDetailScreen({super.key, required this.record});

  final RunRecord record;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(record.courseName ?? '자유 러닝')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Card(
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              height: 240,
              child: RunMapView(runPath: record.path),
            ),
          ),
          const SizedBox(height: 20),
          _DetailMetrics(record: record),
        ],
      ),
    );
  }
}

class _DetailMetrics extends StatelessWidget {
  const _DetailMetrics({required this.record});

  final RunRecord record;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              Formatters.dateTime(record.startedAt),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: MetricTile(
                label: '거리 (KM)',
                value: Formatters.distanceKm(record.distanceMeters),
                emphasized: true,
                alignment: CrossAxisAlignment.center,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                MetricTile(
                  label: '시간',
                  value: Formatters.duration(record.duration),
                  alignment: CrossAxisAlignment.center,
                ),
                MetricTile(
                  label: '평균 페이스',
                  value: Formatters.pace(record.paceSecondsPerKm),
                  alignment: CrossAxisAlignment.center,
                ),
                MetricTile(
                  label: '평균 속도',
                  value: record.speedKmh?.toStringAsFixed(1) ?? '--',
                  unit: 'km/h',
                  alignment: CrossAxisAlignment.center,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
