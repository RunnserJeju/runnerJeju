import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'home/home_screen.dart';
import 'profile/profile_screen.dart';
import 'running/running_screen.dart';
import 'stamp/stamp_screen.dart';

/// 하단 탭 4개로 구성된 앱 뼈대.
///
/// 예전에는 탭 넷 사이에 러닝 시작 FAB가 하나 더 떠 있어 진입점이 다섯이었다.
/// 러닝은 '러닝' 탭([RunningScreen])이 지도째로 맡는다 — 코스를 고르는 것도,
/// 코스 없이 바로 달리는 것도 그 안에서 끝나므로 버튼을 따로 띄울 이유가 없다.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _tabs = <Widget>[
    HomeScreen(),
    RunningScreen(),
    StampScreen(),
    ProfileScreen(),
  ];

  static const _items = <({IconData icon, String label})>[
    (icon: Icons.home_rounded, label: '홈'),
    (icon: Icons.map_rounded, label: '러닝'),
    (icon: Icons.workspace_premium_rounded, label: '스탬프'),
    (icon: Icons.person_rounded, label: '마이페이지'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: BottomAppBar(
        color: Colors.white,
        elevation: 0,
        height: 68,
        padding: EdgeInsets.zero,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final (index, item) in _items.indexed)
              _NavItem(
                icon: item.icon,
                label: item.label,
                selected: _index == index,
                onTap: () => setState(() => _index = index),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.ink : const Color(0xFFA3ABB6);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
