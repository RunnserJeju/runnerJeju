import 'package:flutter/material.dart';

import '../models/coupon.dart';
import '../theme/app_theme.dart';
import '../widgets/coupon_celebration.dart';

/// 쿠폰 획득 팝업 미리보기. 서버·로그인 없이 연출만 본다.
///
///   flutter run -t lib/dev/coupon_celebration_preview.dart
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
  final _coupon = Coupon(
    id: 'preview',
    name: '코스 완주 쿠폰',
    benefit: '아메리카노 1잔 무료',
    issuedAt: DateTime.now(),
    status: CouponStatus.available,
    validUntil: DateTime.now().add(const Duration(days: 30)),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _show());
  }

  void _show() => showCouponCelebration(context, _coupon);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('쿠폰 팝업 미리보기')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: FilledButton(onPressed: _show, child: const Text('다시 보기')),
        ),
      ),
    );
  }
}
