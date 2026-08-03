import 'package:flutter/material.dart';

import '../models/user.dart';
import '../services/service_locator.dart';

/// admin 계정일 때만 [child]를 보여준다. 아니면 아무것도 그리지 않는다.
///
/// 이건 보안 장치가 아니라 화면 정리다. 관리자 전용 엔드포인트는 서버가
/// `require_admin`으로 이미 403을 준다. 여기서 하는 일은 "눌러도 실패할 버튼을
/// 애초에 보여주지 않는" 것뿐이다.
///
/// 권한을 아직 모르거나(첫 조회 전) 조회에 실패하면 감추는 쪽으로 넘어간다.
/// 잠깐 안 보이는 편이, 일반 사용자에게 잠깐 보이는 것보다 낫다.
class AdminOnly extends StatelessWidget {
  const AdminOnly({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // 캐시가 이미 차 있으면 깜빡임 없이 바로 그린다.
    final cached = Services.instance.auth.currentUser;
    if (cached != null) {
      return cached.isAdmin ? child : const SizedBox.shrink();
    }

    return FutureBuilder<User?>(
      future: Services.instance.auth.loadCurrentUser(),
      builder: (context, snapshot) {
        final user = snapshot.data;
        if (user == null || !user.isAdmin) return const SizedBox.shrink();
        return child;
      },
    );
  }
}
