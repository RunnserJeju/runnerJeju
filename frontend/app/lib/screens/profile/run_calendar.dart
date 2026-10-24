import 'package:flutter/material.dart';

import '../../models/run_record.dart';
import '../../services/service_locator.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/metric_tile.dart';
import 'run_record_tile.dart';

/// 캘린더: 월 합계 + 달력. 이번 달로 시작하고, 화살표나 제목을 눌러 달을 옮긴다.
/// 달린 날에 표시가 있고, 그날을 누르면 아래에 그날 기록이 나온다.
class RunCalendar extends StatefulWidget {
  const RunCalendar({super.key});

  @override
  State<RunCalendar> createState() => _RunCalendarState();
}

class _RunCalendarState extends State<RunCalendar> {
  /// 한 달 러닝을 한 번에 받는 상한. 서버 상한(500)과 같다.
  static const int _monthLimit = 500;

  late DateTime _month = _monthOf(DateTime.now());
  late Future<List<RunRecord>> _monthRuns = _loadMonth(_month);
  DateTime? _selectedDay;

  static DateTime _monthOf(DateTime d) => DateTime(d.year, d.month);

  Future<List<RunRecord>> _loadMonth(DateTime month) =>
      Services.instance.run.loadMyRecords(
        limit: _monthLimit,
        since: month,
        until: DateTime(month.year, month.month + 1),
        withPath: false,
      );

  void _showMonth(DateTime month) {
    final target = _monthOf(month);
    if (target.isAfter(_monthOf(DateTime.now()))) return;
    setState(() {
      _month = target;
      _selectedDay = null;
      _monthRuns = _loadMonth(target);
    });
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDatePickerMode: DatePickerMode.year,
      helpText: '조회할 달 선택',
    );
    if (picked != null) _showMonth(picked);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<RunRecord>>(
      future: _monthRuns,
      builder: (context, snapshot) {
        final runs = snapshot.data ?? const <RunRecord>[];
        final selected = _selectedDay;
        final dayRuns = selected == null
            ? const <RunRecord>[]
            : runs
                  .where((r) => _sameDay(r.startedAt.toLocal(), selected))
                  .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                child: Column(
                  children: [
                    _MonthHeader(
                      month: _month,
                      canGoNext: _month.isBefore(_monthOf(DateTime.now())),
                      onPrev: () =>
                          _showMonth(DateTime(_month.year, _month.month - 1)),
                      onNext: () =>
                          _showMonth(DateTime(_month.year, _month.month + 1)),
                      onPick: _pickMonth,
                    ),
                    const SizedBox(height: 8),
                    if (snapshot.hasError)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text(
                          '달력을 불러오지 못했어요',
                          style: TextStyle(color: AppColors.textSubtle),
                        ),
                      )
                    else ...[
                      _MonthSummary(runs: runs),
                      const SizedBox(height: 12),
                      _MonthGrid(
                        month: _month,
                        runDays: {
                          for (final r in runs) _dayKey(r.startedAt.toLocal()),
                        },
                        selectedDay: selected,
                        onTapDay: (day) => setState(
                          () => _selectedDay =
                              selected != null && _sameDay(selected, day)
                              ? null
                              : day,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (selected != null) ...[
              const SizedBox(height: 16),
              Text(
                Formatters.date(selected),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              for (final record in dayRuns) ...[
                RunRecordTile(record: record),
                const SizedBox(height: 10),
              ],
            ],
          ],
        );
      },
    );
  }
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

int _dayKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.canGoNext,
    required this.onPrev,
    required this.onNext,
    required this.onPick,
  });

  final DateTime month;
  final bool canGoNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: '이전 달',
          onPressed: onPrev,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: TextButton(
            onPressed: onPick,
            style: TextButton.styleFrom(foregroundColor: AppColors.ink),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${month.year}년 ${month.month}월',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(Icons.arrow_drop_down_rounded),
              ],
            ),
          ),
        ),
        IconButton(
          tooltip: '다음 달',
          onPressed: canGoNext ? onNext : null,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }
}

/// 보고 있는 달의 합계. 완주 코스는 그 달에 완주 인증이 통과한 코스 수(같은 코스는 1번).
class _MonthSummary extends StatelessWidget {
  const _MonthSummary({required this.runs});

  final List<RunRecord> runs;

  @override
  Widget build(BuildContext context) {
    final distance = runs.fold<double>(0, (sum, r) => sum + r.distanceMeters);
    final duration = runs.fold<Duration>(
      Duration.zero,
      (sum, r) => sum + r.duration,
    );
    final completedCourses = {
      for (final r in runs)
        if (r.completed && r.courseId != null) r.courseId,
    }.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: MetricTile(
              label: '총 거리',
              value: Formatters.distanceKm(distance),
              unit: 'km',
            ),
          ),
          Expanded(
            child: MetricTile(
              label: '총 시간',
              value: Formatters.duration(duration),
            ),
          ),
          Expanded(
            child: MetricTile(
              label: '완주 코스',
              value: '$completedCourses',
              unit: '개',
            ),
          ),
        ],
      ),
    );
  }
}

/// 일요일 시작 월 달력. 달린 날은 강조색 원, 오늘은 테두리, 고른 날은 검정 원.
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.runDays,
    required this.selectedDay,
    required this.onTapDay,
  });

  final DateTime month;
  final Set<int> runDays;
  final DateTime? selectedDay;
  final ValueChanged<DateTime> onTapDay;

  static const _weekdays = ['일', '월', '화', '수', '목', '금', '토'];

  int get _daysInMonth => DateTime(month.year, month.month + 1, 0).day;

  @override
  Widget build(BuildContext context) {
    final leading = DateTime(month.year, month.month).weekday % 7;
    final today = DateTime.now();
    final rows = ((leading + _daysInMonth) / 7).ceil();

    return Column(
      children: [
        Row(
          children: [
            for (final (i, label) in _weekdays.indexed)
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: i == 0 ? AppColors.danger : AppColors.textSubtle,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (var row = 0; row < rows; row++)
          Row(
            children: [
              for (var col = 0; col < 7; col++)
                Expanded(child: _cell(row * 7 + col - leading + 1, today)),
            ],
          ),
      ],
    );
  }

  Widget _cell(int dayNumber, DateTime today) {
    if (dayNumber < 1 || dayNumber > _daysInMonth) {
      return const SizedBox(height: 44);
    }
    final day = DateTime(month.year, month.month, dayNumber);
    final ran = runDays.contains(_dayKey(day));
    final isSelected = selectedDay != null && _sameDay(selectedDay!, day);
    final isToday = _sameDay(day, today);

    final Color? fill = isSelected
        ? AppColors.ink
        : ran
        ? AppColors.accent
        : null;
    final textColor = isSelected
        ? Colors.white
        : ran
        ? AppColors.ink
        : AppColors.textBody;

    return SizedBox(
      height: 44,
      child: Center(
        child: InkResponse(
          onTap: ran ? () => onTapDay(day) : null,
          radius: 20,
          child: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fill,
              shape: BoxShape.circle,
              border: isToday && fill == null
                  ? Border.all(color: AppColors.line)
                  : null,
            ),
            child: Text(
              '$dayNumber',
              style: TextStyle(
                fontSize: 13,
                fontWeight: ran ? FontWeight.w800 : FontWeight.w500,
                color: textColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
