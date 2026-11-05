import 'package:flutter/material.dart';

import '../../exceptions/app_exception.dart';
import '../../models/coupon.dart';
import '../../models/course_partner.dart';
import '../../models/user_log.dart';
import '../../services/coupon_service.dart';
import '../../services/service_locator.dart';
import '../../services/user_log_service.dart';
import '../../theme/app_theme.dart';

/// 쿠폰 사용: 업체 직원이 업체 고유 번호 4자리를 입력하고 "사용하기"를 누른다.
///
/// 번호로 서버가 업체를 찾으므로 업체를 따로 고르지 않는다. 성공하면 사용된 쿠폰을,
/// 서버가 만료라고 하면 만료 상태의 쿠폰을 결과로 돌려준다 — 둘 다 목록에서 빠질 쿠폰이다.
class CouponUseScreen extends StatefulWidget {
  const CouponUseScreen({super.key, required this.coupon});

  final Coupon coupon;

  @override
  State<CouponUseScreen> createState() => _CouponUseScreenState();
}

class _CouponUseScreenState extends State<CouponUseScreen> {
  static const _pinLength = 4;

  final _pin = TextEditingController();
  bool _using = false;

  /// 업체 제한이 있는 쿠폰만 쓸 수 있는 업체 이름을 불러온다.
  Future<List<CoursePartner>>? _allowedPartners;

  @override
  void initState() {
    super.initState();
    _pin.addListener(() => setState(() {}));
    if (widget.coupon.partnerIds != null) {
      _allowedPartners = Services.instance.partner.loadPartners().then(
        (partners) => [
          for (final p in partners)
            if (widget.coupon.allows(p.id)) p,
        ],
      );
    }
  }

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  bool get _ready => _pin.text.length == _pinLength && !_using;

  Future<void> _use() async {
    if (!_ready) return;

    writeLog(LogName.couponUseClick, detail: {'coupon_id': widget.coupon.id});

    setState(() => _using = true);
    try {
      final used = await Services.instance.coupon.useCoupon(
        widget.coupon.id,
        pin: _pin.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(used);
    } on CouponExpiredException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
      Navigator.of(context).pop(widget.coupon.asExpired());
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _using = false);
      _pin.clear();
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
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
          const Text(
            '업체 직원에게 화면을 보여주고 쿠폰 번호 4자리를 입력받아 주세요.\n사용 처리하면 되돌릴 수 없어요.',
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: AppColors.textSubtle,
            ),
          ),
          if (_allowedPartners case final allowed?)
            FutureBuilder<List<CoursePartner>>(
              future: allowed,
              builder: (context, snapshot) {
                final names = snapshot.data?.map((p) => p.name).join(', ');
                if (names == null || names.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '사용 가능 업체: $names',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: 28),
          // 입력 버튼은 입력칸 옆에 둔다. 하단 바에 두면 키보드에 가려진다.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 180,
                child: TextField(
                  controller: _pin,
                  autofocus: true,
                  enabled: !_using,
                  obscureText: true,
                  // 기본 문자 키보드 — 완료 키가 있어 iOS에서도 키보드를 내릴 수 있다.
                  textInputAction: TextInputAction.done,
                  textAlign: TextAlign.center,
                  maxLength: _pinLength,
                  onSubmitted: (_) => _use(),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 16,
                    color: AppColors.ink,
                  ),
                  decoration: const InputDecoration(
                    hintText: '••••',
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _ready ? _use : null,
                // 테마 기본은 가로 무한(전체 폭)이라 Row 안에서는 폭을 정해 줘야 한다.
                style: FilledButton.styleFrom(
                  minimumSize: const Size(88, 54),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                ),
                child: Text(_using ? '처리 중' : '입력'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _pin.text.length < _pinLength ? '쿠폰 번호 4자리를 입력해 주세요' : '',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppColors.textSubtle),
          ),
        ],
      ),
    );
  }
}
