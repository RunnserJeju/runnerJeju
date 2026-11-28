import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../exceptions/app_exception.dart';
import '../../models/external_cert.dart';
import '../../models/running_course.dart';
import '../../services/service_locator.dart';
import '../../theme/app_theme.dart';
import '../../widgets/confirm_popup.dart';
import '../../widgets/course_thumbnail.dart';
import '../../widgets/linked_text.dart';
import '../profile/reward_claim_screen.dart';

/// 화면을 닫으며 부르는 쪽(러닝 탭)에 부탁하는 다음 행선지. 그냥 닫으면 null.
enum ExternalCertExit {
  /// 스탬프 탭으로.
  stamps,

  /// 러닝 탭 코스 목록으로.
  courseList,
}

/// 가민·순토 공유 링크로 코스 완주를 인증한다. 링크 입력 → 대기 → 결과가 한 화면 안에서
/// 바뀐다. 러닝 기록은 생기지 않고 스탬프·쿠폰만 지급된다(서버 external_completions).
class ExternalCertScreen extends StatefulWidget {
  const ExternalCertScreen({super.key, required this.course});

  final RunningCourse course;

  @override
  State<ExternalCertScreen> createState() => _ExternalCertScreenState();
}

// 이 화면 전용 색. 기존 팔레트에 없는 상태색(통과·보류·실패)이다.
const _ink = Color(0xFF0C0E0F);
const _sub = Color(0xFF677180);
const _card = Color(0xFFF5F6F8);
const _fieldLine = Color(0xFFD9DDE3);
const _cardLine = Color(0xFFE2E5E9);
const _green = Color(0xFF527B32);
const _greenSoft = Color(0xFFF0F6E9);
const _amber = Color(0xFF96600A);
const _amberSoft = Color(0xFFFFF3DC);
const _red = Color(0xFFB3473E);
const _redSoft = Color(0xFFFDEDEB);

const _inquiryLink = '[운영자에게 문의](https://pf.kakao.com/_xiUEbX)';

class _ExternalCertScreenState extends State<ExternalCertScreen> {
  final TextEditingController _url = TextEditingController();

  bool _verifying = false;
  ExternalCertResult? _result;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final url = _url.text.trim();
    if (url.isEmpty) {
      await _showEmptyAlert();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _verifying = true);
    try {
      final result = await Services.instance.externalCert.certify(
        courseId: widget.course.id,
        url: url,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _verifying = false;
      });
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _verifying = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _showEmptyAlert() => showConfirmPopup(
    context,
    title: '링크를 입력해 주세요',
    message: '운동 기록의 공유 링크를 입력한 뒤\n다시 인증해 주세요.',
    confirmLabel: '확인',
  );

  void _retry() => setState(() => _result = null);

  void _exit(ExternalCertExit to) => Navigator.of(context).pop(to);

