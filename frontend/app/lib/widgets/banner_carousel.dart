import 'dart:async';

import 'package:flutter/material.dart';

import '../models/home_banner.dart';
import '../theme/app_theme.dart';

/// 홈 화면 상단 이미지 배너. 스와이프로 넘기고, 4초마다 자동으로도 넘어간다.
///
/// 배너 사진 품질이 들쭉날쭉해서 이미지 위에 하단 그라디언트(scrim)를 덮어 톤을
/// 잡아준다. 자동 슬라이드 타이머는 [dispose]에서 반드시 취소한다.
class BannerCarousel extends StatefulWidget {
  const BannerCarousel({super.key, required this.banners});

  final List<HomeBanner> banners;

  @override
  State<BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<BannerCarousel> {
  final _controller = PageController();
  Timer? _timer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _startAutoSlide();
  }

  void _startAutoSlide() {
    if (widget.banners.length <= 1) return;
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_controller.hasClients) return;
      final next = (_page + 1) % widget.banners.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final banners = widget.banners;

    return Column(
      children: [
        AspectRatio(
          // 가로로 길고 세로로 짧은 스트립 배너. 사진은 이 비율에 맞춰 넣는다.
          aspectRatio: 3 / 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: AppColors.ink.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PageView.builder(
                    controller: _controller,
                    itemCount: banners.length,
                    onPageChanged: (page) => setState(() => _page = page),
                    itemBuilder: (context, index) => Image.network(
                      banners[index].imageUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (_, _, _) => const _BannerFallback(),
                    ),
                  ),
                  // 사진 위에 얹는 하단 그라디언트 — 저품질 사진도 톤이 잡히고,
                  // 인디케이터가 밝은 사진 위에서도 보이게 한다.
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            AppColors.ink.withValues(alpha: 0.35),
                          ],
                          stops: const [0.55, 1.0],
                        ),
                      ),
                    ),
                  ),
                  if (banners.length > 1)
                    Positioned(
                      right: 14,
                      bottom: 12,
                      child: Row(
                        children: [
                          for (var i = 0; i < banners.length; i++)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              width: i == _page ? 18 : 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: i == _page
                                    ? AppColors.accent
                                    : Colors.white.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(999),
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
      ],
    );
  }
}

class _BannerFallback extends StatelessWidget {
  const _BannerFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.ink.withValues(alpha: 0.06),
      alignment: Alignment.center,
      child: Icon(
        Icons.image_not_supported_outlined,
        color: AppColors.ink.withValues(alpha: 0.3),
      ),
    );
  }
}

/// 등록된 배너가 하나도 없을 때 상단에 대신 보여주는 브랜드 히어로.
///
/// 배너를 접어버리면 홈 첫 화면이 허전해서, 사진 대신 앱 캐치프레이즈를 얹은
/// 라이트 미니멀 카드를 항상 한 장은 띄운다. 배너와 같은 가로 스트립 비율.
class BrandHeroBanner extends StatelessWidget {
  const BrandHeroBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 3 / 1,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFECEEF2)),
          boxShadow: [
            BoxShadow(
              color: AppColors.ink.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -8,
              bottom: -12,
              child: Icon(
                Icons.directions_run_rounded,
                size: 120,
                color: AppColors.ink.withValues(alpha: 0.04),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppColors.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'RUNNERS JEJU',
                        style: TextStyle(
                          color: Color(0xFF9AA0AC),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '제주를 달리는 가장 좋은 방법',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.ink,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
