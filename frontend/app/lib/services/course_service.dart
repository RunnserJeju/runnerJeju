import '../api/course_api.dart';
import '../exceptions/app_exception.dart';
import '../models/running_course.dart';

/// 비즈니스 로직 계층: 코스 조회. UI가 이해할 수 있는 형태로 오류를 바꿔준다.
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
}
