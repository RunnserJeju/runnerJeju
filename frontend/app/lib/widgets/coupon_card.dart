import 'package:flutter/material.dart';

import '../models/coupon.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

/// 쿠폰 한 장. 왼쪽에 혜택을 크게, 오른쪽에 절취선 너머 상태를 둔 티켓 모양이다.
///
/// 쿠폰 목록·상세·획득 팝업이 같이 쓴다. 사용했거나 만료된 쿠폰은 흐리게 그린다.
class CouponCard extends StatelessWidget {
  const CouponCard({super.key, required this.coupon, this.onTap});

  final Coupon coupon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final active = coupon.isAvailable;
    final tint = active ? AppColors.accent : AppColors.surfaceMuted;

    return Opacity(
      opacity: active ? 1 : 0.55,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        child: InkWell(
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.lineSoft),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            coupon.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSubtle,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            coupon.benefit,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _footnote,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textFaint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const _Perforation(),
                  Container(
                    width: 84,
                    color: tint.withValues(alpha: active ? 0.18 : 0.6),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          active
                              ? Icons.confirmation_number_rounded
                              : Icons.check_circle_rounded,
                          color: active ? AppColors.accent : AppColors.muted,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          coupon.isReward && coupon.status == CouponStatus.used
                              ? '지급 완료'
                              : coupon.status.label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: active ? AppColors.ink : AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String get _footnote {
    switch (coupon.status) {
      case CouponStatus.used:
        final where = coupon.usedPartnerName;
        final when = coupon.usedAt == null
            ? ''
            : Formatters.date(coupon.usedAt!);
        if (coupon.isReward) return '$when 경품 지급';
        return where == null ? '$when 사용' : '$when · $where에서 사용';
      case CouponStatus.expired:
        return coupon.validUntil == null
            ? '기간이 지났어요'
            : '${Formatters.date(coupon.validUntil!)}까지였어요';
      case CouponStatus.available:
        if (coupon.validUntil == null) return '기한 없음';
        final until = Formatters.date(coupon.validUntil!);
        return coupon.isReward ? '$until까지 수령' : '$until까지';
    }
  }
}

/// 티켓 절취선. 위아래 반원 홈과 점선.
class _Perforation extends StatelessWidget {
  const _Perforation();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 12,
      child: CustomPaint(painter: _PerforationPainter()),
    );
  }
}

class _PerforationPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    final dash = Paint()
      ..color = AppColors.line
      ..strokeWidth = 1;
    for (double y = 10; y < size.height - 10; y += 6) {
      canvas.drawLine(Offset(x, y), Offset(x, y + 3), dash);
    }
    final notch = Paint()..color = AppColors.paper;
    canvas.drawCircle(Offset(x, 0), 7, notch);
    canvas.drawCircle(Offset(x, size.height), 7, notch);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
