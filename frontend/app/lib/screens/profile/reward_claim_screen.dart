import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/coupon.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/coupon_card.dart';

/// 경품 쿠폰 수령 안내. 앱에서 사용 처리하지 않는다 — 카카오톡 채널 '제주러닝위크'에
/// 이 화면 캡처를 보내면 운영자가 코드로 찾아 지급완료 처리하고, 그러면 쿠폰함에서
/// 사용완료로 보인다. 캡처 한 장에 코드·경품·닉네임 대신 쓸 식별 정보가 다 들어가게 짠다.
class RewardClaimScreen extends StatelessWidget {
  const RewardClaimScreen({super.key, required this.coupon});

  final Coupon coupon;

  /// 카카오톡 채널 '제주러닝위크'. 카카오톡이 깔려 있으면 앱으로, 아니면 웹으로 열린다.
  static final Uri channelUrl = Uri.parse('https://pf.kakao.com/_xiUEbX');
  static const String channelName = '제주러닝위크';

  Future<void> _openChannel(BuildContext context) async {
    final opened = await launchUrl(
      channelUrl,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('카카오톡 채널을 열지 못했어요.')));
    }
  }

  Future<void> _copyCode(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: coupon.code));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('쿠폰 코드를 복사했어요.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = coupon.isAvailable;
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(title: const Text('경품 받기')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            CouponCard(coupon: coupon),
            const SizedBox(height: 16),
            _CodeBox(
              code: coupon.code,
              onCopy: available ? () => _copyCode(context) : null,
            ),
            const SizedBox(height: 20),
            const _Steps(),
            const SizedBox(height: 16),
            _Line('${Formatters.date(coupon.issuedAt)} 당첨'),
            if (coupon.validUntil case final until?)
              _Line('${Formatters.dateTime(until)}까지 받을 수 있어요'),
            if (coupon.usedAt case final usedAt?)
              _Line('${Formatters.dateTime(usedAt)} 지급 완료'),
            const SizedBox(height: 24),
            if (available)
              FilledButton.icon(
                onPressed: () => _openChannel(context),
                icon: const Icon(Icons.chat_bubble_rounded, size: 18),
                label: const Text('카카오톡 채널 $channelName 열기'),
              )
            else
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  coupon.status == CouponStatus.used
                      ? '지급이 완료된 경품이에요'
                      : '수령 기한이 지난 경품이에요',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 운영자가 캡처에서 찾는 코드. 크고 자간 넓게.
class _CodeBox extends StatelessWidget {
  const _CodeBox({required this.code, required this.onCopy});

  final String code;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.lineSoft),
      ),
      padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '쿠폰 코드',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSubtle,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  code,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    color: AppColors.ink,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onCopy,
            icon: const Icon(Icons.copy_rounded),
            color: AppColors.iconSubtle,
            tooltip: '복사',
          ),
        ],
      ),
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps();

  static const _steps = [
    '아래 버튼으로 카카오톡 채널 ${RewardClaimScreen.channelName}을 열고 친구 추가해요.',
    '1:1 채팅에 이 화면을 캡처해서 보내요. 쿠폰 코드가 보여야 해요.',
    '운영자가 확인하면 경품을 안내하고 지급 완료로 바꿔요. 쿠폰함에서 지급 완료로 보여요.',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '받는 방법',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < _steps.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == _steps.length - 1 ? 0 : 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _steps[i],
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: AppColors.textBody,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        '· $text',
        style: const TextStyle(fontSize: 12, color: AppColors.textSubtle),
      ),
    );
  }
}
