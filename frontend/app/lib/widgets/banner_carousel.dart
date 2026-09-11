import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/notice.dart';
import '../theme/app_theme.dart';

/// 배너 가로:세로 비율. 시안(402×172)을 따른다.
const _kBannerAspectRatio = 402 / 172;

/// 홈 상단 풀블리드 이미지 배너. 스와이프로 넘기고, 4초마다 자동으로도 넘어간다.
///
/// 배너는 이미지가 있는 공지다 — 누르면 [onTap]으로 그 공지를 연다.
/// 배너 이미지는 글자까지 넣어 만든 완성본이라 그 위에 아무것도 얹지 않는다.
/// 자동 슬라이드 타이머는 [dispose]에서 반드시 취소한다.
class BannerCarousel extends StatefulWidget {
  const BannerCarousel({super.key, required this.banners, required this.onTap});

  /// 이미지가 있는 공지만 넘긴다.
  final List<Notice> banners;
  final ValueChanged<Notice> onTap;

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

  /// 새로고침으로 배너 수가 바뀌면 타이머를 다시 맞춘다. 1장→여러 장이면
  /// 이제야 자동 슬라이드가 켜지고, 줄어들면 현재 페이지가 범위를 벗어나지 않게 한다.
  @override
  void didUpdateWidget(covariant BannerCarousel old) {
    super.didUpdateWidget(old);
    if (old.banners.length == widget.banners.length) return;
    _timer?.cancel();
    _timer = null;
    if (_page >= widget.banners.length) _page = 0;
    _startAutoSlide();
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

    return AspectRatio(
      aspectRatio: _kBannerAspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: banners.length,
            onPageChanged: (page) => setState(() => _page = page),
            itemBuilder: (context, index) {
              final notice = banners[index];
              return GestureDetector(
                onTap: () => widget.onTap(notice),
                child: CachedNetworkImage(
                  imageUrl: notice.imageUrl!,
                  fit: BoxFit.cover,
                  placeholder: (_, _) =>
                      const ColoredBox(color: AppColors.inkSoft),
                  errorWidget: (_, _, _) =>
                      const ColoredBox(color: AppColors.inkSoft),
                ),
              );
            },
          ),
          if (banners.length > 1)
            Positioned(
              right: 16,
              bottom: 12,
              child: Row(
                children: [
                  for (var i = 0; i < banners.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(left: 5),
                      width: i == _page ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == _page
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(999),
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

/// 등록된 배너가 하나도 없을 때 상단에 대신 보여주는 브랜드 히어로.
///
/// 배너를 접어버리면 홈 첫 화면이 허전해서, 사진 대신 앱 캐치프레이즈를 얹은
/// 어두운 카드를 항상 한 장은 띄운다. 배너와 같은 비율.
class BrandHeroBanner extends StatelessWidget {
  const BrandHeroBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return const AspectRatio(
      aspectRatio: _kBannerAspectRatio,
      child: _BannerSlide(
        image: ColoredBox(color: AppColors.ink),
        eyebrow: 'RUNNERS JEJU',
        title: '제주를 달리는 가장 좋은 방법',
        subtitle: '코스를 고르고, 달리고, 스탬프를 모아보세요',
      ),
    );
  }
}

/// 브랜드 히어로 한 장: 배경 + 어두운 그라디언트 + 좌하단 텍스트.
class _BannerSlide extends StatelessWidget {
  const _BannerSlide({
    required this.image,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });

  final Widget image;
  final String eyebrow;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        image,
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x66000000), Color(0x80000000), Color(0x99000000)],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                eyebrow.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.9,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.66,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 13,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
