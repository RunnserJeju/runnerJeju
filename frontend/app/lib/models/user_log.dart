/// 사용자 행동 로그 한 건. 서버 user_log 테이블(POST /user-logs)과 1:1이다.
///
/// 화면은 이 클래스를 직접 만들지 않는다 — [writeLog]에 이름과 detail만 넘기면
/// 세션·플랫폼·앱 버전은 UserLogService가 채운다.
class UserLog {
  const UserLog({
    required this.name,
    required this.detail,
    required this.sessionId,
    required this.platform,
    required this.appVersion,
  });

  final LogName name;
  final Map<String, dynamic> detail;
  final String sessionId;
  final String platform;
  final String appVersion;

  Map<String, dynamic> toJson() => {
    'log_name': name.wire,
    'detail': detail,
    'session_id': sessionId,
    'platform': platform,
    'app_version': appVersion,
  };
}

/// 로그 이름. 서버 app/user_log.py의 LOG_NAMES와 같아야 한다 — 목록 밖 이름은
/// 서버가 422로 거절한다. 새 로그는 서버 목록에 먼저 넣고 여기 한 줄 추가한다.
enum LogName {
  // 세션
  appOpen('app_open'),
  // 홈
  homeCourseClick('home_course_click'),
  bannerClick('banner_click'),
  notificationOpen('notification_open'),
  // 코스 탐색
  coursePreviewOpen('course_preview_open'),
  courseSearch('course_search'),
  courseListSort('course_list_sort'),
  favoriteAdd('favorite_add'),
  favoriteRemove('favorite_remove'),
  navigateClick('navigate_click'),
  // 러닝
  runStart('run_start'),
  runPause('run_pause'),
  runResume('run_resume'),
  runFinish('run_finish'),
  runAbandon('run_abandon'),
  runUploadFailed('run_upload_failed'),
  runDetailOpen('run_detail_open'),
  // 스탬프·쿠폰
  stampDetailOpen('stamp_detail_open'),
  couponView('coupon_view'),
  couponUseClick('coupon_use_click'),
  // 커뮤니티
  externalLinkOpen('external_link_open'),
  // 계정
  login('login'),
  loginFailed('login_failed'),
  logout('logout'),
  withdraw('withdraw');

  const LogName(this.wire);

  /// 서버에 보내는 문자열.
  final String wire;
}

/// detail에 쓰는 키. 화면마다 표기가 갈리지 않게 여기 것만 쓴다(snake_case).
abstract final class LogKeys {
  static const courseId = 'course_id';
  static const runId = 'run_id';
  static const noticeId = 'notice_id';
  static const source = 'source';
  static const section = 'section';
  static const position = 'position';
  static const reason = 'reason';
  static const elapsedSec = 'elapsed_sec';
  static const distanceM = 'distance_m';
  static const error = 'error';
}

/// 어디서 눌렀는지(detail[LogKeys.source]).
enum LogSource { home, map, list, search, favorite, stamp, profile, detail }
