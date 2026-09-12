import 'package:flutter/material.dart';

import '../../models/run_record.dart';
import '../../widgets/run_metrics_card.dart';
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
          RunMetricsCard(record: record),
        ],
      ),
    );
  }
}
