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
import 'reward_claim_screen.dart';

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

  /// 사용했거나 만료로 판명나면 목록을 다시 받는다 — 둘 다 서버 목록이 달라진다.
  /// 경품 쿠폰은 앱에서 사용 처리하지 않으므로 수령 안내 화면으로 바로 간다.
  Future<void> _openDetail(Coupon coupon) async {
    if (coupon.isReward) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => RewardClaimScreen(coupon: coupon)),
      );
      if (mounted) _refresh();
      return;
    }
    final changed = await showCouponDetail(context, coupon);
    if (changed != null && mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.paper,
        appBar: AppBar(title: const Text('내 쿠폰')),
        body: FutureBuilder<List<Coupon>>(
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
              // 사용 가능 / 사용 완료 탭. 만료는 서버가 목록에서 뺀다.
              final available = coupons.where((c) => c.isAvailable).toList();
              final done = coupons.where((c) => !c.isAvailable).toList();
              return Column(
                children: [
                  TabBar(
                    labelColor: AppColors.ink,
                    unselectedLabelColor: AppColors.muted,
                    labelStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                    indicatorColor: AppColors.ink,
                    indicatorWeight: 2,
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: AppColors.lineSoft,
                    tabs: [
                      Tab(text: '사용 가능 ${available.length}'),
                      Tab(text: '사용 완료 ${done.length}'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _CouponList(
                          coupons: available,
                          emptyText: '사용할 수 있는 쿠폰이 없어요',
                          onRefresh: _refresh,
                          onTap: _openDetail,
                        ),
                        _CouponList(
                          coupons: done,
                          emptyText: '사용 완료한 쿠폰이 없어요',
                          onRefresh: _refresh,
                          onTap: _openDetail,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 탭 하나의 목록. 비어도 당겨서 새로고침이 되도록 스크롤 가능한 빈 화면을 둔다.
class _CouponList extends StatelessWidget {
  const _CouponList({
    required this.coupons,
    required this.emptyText,
    required this.onRefresh,
    required this.onTap,
  });

  final List<Coupon> coupons;
  final String emptyText;
  final Future<void> Function() onRefresh;
  final void Function(Coupon coupon) onTap;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: coupons.isEmpty
          ? ListView(
              padding: const EdgeInsets.only(top: 80),
              children: [
                Center(
                  child: Text(
                    emptyText,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textSubtle,
                    ),
                  ),
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
              itemCount: coupons.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final coupon = coupons[index];
                return CouponCard(coupon: coupon, onTap: () => onTap(coupon));
              },
            ),
    );
  }
}

/// 쿠폰 상세 시트. 쓸 수 있는 쿠폰이면 "사용하기"로 업체 검색 화면을 연다.
/// 사용했거나 만료로 판명나면 그 쿠폰을 돌려주고, 아니면 null.
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
    final changed = await Navigator.of(context).push<Coupon>(
      MaterialPageRoute(builder: (_) => CouponUseScreen(coupon: coupon)),
    );
    if (changed != null && context.mounted) Navigator.of(context).pop(changed);
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
