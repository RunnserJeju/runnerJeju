import 'package:flutter/material.dart';

import '../../models/run_record.dart';
import '../../services/run_submission.dart';
import '../../services/service_locator.dart';
import '../../theme/app_theme.dart';
import '../../utils/continuation_window.dart';
import '../../utils/formatters.dart';
import '../../widgets/async_view.dart';
import '../../widgets/section_title.dart';
import 'run_record_tile.dart';

/// 이어 달리기를 고른 기록을 받는다. 확인 시트를 거친 뒤에만 불린다.
typedef ContinueRun = void Function(RunRecord record);

/// 마이페이지의 "미완주 기록": 최근 7일 안에 시작해 아직 완주하지 못한 코스 러닝.
/// 최근 [_previewCount]개만 보이고, 더 있으면 "더보기"로 전체(7일치)를 연다.
/// 이어 달릴 기록이 없어도 섹션은 두고 "이어 달릴 기록이 없어요"를 보여준다.
class IncompleteRunsSection extends StatefulWidget {
  const IncompleteRunsSection({super.key, required this.onContinue});

  final ContinueRun onContinue;

  @override
  State<IncompleteRunsSection> createState() => _IncompleteRunsSectionState();
}

class _IncompleteRunsSectionState extends State<IncompleteRunsSection> {
  static const int _previewCount = 5;

  // 하나 더 받아 "더보기"를 띄울지 정한다. 전체 개수를 따로 묻지 않는다.
  late Future<List<RunRecord>> _future = _load();

  static Future<List<RunRecord>> _load() => Services.instance.run
      .loadContinuableRecords(limit: _previewCount + 1);

  void _reload() => setState(() => _future = _load());

  // 러닝이 저장되거나 검증이 끝나면 목록이 바뀐다(새 미완주 기록, 이어 달려 완주한 기록).
  // 마이페이지는 탭으로 살아 있어 돌아와도 다시 만들어지지 않으므로 직접 다시 받는다.
  RunSubmission get _submission => Services.instance.runSubmission;
  Object? _seenUpload;
  Object? _seenVerification;

  @override
  void initState() {
    super.initState();
    _seenUpload = _submission.uploadResult;
    _seenVerification = _submission.verification;
    _submission.addListener(_onSubmissionChanged);
  }

  @override
  void dispose() {
    _submission.removeListener(_onSubmissionChanged);
    super.dispose();
  }

  void _onSubmissionChanged() {
    final upload = _submission.uploadResult;
    final verification = _submission.verification;
    if (identical(upload, _seenUpload) &&
        identical(verification, _seenVerification)) {
      return;
    }
    _seenUpload = upload;
    _seenVerification = verification;
    if (mounted && upload != null) _reload();
  }

  Future<void> _openAll() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => IncompleteRunsScreen(onContinue: widget.onContinue),
      ),
    );
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<RunRecord>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _Frame(
            children: [
              Card(
                child: ListTile(
                  title: const Text(
                    '미완주 기록을 불러오지 못했어요',
                    style: TextStyle(fontSize: 14, color: AppColors.textSubtle),
                  ),
                  trailing: TextButton(
                    onPressed: _reload,
                    child: const Text('다시 시도'),
                  ),
                ),
              ),
            ],
          );
        }

        // 받는 중에도 빈 상태와 같은 높이의 카드로 자리를 잡아 둔다. 그래야 받은 뒤
        // 아래 메뉴가 밀려 내려가지 않는다.
        if (snapshot.connectionState != ConnectionState.done) {
          return const _Frame(
            children: [
              _NoticeCard(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ],
          );
        }

        final runs = snapshot.data ?? const <RunRecord>[];
        if (runs.isEmpty) {
          return const _Frame(
            children: [
              _NoticeCard(
                child: Text(
                  '이어 달릴 기록이 없어요',
                  style: TextStyle(fontSize: 14, color: AppColors.textSubtle),
                ),
              ),
            ],
          );
        }

        return _Frame(
          onMore: runs.length > _previewCount ? _openAll : null,
          children: [
            for (final record in runs.take(_previewCount)) ...[
              IncompleteRunTile(record: record, onContinue: widget.onContinue),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }
}

/// 목록 자리에 들어가는 한 줄짜리 카드(불러오는 중·비어 있음).
class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SizedBox(
        height: 64,
        child: Center(child: child),
      ),
    );
  }
}

/// 섹션 제목 + 안내 + 내용. 마이페이지 목록 사이에 끼므로 위 간격도 여기서 잡는다.
class _Frame extends StatelessWidget {
  const _Frame({required this.children, this.onMore});

