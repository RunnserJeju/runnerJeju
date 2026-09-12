import 'package:flutter/material.dart';

import '../models/run_record.dart';
import '../utils/formatters.dart';
import 'metric_tile.dart';

/// 러닝 기록 요약 카드: 시작 시각, 거리(강조), 시간·평균 페이스·평균 속도.
/// 러닝 결과 화면과 기록 상세 화면이 같은 카드를 쓴다.
class RunMetricsCard extends StatelessWidget {
  const RunMetricsCard({super.key, required this.record});

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
