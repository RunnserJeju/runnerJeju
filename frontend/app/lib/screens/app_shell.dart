import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'course/course_list_screen.dart';
import 'home/home_screen.dart';
import 'profile/profile_screen.dart';
import 'run/run_screen.dart';
import 'stamp/stamp_screen.dart';

/// 하단 탭 + 중앙 러닝 시작 버튼으로 구성된 앱 뼈대.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _tabs = <Widget>[
    HomeScreen(),
    CourseListScreen(),
    StampScreen(),
    ProfileScreen(),
  ];

  void _startRun() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RunScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton.large(
        onPressed: _startRun,
        backgroundColor: AppColors.ink,
        foregroundColor: AppColors.accent,
        shape: const CircleBorder(),
        child: const Icon(Icons.directions_run_rounded, size: 34),
      ),
      bottomNavigationBar: BottomAppBar(
        color: Colors.white,
        elevation: 0,
        height: 68,
        padding: EdgeInsets.zero,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _NavItem(
              icon: Icons.home_rounded,
              label: '홈',
              selected: _index == 0,
              onTap: () => setState(() => _index = 0),
            ),
            _NavItem(
              icon: Icons.route_rounded,
              label: '코스',
              selected: _index == 1,
              onTap: () => setState(() => _index = 1),
            ),
            const SizedBox(width: 72),
            _NavItem(
              icon: Icons.workspace_premium_rounded,
              label: '스탬프',
              selected: _index == 2,
              onTap: () => setState(() => _index = 2),
            ),
            _NavItem(
              icon: Icons.person_rounded,
              label: '프로필',
              selected: _index == 3,
              onTap: () => setState(() => _index = 3),
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
