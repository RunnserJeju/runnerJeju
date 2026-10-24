import 'package:flutter/material.dart';

import '../../exceptions/app_exception.dart';
import '../../models/run_record.dart';
import '../../services/service_locator.dart';
import '../../utils/formatters.dart';
import '../run/run_detail_screen.dart';

/// 러닝 기록 한 줄. 누르면 상세. 경로 없이 받은 기록(달력)은 상세를 열기 전에
/// 경로까지 다시 받는다.
class RunRecordTile extends StatelessWidget {
  const RunRecordTile({super.key, required this.record});

  final RunRecord record;

  Future<void> _open(BuildContext context) async {
    var full = record;
    final id = record.id;
    if (record.path.isEmpty && id != null) {
      try {
        full = await Services.instance.run.loadRecord(id);
      } on AppException catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
        return;
      }
    }
    if (!context.mounted) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => RunDetailScreen(record: full)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(context),
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
                    Text(Formatters.dateTime(record.startedAt), style: subtle),
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
                  Text(Formatters.pace(record.paceSecondsPerKm), style: subtle),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
