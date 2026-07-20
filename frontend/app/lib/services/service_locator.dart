import '../api/course_api.dart';
import '../api/run_api.dart';
import '../api/stamp_api.dart';
import '../api/verification_api.dart';
import '../config/app_config.dart';
import '../network/api_client.dart';
import 'course_service.dart';
import 'location_service.dart';
import 'run_service.dart';
import 'run_tracker.dart';
import 'stamp_service.dart';
import 'verification_service.dart';

/// 앱 전역에서 공유하는 서비스 인스턴스 모음.
///
/// 상태관리 패키지를 도입하기 전까지의 최소 DI. 화면은 여기서 서비스를 꺼내 쓴다.
class Services {
  Services._();

  static final Services instance = Services._();

  late final ApiClient apiClient = ApiClient(baseUrl: AppConfig.apiBaseUrl);

  late final CourseService course = CourseService(CourseApi(apiClient));
  late final RunService run = RunService(RunApi(apiClient));
  late final StampService stamp = StampService(StampApi(apiClient));
  late final VerificationService verification = VerificationService(
    VerificationApi(apiClient),
  );
  late final LocationService location = LocationService();

  /// 진행 중인 러닝은 화면 전환과 무관하게 유지되어야 하므로 전역에 하나만 둔다.
  late final RunTracker runTracker = RunTracker(location);
}
