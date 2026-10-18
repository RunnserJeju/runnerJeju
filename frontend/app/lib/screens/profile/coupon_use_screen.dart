import 'package:flutter/material.dart';

import '../../exceptions/app_exception.dart';
import '../../models/coupon.dart';
import '../../models/course_partner.dart';
import '../../models/user_log.dart';
import '../../services/service_locator.dart';
import '../../services/user_log_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/async_view.dart';
import '../../widgets/partner_category_tile.dart';

/// 쿠폰 사용: 업체 이름을 검색해 고르고 "사용하기"를 누른다.
///
/// 업체 코드 같은 건 없다 — 유저 폰을 업체에 보여주고 업체 이름을 골라 사용 처리하면
/// 끝이다. 되돌릴 수 없으므로 확인을 한 번 거친다. 성공하면 사용된 쿠폰을 결과로 돌려준다.
class CouponUseScreen extends StatefulWidget {
  const CouponUseScreen({super.key, required this.coupon});

  final Coupon coupon;

  @override
  State<CouponUseScreen> createState() => _CouponUseScreenState();
}

class _CouponUseScreenState extends State<CouponUseScreen> {
  late Future<List<CoursePartner>> _future;
  final _query = TextEditingController();
  CoursePartner? _selected;
  bool _using = false;

  @override
  void initState() {
    super.initState();
    _load();
    _query.addListener(() => setState(() {}));
  }

  void _load() {
    _future = Services.instance.partner.loadPartners();
  }

  Future<void> _refresh() async {
    setState(_load);
    await _future.catchError((_) => <CoursePartner>[]);
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// 쿠폰에 업체 제한이 있으면 그 안에서, 검색어가 있으면 이름·주소 부분일치로.
  List<CoursePartner> _filter(List<CoursePartner> partners) {
    final q = _query.text.trim().toLowerCase();
    return [
      for (final p in partners)
        if (widget.coupon.allows(p.id) &&
            (q.isEmpty ||
                p.name.toLowerCase().contains(q) ||
                (p.address?.toLowerCase().contains(q) ?? false)))
          p,
    ];
  }

  Future<void> _use() async {
    final partner = _selected;
    if (partner == null || _using) return;

    writeLog(
      LogName.couponUseClick,
      detail: {LogKeys.partnerId: partner.id, 'coupon_id': widget.coupon.id},
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${partner.name}에서 사용할까요?'),
        content: const Text('사용 처리하면 되돌릴 수 없어요.\n업체 직원이 누르지 않으면 적용이 어렵습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('사용하기'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _using = true);
    try {
      final used = await Services.instance.coupon.useCoupon(
        widget.coupon.id,
        partnerId: partner.id,
      );
      if (!mounted) return;
      Navigator.of(context).pop(used);
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _using = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final coupon = widget.coupon;

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(title: const Text('쿠폰 사용')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  coupon.benefit,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  coupon.partnerIds == null
                      ? '사용할 협력업체를 골라 주세요'
                      : '이 쿠폰을 쓸 수 있는 업체만 보여요',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSubtle,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _query,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: '업체 이름 검색',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: _query.clear,
                          ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<CoursePartner>>(
              future: _future,
              builder: (context, snapshot) => AsyncView<List<CoursePartner>>(
                snapshot: snapshot,
                onRetry: _refresh,
                builder: (context, partners) {
                  final shown = _filter(partners);
                  if (shown.isEmpty) {
                    return const Center(
                      child: Text(
                        '검색 결과가 없어요',
                        style: TextStyle(color: AppColors.muted),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                    itemCount: shown.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final partner = shown[index];
                      return _PartnerTile(
                        partner: partner,
                        selected: _selected?.id == partner.id,
                        onTap: () => setState(() => _selected = partner),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: FilledButton(
            onPressed: _selected == null || _using ? null : _use,
            child: Text(
              _using
                  ? '처리 중…'
                  : _selected == null
                  ? '업체를 골라 주세요'
                  : '${_selected!.name}에서 사용하기',
            ),
          ),
        ),
      ),
    );
  }
}

class _PartnerTile extends StatelessWidget {
  const _PartnerTile({
    required this.partner,
    required this.selected,
    required this.onTap,
  });

  final CoursePartner partner;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.lineSoft,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              PartnerCategoryTile(category: partner.category, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      partner.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AppColors.ink,
                      ),
                    ),
                    if (partner.address case final address?) ...[
                      const SizedBox(height: 2),
                      Text(
                        address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSubtle,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle_rounded, color: AppColors.accent),
            ],
          ),
        ),
      ),
    );
  }
}
