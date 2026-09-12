import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_theme.dart';
import 'community/community_screen.dart';
import 'home/home_screen.dart';
import 'profile/profile_screen.dart';
import 'running/running_screen.dart';
import 'stamp/stamp_screen.dart';

/// 하단 탭으로 구성된 앱 뼈대.
///
/// 예전에는 탭 사이에 러닝 시작 FAB가 하나 더 떠 있었다. 러닝은 '러닝'
/// 탭([RunningScreen])이 지도째로 맡는다 — 코스를 고르는 것도, 코스 없이 바로
/// 달리는 것도 그 안에서 끝나므로 버튼을 따로 띄울 이유가 없다.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _runningTab = 2;

  static const _items = <({IconData? icon, String? asset, String label})>[
    (icon: Icons.home, asset: null, label: '홈'),
    (icon: Icons.groups, asset: null, label: '커뮤니티'),
    (icon: null, asset: 'assets/icons/nav_run.svg', label: '러닝'),
    (icon: Icons.star, asset: null, label: '스탬프'),
    (icon: Icons.person, asset: null, label: '마이페이지'),
  ];

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[
      HomeScreen(onShowMap: () => setState(() => _index = _runningTab)),
      const CommunityScreen(),
      const RunningScreen(),
      const StampScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      // 탭 안에 지도(카카오맵 PlatformView)를 쓰는 화면이 있다(RunningScreen).
      // 이 바깥 Scaffold가 키보드에 맞춰 body를 리사이즈하면 그 안의
      // IndexedStack 전체가 줄어들면서 지도가 함께 리사이즈돼 렌더링이
      // 깨진다. 리사이즈 대신 키보드가 위에 그냥 덮이게 둔다.
      resizeToAvoidBottomInset: false,
      body: IndexedStack(index: _index, children: tabs),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.lineSoft)),
        ),
        child: BottomAppBar(
          color: Colors.transparent,
          elevation: 0,
          height: 68,
          padding: EdgeInsets.zero,
          child: Row(
            children: [
              for (final (index, item) in _items.indexed)
                Expanded(
                  child: _NavItem(
                    icon: item.icon,
                    asset: item.asset,
                    label: item.label,
                    selected: _index == index,
                    onTap: () => setState(() => _index = index),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.asset,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  /// 머티리얼 아이콘 또는 SVG 에셋 중 하나만 쓴다.
  final IconData? icon;
  final String? asset;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accent : AppColors.muted;

    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (asset case final asset?)
            SvgPicture.asset(
              asset,
              width: 22,
              height: 22,
              colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
            )
          else
            Icon(icon, color: color, size: 22),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
