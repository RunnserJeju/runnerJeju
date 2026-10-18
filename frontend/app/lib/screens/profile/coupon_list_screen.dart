import 'package:flutter/material.dart';

import '../../models/coupon.dart';
import '../../models/user_log.dart';
import '../../services/service_locator.dart';
import '../../services/user_log_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/async_view.dart';
import '../../widgets/coupon_card.dart';
import 'coupon_use_screen.dart';

/// 내 쿠폰함. 마이페이지에서 들어오며, 쿠폰을 누르면 상세 시트에서 사용으로 이어진다.
class CouponListScreen extends StatefulWidget {
  const CouponListScreen({super.key});

  @override
  State<CouponListScreen> createState() => _CouponListScreenState();
}

class _CouponListScreenState extends State<CouponListScreen> {
  late Future<List<Coupon>> _future;

  @override
  void initState() {
    super.initState();
    _load();
    writeLog(LogName.couponView);
  }

  void _load() {
    _future = Services.instance.coupon.loadMyCoupons();
  }

  Future<void> _refresh() async {
    setState(_load);
    await _future.catchError((_) => <Coupon>[]);
  }

  Future<void> _openDetail(Coupon coupon) async {
    final used = await showCouponDetail(context, coupon);
    if (used != null && mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(title: const Text('내 쿠폰')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Coupon>>(
          future: _future,
          builder: (context, snapshot) => AsyncView<List<Coupon>>(
            snapshot: snapshot,
            onRetry: _refresh,
            isEmpty: (coupons) => coupons.isEmpty,
            emptyTitle: '아직 쿠폰이 없어요',
            emptyMessage: '코스를 완주하면 쿠폰을 받을 수 있어요',
            emptyIcon: Icons.confirmation_number_outlined,
            emptyActionLabel: null,
            builder: (context, coupons) {
              // 쓸 수 있는 것부터, 그다음 사용·만료.
              final available = coupons.where((c) => c.isAvailable).toList();
              final done = coupons.where((c) => !c.isAvailable).toList();
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                children: [
                  if (available.isNotEmpty) ...[
                    _Heading('사용 가능 ${available.length}'),
                    for (final coupon in available) ...[
                      CouponCard(
                        coupon: coupon,
                        onTap: () => _openDetail(coupon),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                  if (done.isNotEmpty) ...[
                    if (available.isNotEmpty) const SizedBox(height: 16),
                    const _Heading('지난 쿠폰'),
                    for (final coupon in done) ...[
                      CouponCard(
                        coupon: coupon,
                        onTap: () => _openDetail(coupon),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.textSubtle,
        ),
      ),
    );
  }
}

/// 쿠폰 상세 시트. 쓸 수 있는 쿠폰이면 "사용하기"로 업체 검색 화면을 연다.
/// 사용에 성공하면 사용된 쿠폰을 돌려주고, 아니면 null.
Future<Coupon?> showCouponDetail(BuildContext context, Coupon coupon) {
  return showModalBottomSheet<Coupon>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.paper,
    builder: (sheetContext) => _CouponDetailSheet(coupon: coupon),
  );
}

class _CouponDetailSheet extends StatelessWidget {
  const _CouponDetailSheet({required this.coupon});

  final Coupon coupon;

  Future<void> _use(BuildContext context) async {
    final used = await Navigator.of(context).push<Coupon>(
      MaterialPageRoute(builder: (_) => CouponUseScreen(coupon: coupon)),
    );
    if (used != null && context.mounted) Navigator.of(context).pop(used);
  }

  @override
  Widget build(BuildContext context) {
    final lines = <String>[
      '${Formatters.date(coupon.issuedAt)} 받음',
      if (coupon.validUntil case final until?)
        '${Formatters.dateTime(until)}까지',
      if (coupon.partnerIds == null)
        '모든 협력업체에서 쓸 수 있어요'
      else
        '정해진 협력업체에서만 쓸 수 있어요',
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CouponCard(coupon: coupon),
            if (coupon.description case final description?) ...[
              const SizedBox(height: 16),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: AppColors.textBody,
                ),
              ),
            ],
            const SizedBox(height: 14),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '· $line',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSubtle,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            if (coupon.isAvailable)
              FilledButton(
                onPressed: () => _use(context),
                child: const Text('사용하기'),
              )
            else
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  coupon.status == CouponStatus.used
                      ? '사용한 쿠폰이에요'
                      : '기간이 지난 쿠폰이에요',
                ),
              ),
          ],
        ),
      ),
    );
  }
}
