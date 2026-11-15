import 'package:flutter/widgets.dart';

import 'user_log_service.dart';

/// 지금 보는 화면을 [UserLogService.viewScreen]에 알린다(screen_view 로그).
///
/// 화면 = 맨 위 페이지 라우트의 이름(RouteSettings.name). 맨 위가 탭 화면(AppShell)이면
/// 고른 탭([tab])이다. 다이얼로그·바텀시트는 화면으로 치지 않는다.
class ScreenObserver extends NavigatorObserver {
  ScreenObserver(this._userLog);

  final UserLogService _userLog;

  /// AppShell 라우트 이름. 홈(AuthGate)으로 뜬 경우는 기본 이름 '/'이다.
  static const _shellNames = {'shell', '/'};

  final List<PageRoute<dynamic>> _pages = [];
  String? _tab;

  /// AppShell이 고른 탭. AppShell이 사라지면 null.
  set tab(String? value) {
    _tab = value;
    _report();
  }

  void _report() {
    final name = _pages.isEmpty ? null : _pages.last.settings.name;
    _userLog.viewScreen(
      name == null || _shellNames.contains(name) ? _tab : name,
    );
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is! PageRoute) return;
    _pages.add(route);
    _report();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _drop(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _drop(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _pages.remove(oldRoute);
    if (newRoute is PageRoute) _pages.add(newRoute);
    _report();
  }

  void _drop(Route<dynamic> route) {
    if (_pages.remove(route)) _report();
  }
}