  final List<Widget> children;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: SectionTitle('미완주 기록')),
              if (onMore != null)
                TextButton(
                  onPressed: onMore,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSubtle,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('더보기'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '최근 7일 안에 시작한 기록은 이어 달려서 완주할 수 있어요',
            style: TextStyle(fontSize: 12, color: AppColors.textSubtle),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

/// "더보기": 이어 달릴 수 있는 미완주 기록 전체(최근 7일).
class IncompleteRunsScreen extends StatefulWidget {
  const IncompleteRunsScreen({super.key, required this.onContinue});

  final ContinueRun onContinue;

  @override
  State<IncompleteRunsScreen> createState() => _IncompleteRunsScreenState();
}

class _IncompleteRunsScreenState extends State<IncompleteRunsScreen> {
  /// 7일치라 서버 상한(100)이면 충분하다.
  static const int _limit = 100;

  late Future<List<RunRecord>> _future = _load();

  static Future<List<RunRecord>> _load() =>
      Services.instance.run.loadContinuableRecords(limit: _limit);

  Future<void> _refresh() async {
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(title: const Text('미완주 기록')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<RunRecord>>(
          future: _future,
          builder: (context, snapshot) => AsyncView<List<RunRecord>>(
            snapshot: snapshot,
            onRetry: _refresh,
            isEmpty: (runs) => runs.isEmpty,
            emptyTitle: '이어 달릴 기록이 없어요',
            emptyMessage: '최근 7일 안에 시작한 미완주 기록이 여기에 나와요',
            emptyIcon: Icons.directions_run_rounded,
            builder: (context, runs) => ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              itemCount: runs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) => IncompleteRunTile(
                record: runs[index],
                onContinue: widget.onContinue,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 미완주 기록 한 장: 코스·날짜·거리, 코스 진행률, 남은 기한, "이어 달리기" 버튼.
/// 카드를 누르면 상세, 버튼을 누르면 확인 시트를 거쳐 [onContinue].
class IncompleteRunTile extends StatelessWidget {
  const IncompleteRunTile({
    super.key,
    required this.record,
    required this.onContinue,
  });

  final RunRecord record;
  final ContinueRun onContinue;

  Future<void> _continue(BuildContext context) async {
    final confirmed = await showContinueRunSheet(context, record);
    if (confirmed) onContinue(record);
  }

  @override
  Widget build(BuildContext context) {
    final rate = record.matchRate?.clamp(0.0, 1.0);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openRunDetail(context, record),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          record.courseName ?? '코스',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${Formatters.dateTime(record.startedAt)} · '
                          '${Formatters.distanceKm(record.distanceMeters)}km',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSubtle,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => _continue(context),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: const Text('이어 달리기'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Row(
                  children: [
                    Text(
                      rate == null
                          ? '코스 진행률 없음'
                          : '코스 ${(rate * 100).round()}% 달림',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textBody,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _deadlineLabel(record.startedAt),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSubtle,
                      ),
                    ),
                  ],
                ),
              ),
              if (rate != null) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: LinearProgressIndicator(
                    value: rate,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                    color: AppColors.accent,
                    backgroundColor: AppColors.lineFaint,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 이어 달리기 전 확인. 시작을 고르면 true.
Future<bool> showContinueRunSheet(BuildContext context, RunRecord record) async {
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.paper,
    builder: (_) => _ContinueRunSheet(record: record),
  );
  return confirmed ?? false;
}

class _ContinueRunSheet extends StatelessWidget {
  const _ContinueRunSheet({required this.record});

  final RunRecord record;

  @override
  Widget build(BuildContext context) {
    final rate = record.matchRate;
    final lines = <String>[
      '${Formatters.distanceKm(record.distanceMeters)}km'
          '${rate == null ? '' : ' · 코스 ${(rate * 100).round()}%'}'
          '까지 달린 기록에 이어서 기록돼요',
      '이어 달린 구간과 합쳐져 하나의 기록이 되고, 다시 나눌 수 없어요',
      '이 기록은 ${_deadlineLabel(record.startedAt, sentence: true)}',
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionTitle('이어 달리기'),
            const SizedBox(height: 6),
            Text(
              '${record.courseName ?? '코스'} · '
              '${Formatters.dateTime(record.startedAt)}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textBody,
              ),
            ),
            const SizedBox(height: 14),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '· $line',
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: AppColors.textSubtle,
                  ),
                ),
              ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('이어 달리기 시작'),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(foregroundColor: AppColors.textSubtle),
              child: const Text('취소'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 이어 달릴 수 있는 남은 날([ContinuationWindow]).
String _deadlineLabel(DateTime startedAt, {bool sentence = false}) {
  final lastDay = ContinuationWindow.lastDay(startedAt);
  final daysLeft = ContinuationWindow.daysLeft(startedAt);

  if (daysLeft <= 0) {
    return sentence ? '오늘까지 이어 달릴 수 있어요' : '오늘까지';
  }
  return sentence
      ? '${lastDay.month}월 ${lastDay.day}일까지 이어 달릴 수 있어요'
      : '$daysLeft일 남음';
}
