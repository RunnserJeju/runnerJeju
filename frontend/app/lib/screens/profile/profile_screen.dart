import 'package:flutter/material.dart';

import '../../models/user.dart';
import '../../models/user_log.dart';
import '../../services/service_locator.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/profile_avatar.dart';
import '../../widgets/section_title.dart';
import '../auth/login_screen.dart';
import 'completed_courses_screen.dart';
import 'coupon_list_screen.dart';
import 'favorite_courses_screen.dart';
import 'member_info_screen.dart';
import 'run_calendar.dart';

/// 마이페이지: 프로필 카드(누르면 회원 정보) → 캘린더 → 항목 목록(각자 화면으로 들어간다).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.onOpenCourse});

  /// 코스 카드를 눌렀을 때. 러닝 탭으로 옮겨 그 코스를 고른 상태로 연다.
  final void Function(String courseId, LogSource source) onOpenCourse;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<User?> _user = _loadUser();

  /// 당겨서 새로고침하면 바뀐다. 달력을 새로 만들어 이번 달부터 다시 받는다.
  int _generation = 0;

  static Future<User?> _loadUser() =>
      Services.instance.auth.loadCurrentUser(refresh: true);

  Future<void> _refresh() async {
    setState(() {
      _user = _loadUser();
      _generation++;
    });
  }

  Future<void> _logout() async {
    await Services.instance.auth.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _push(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  /// 회원 정보에서 사진을 바꾸고 돌아오면 카드에도 반영한다(서비스가 들고 있는 값).
  Future<void> _openMemberInfo() async {
    await _push(const MemberInfoScreen());
    if (!mounted) return;
    setState(() => _user = Services.instance.auth.loadCurrentUser());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('마이페이지'),
        actions: [
          IconButton(
            tooltip: '로그아웃',
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
          children: [
            FutureBuilder<User?>(
              future: _user,
              builder: (context, snapshot) =>
                  _ProfileCard(user: snapshot.data, onTap: _openMemberInfo),
            ),
            const SizedBox(height: 24),
            const SectionTitle('캘린더'),
            const SizedBox(height: 12),
            RunCalendar(key: ValueKey(_generation)),
            const SizedBox(height: 24),
            _MenuEntry(
              icon: Icons.flag_rounded,
              label: '완주 코스',
              onTap: () => _push(
                CompletedCoursesScreen(
                  onOpenCourse: (id) =>
                      widget.onOpenCourse(id, LogSource.profile),
                ),
              ),
            ),
            _MenuEntry(
              icon: Icons.favorite_rounded,
              label: '찜한 코스',
              onTap: () => _push(
                FavoriteCoursesScreen(
                  onOpenCourse: (id) =>
                      widget.onOpenCourse(id, LogSource.favorite),
                ),
              ),
            ),
            // 쿠폰은 업체에서 보여주며 쓰는 것이라 마이페이지에 둔다.
            _MenuEntry(
              icon: Icons.confirmation_number_rounded,
              label: '내 쿠폰',
              onTap: () => _push(const CouponListScreen()),
            ),
          ],
        ),
      ),
    );
  }
}

/// 맨 위 작은 프로필: 닉네임, 이메일, 가입일. 누르면 회원 정보.
/// 불러오는 중이면 빈 자리만 잡는다.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.user, required this.onTap});

  final User? user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final user = this.user;
    final email = user?.email;
    final joined = user?.createdAt;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              ProfileAvatar(imageUrl: user?.profileImageUrl),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      user?.nickname ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (email != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSubtle,
                        ),
                      ),
                    ],
                    if (joined != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${Formatters.date(joined)} 가입',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textFaint,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuEntry extends StatelessWidget {
  const _MenuEntry({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Icon(icon, color: AppColors.accent),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