  Future<void> _openInquiry() async {
    final opened = await launchUrl(
      RewardClaimScreen.channelUrl,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('카카오톡 채널을 열지 못했어요.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final title = result != null
        ? '인증 결과'
        : _verifying
        ? '스탬프 인증'
        : '외부 기록으로 스탬프 인증';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        // 결과에서는 뒤로가 아니라 닫기(X)다 — 둘 다 코스 상세로 돌아간다.
        automaticallyImplyLeading: result == null,
        title: Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (result != null)
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, size: 28),
              tooltip: '닫기',
            ),
          const SizedBox(width: 4),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.lineFaint),
        ),
      ),
      body: SafeArea(
        child: result != null
            ? _resultBody(result)
            : _verifying
            ? _verifyingBody()
            : _inputBody(),
      ),
    );
  }

  // --- 링크 입력 ------------------------------------------------------------

  Widget _inputBody() {
    return _Page(
      actions: [
        FilledButton(onPressed: _submit, child: const Text('공유 링크로 인증하기')),
      ],
      children: [
        const Text(
          '다음 코스 완주를 인증할게요',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _sub,
          ),
        ),
        const SizedBox(height: 12),
        _CourseCard(course: widget.course),
        const SizedBox(height: 32),
        const Text(
          '운동 기록 공유 링크 *',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: _ink,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'Garmin · Suunto에서 복사한 운동 공유 링크를 입력해 주세요.',
          style: TextStyle(fontSize: 13, height: 1.6, color: _sub),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          autocorrect: false,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          style: const TextStyle(fontSize: 14, color: _ink),
          decoration: InputDecoration(
            hintText: '공유 링크를 붙여 넣어주세요',
            hintStyle: const TextStyle(fontSize: 14, color: _sub),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 17,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: _fieldLine),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: _ink),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '예) https://connect.garmin.com/app/activity/~~~\n'
          '       https://maps.suunto.com/move/~~',
          style: TextStyle(fontSize: 11, height: 1.9, color: _sub),
        ),
        const SizedBox(height: 40),
        const _RuleCard(),
      ],
    );
  }

  // --- 검증 대기 ------------------------------------------------------------

  Widget _verifyingBody() {
    return _Page(
      children: [
        const SizedBox(height: 20),
        const Center(
          child: SizedBox.square(
            dimension: 80,
            child: CircularProgressIndicator(
              strokeWidth: 9,
              strokeCap: StrokeCap.round,
              color: AppColors.accent,
              backgroundColor: _greenSoft,
            ),
          ),
        ),
        const SizedBox(height: 24),
        const _Headline(
          title: '코스 경로를 비교하고 있어요',
          body: '공유 링크의 운동 기록으로\n스탬프 지급 기준을 확인해요.',
        ),
        const SizedBox(height: 20),
        _CourseCard(course: widget.course),
        const SizedBox(height: 32),
        const Text(
          '잠시만 기다려 주세요',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _ink,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          '완료되면 스탬프 지급 여부를 알려드려요.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: _sub),
        ),
      ],
    );
  }

  // --- 결과 ----------------------------------------------------------------

  Widget _resultBody(ExternalCertResult result) {
    final course = widget.course;
    switch (result.outcome) {
      case ExternalCertOutcome.granted:
        return _Page(
          actions: [
            FilledButton(
              onPressed: () => _exit(ExternalCertExit.stamps),
              child: const Text('획득한 스탬프 보기'),
            ),
          ],
          children: [
            const _StatusIcon(Icons.check_rounded, _green, _greenSoft),
            const _Headline(
              title: '코스 스탬프를 획득했어요!',
              body: '운동 기록의 GPS 경로 검증을 통과했어요.',
            ),
            const SizedBox(height: 20),
            _CourseCard(
              course: course,
              subtitle: [?result.sourceLabel, '외부 운동 기록 인증'].join(' · '),
              footer: _MatchRate(
                percent: result.matchPercent,
                note: '기준 85% 이상 충족',
                color: _green,
                valueColor: _ink,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: _greenSoft,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${course.name} 스탬프 지급 완료',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _green,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '코스별 스탬프는 계정당 1회만 지급돼요.',
                    style: TextStyle(fontSize: 12, color: _sub),
                  ),
                ],
              ),
            ),
          ],
        );

      case ExternalCertOutcome.alreadyCompleted:
        return _Page(
          actions: [
            FilledButton(
              onPressed: () => _exit(ExternalCertExit.stamps),
              child: const Text('보유한 스탬프 보기'),
            ),
          ],
          children: [
            const _StatusIcon(Icons.check_rounded, _sub, _card),
            const _Headline(title: '이미 획득한 스탬프예요'),
            const SizedBox(height: 20),
            _CourseCard(course: course),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                '이미 보유 중이라 추가 지급되지 않아요',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
            ),
          ],
        );

      case ExternalCertOutcome.activityUsed:
        return _Page(
          actions: [
            FilledButton(
              onPressed: () => _exit(ExternalCertExit.stamps),
              child: const Text('스탬프 보러가기'),
            ),
            _InquiryButton(onPressed: _openInquiry),
          ],
          children: [
            const _StatusIcon(Icons.priority_high_rounded, _amber, _amberSoft),
            const _Headline(
              title: '이미 사용된 링크예요',
              body: '이미 완주 인증에 사용된 링크라\n스탬프 지급을 보류했어요.',
            ),
            const SizedBox(height: 26),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                children: [
                  Text(
                    '기록 확인이 필요하신가요?',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    '한 번 제출한 공유 링크는 재사용할 수 없어요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, height: 1.7, color: _sub),
                  ),
                  SizedBox(height: 12),
                  LinkedText(
                    '해당 링크로 이미 스탬프를 지급받았는지 확인해 주세요.\n'
                    '추가 확인이 필요하다면 $_inquiryLink해 주세요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, height: 1.7, color: _sub),
                  ),
                ],
              ),
            ),
          ],
        );

      case ExternalCertOutcome.mismatched:
        return _Page(
          actions: [
            FilledButton(
              onPressed: () => _exit(ExternalCertExit.courseList),
              child: const Text('다른 운동 기록 제출하기'),
            ),
          ],
          children: [
            const _StatusIcon(Icons.close_rounded, _red, _redSoft),
            const _Headline(
              title: '스탬프를 지급할 수 없어요',
              body: '선택한 코스와 경로가 충분히 일치하지 않아\n이번 기록에는 스탬프가 지급되지 않아요.',
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(16),
              ),
              child: _MatchRate(
                percent: result.matchPercent,
                note: '지급 기준 85% 이상 · 기준 미달',
                color: _red,
                valueColor: _red,
              ),
            ),
            const SizedBox(height: 24),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '다른 운동 기록으로 다시 시도해 보세요',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    '선택한 코스를 달린 다른 운동 기록의\n공유 링크를 제출해 주세요.',
                    style: TextStyle(fontSize: 13, height: 1.7, color: _sub),
                  ),
                ],
              ),
            ),
          ],
        );

      case ExternalCertOutcome.unreadable:
        return _Page(
          actions: [
            FilledButton(onPressed: _retry, child: const Text('링크 다시 입력하기')),
            _InquiryButton(onPressed: _openInquiry),
          ],
          children: [
            const _StatusIcon(Icons.priority_high_rounded, _red, _redSoft),
            const _Headline(
              title: '운동 경로를 읽지 못했어요',
              body: '링크에서 운동 기록을 확인할 수 없어\n스탬프가 지급되지 않았어요.',
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '링크를 다시 확인해 주세요',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
                  ),
                  SizedBox(height: 14),
                  _Check(
                    '1. 공유할 수 있는 링크인가요?',
                    'Garmin·Suunto에서 운동 기록의 공유 링크를 복사해 주세요. '
                        '비공개이거나 접근이 제한된 링크는 확인할 수 없어요.',
                  ),
                  SizedBox(height: 14),
                  _Check('2. 달리기 기록의 링크가 맞나요?', '완료한 운동 기록의 링크를 입력해 주세요.'),
                  SizedBox(height: 14),
                  LinkedText(
                    '링크에 문제가 없는데도 기록을 불러오지 못한다면\n'
                    '$_inquiryLink해 주세요.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.85,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
    }
  }
}

