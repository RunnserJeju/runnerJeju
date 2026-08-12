import '../api/course_api.dart';
import '../exceptions/app_exception.dart';
import '../models/running_course.dart';

/// 비즈니스 로직 계층: 코스 조회/등록. UI가 이해할 수 있는 형태로 오류를 바꿔준다.
class CourseService {
  CourseService(this._courseApi);

  final CourseApi _courseApi;

  Future<List<RunningCourse>> loadCourses({String? keyword}) async {
    try {
      return await _courseApi.fetchCourses(keyword: keyword);
    } catch (e) {
      throw AppException('코스 목록을 불러오지 못했어요.', e);
    }
  }

  Future<RunningCourse> loadCourse(String courseId) async {
    try {
      return await _courseApi.fetchCourse(courseId);
    } catch (e) {
      throw AppException('코스 정보를 불러오지 못했어요.', e);
    }
  }

  /// GPX 파일을 코스로 등록한다 (관리자용 수동 업로드).
  Future<RunningCourse> uploadGpxFile({
    required List<int> bytes,
    required String filename,
    required String name,
    required int distanceKm,
    required CourseDifficulty difficulty,
    required String address,
    String? tags,
    String? parkingAddress,
    String? restroomAddress,
    String? description,
  }) async {
    if (bytes.isEmpty) {
      throw AppException('GPX 파일이 비어 있어요.');
    }

    try {
      return await _courseApi.uploadGpx(
        bytes: bytes,
        filename: filename,
        name: name,
        distanceKm: distanceKm,
        difficulty: difficulty,
        address: address,
        tags: tags,
        parkingAddress: parkingAddress,
        restroomAddress: restroomAddress,
        description: description,
      );
    } catch (e) {
      throw AppException('GPX 업로드에 실패했어요.', e);
    }
  }
}
