import 'package:flutter/material.dart';

import '../models/coupon.dart';
import '../models/run_stamp.dart';
import '../theme/app_theme.dart';
import '../widgets/coupon_celebration.dart';
import '../widgets/stamp_celebration.dart';

/// 러닝위크 참가자가 코스를 처음 완주했을 때의 팝업 연속 미리보기. 서버·로그인 없이 연출만 본다.
/// 순서는 결과 화면(run_result_screen)과 같다: 코스 스탬프 → 코스 쿠폰 → 러닝위크 코스 스탬프.
///
///   flutter run -t lib/dev/run_rewards_preview.dart
void main() => runApp(
  MaterialApp(
    theme: AppTheme.light,
    debugShowCheckedModeBanner: false,
    home: const _Preview(),
  ),
);

class _Preview extends StatefulWidget {
  const _Preview();

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  final _courseStamp = RunStamp(
    id: 'course',
    definitionId: 'course',
    name: '댕댕런',
    acquiredAt: DateTime.now(),
  );
  final _coupon = Coupon(
    id: 'coupon',
    name: '코스 완주 쿠폰',
    benefit: '아메리카노 1잔 무료',
    issuedAt: DateTime.now(),
    status: CouponStatus.available,
    validUntil: DateTime.now().add(const Duration(days: 30)),
  );
  final _weekStamp = RunStamp(
    id: 'week',
    definitionId: 'week',
    name: '[러닝위크] 댕댕런',
    acquiredAt: DateTime.now(),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _show());
  }

  Future<void> _show() async {
    await showStampCelebration(context, _courseStamp);
    if (!mounted) return;
    await showCouponCelebration(context, _coupon);
    if (!mounted) return;
    await showStampCelebration(context, _weekStamp);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('완주 보상 팝업 미리보기')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '코스 스탬프 → 코스 쿠폰 → 러닝위크 코스 스탬프\n각 팝업을 닫으면 다음 팝업이 떠요.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: FilledButton(onPressed: _show, child: const Text('다시 보기')),
        ),
      ),
    );
  }
}