/// 스크롤되는 본문과 아래에 붙는 버튼 줄. 버튼이 둘이면 나란히 놓는다.
class _Page extends StatelessWidget {
  const _Page({required this.children, this.actions = const []});

  final List<Widget> children;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            children: children,
          ),
        ),
        if (actions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Row(
              children: [
                for (final (index, action) in actions.indexed) ...[
                  if (index > 0) const SizedBox(width: 6),
                  Expanded(child: action),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _InquiryButton extends StatelessWidget {
  const _InquiryButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(side: const BorderSide(color: _ink)),
      child: const Text('운영자 문의하기'),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon(this.icon, this.color, this.background);

  final IconData icon;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 24),
      child: Center(
        child: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(color: background, shape: BoxShape.circle),
          child: Icon(icon, size: 44, color: color),
        ),
      ),
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.title, this.body});

  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            height: 1.45,
            color: _ink,
          ),
        ),
        if (body != null) ...[
          const SizedBox(height: 12),
          Text(
            body!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, height: 1.57, color: _sub),
          ),
        ],
      ],
    );
  }
}

/// 대상 코스 한 줄. [footer]를 주면 구분선 아래에 이어 붙인다(일치율).
class _CourseCard extends StatelessWidget {
  const _CourseCard({required this.course, this.subtitle, this.footer});

  final RunningCourse course;

  /// 없으면 '왕복 5km'.
  final String? subtitle;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: SizedBox.square(
                  dimension: 56,
                  child: CourseThumbnail(
                    url: course.thumbnailUrl,
                    iconSize: 24,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      course.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle ?? '왕복 ${course.distanceKmLabel}km',
                      style: const TextStyle(fontSize: 12, color: _sub),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (footer != null) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Divider(height: 1, color: _cardLine),
            ),
            footer!,
          ],
        ],
      ),
    );
  }
}

/// '코스 경로 일치율'과 큰 숫자, 그 아래 기준 안내.
class _MatchRate extends StatelessWidget {
  const _MatchRate({
    required this.percent,
    required this.note,
    required this.color,
    required this.valueColor,
  });

  final int? percent;
  final String note;
  final Color color;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '코스 경로 일치율',
                style: TextStyle(fontSize: 13, color: _sub),
              ),
              const SizedBox(height: 8),
              Text(note, style: TextStyle(fontSize: 12, color: color)),
            ],
          ),
        ),
        Text(
          percent == null ? '-' : '$percent%',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

class _RuleCard extends StatelessWidget {
  const _RuleCard();

  static const _rules = [
    '선택한 코스와 GPS 경로가 85% 이상 일치해야 해요.',
    '한 번 제출한 공유 링크는 재사용할 수 없어요.',
    '검증이 완료되면 해당 코스 스탬프가 1회에 한해 지급돼요.',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '스탬프 지급 기준',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
          const SizedBox(height: 12),
          for (final (index, rule) in _rules.indexed) ...[
            if (index > 0) const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 30,
                  child: Text(
                    '0${index + 1}',
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.7,
                      fontWeight: FontWeight.w700,
                      color: _green,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    rule,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.58,
                      color: _sub,
                    ),
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

class _Check extends StatelessWidget {
  const _Check(this.question, this.answer);

  final String question;
  final String answer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          question,
          style: const TextStyle(
            fontSize: 15,
            height: 1.6,
            fontWeight: FontWeight.w700,
            color: _ink,
          ),
        ),
        Text(
          answer,
          style: const TextStyle(fontSize: 12, height: 1.67, color: _sub),
        ),
      ],
    );
  }
}
