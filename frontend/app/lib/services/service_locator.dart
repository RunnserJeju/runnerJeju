import '../api/auth_api.dart';
import '../api/banner_api.dart';
import '../api/course_api.dart';
import '../api/notice_api.dart';
import '../api/run_api.dart';
import '../api/stamp_api.dart';
import '../api/verification_api.dart';
import '../config/app_config.dart';
import '../network/api_client.dart';
import 'auth_service.dart';
import 'banner_service.dart';
import 'course_service.dart';
import 'location_service.dart';
import 'notice_service.dart';
import 'run_service.dart';
import 'run_tracker.dart';
import 'stamp_service.dart';
import 'token_storage.dart';
import 'verification_service.dart';

/// 앱 전역에서 공유하는 서비스 인스턴스 모음.
///
/// 상태관리 패키지를 도입하기 전까지의 최소 DI. 화면은 여기서 서비스를 꺼내 쓴다.
class Services {
  Services._();

  static final Services instance = Services._();

  late final TokenStorage tokenStorage = TokenStorage();

  late final ApiClient apiClient = ApiClient(
    baseUrl: AppConfig.apiBaseUrl,
    getAccessToken: tokenStorage.readAccessToken,
  );

  late final AuthService auth = AuthService(AuthApi(apiClient), tokenStorage);
  late final CourseService course = CourseService(CourseApi(apiClient));
  late final RunService run = RunService(RunApi(apiClient));
  late final StampService stamp = StampService(StampApi(apiClient));
  late final VerificationService verification = VerificationService(
    VerificationApi(apiClient),
  );
  late final NoticeService notice = NoticeService(NoticeApi(apiClient));
  late final BannerService banner = BannerService(BannerApi(apiClient));

  /// 실제 GPS. 시뮬레이션 러닝은 이걸 바꾸지 않고 [RunTracker.start]에
  /// 위치원을 따로 넘긴다 — 그래야 앱 전역이 아니라 그 한 번의 러닝만 가짜가 된다.
  late final LocationService location = LocationService();

  /// 진행 중인 러닝은 화면 전환과 무관하게 유지되어야 하므로 전역에 하나만 둔다.
  late final RunTracker runTracker = RunTracker(location);
}
