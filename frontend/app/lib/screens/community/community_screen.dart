import 'package:flutter/material.dart';

import '../../models/running_program.dart';
import '../../services/service_locator.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/async_view.dart';

/// 커뮤니티 탭. 지금은 러닝 프로그램 섹션만 있고 목록은 비어 있다.
class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  late Future<List<RunningProgram>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = Services.instance.program.loadPrograms();
  }

  Future<void> _refresh() async {
    setState(_load);
    await _future.catchError((_) => <RunningProgram>[]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('커뮤니티')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<RunningProgram>>(
          future: _future,
          builder: (context, snapshot) => AsyncView<List<RunningProgram>>(
            snapshot: snapshot,
            onRetry: _refresh,
            isEmpty: (programs) => programs.isEmpty,
            emptyTitle: '아직 열린 러닝 프로그램이 없어요',
            emptyMessage: '곧 다양한 프로그램이 열릴 예정이에요',
            emptyIcon: Icons.groups_rounded,
            builder: (context, programs) => _ProgramList(programs: programs),
          ),
        ),
      ),
    );
  }
}

class _ProgramList extends StatelessWidget {
  const _ProgramList({required this.programs});

  final List<RunningProgram> programs;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
          sliver: SliverToBoxAdapter(child: _SectionTitle('러닝 프로그램')),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
          sliver: SliverList.separated(
            itemCount: programs.length,
            itemBuilder: (context, index) =>
                _ProgramCard(program: programs[index]),
            separatorBuilder: (_, _) => const SizedBox(height: 12),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        color: AppColors.ink,
      ),
    );
  }
}

class _ProgramCard extends StatelessWidget {
  const _ProgramCard({required this.program});

  final RunningProgram program;

  /// 상시 모집이면 null이라 기간 줄을 아예 감춘다.
  String? get _period {
    final start = program.startDate;
    final end = program.endDate;
    if (start == null && end == null) return null;
    if (start != null && end != null) {
      return '${Formatters.date(start)} ~ ${Formatters.date(end)}';
    }
    return Formatters.date((start ?? end)!);
  }

  @override
  Widget build(BuildContext context) {
    final period = _period;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            program.title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: AppColors.ink,
            ),
          ),
          if (program.description != null) ...[
            const SizedBox(height: 6),
            Text(
              program.description!,
              style: const TextStyle(fontSize: 13, color: AppColors.inkSoft),
            ),
          ],
          if (period != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.event_rounded,
                  size: 15,
                  color: AppColors.accent,
                ),
                const SizedBox(width: 6),
                Text(
                  period,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkSoft,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
