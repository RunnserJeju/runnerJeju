import '../api/course_api.dart';
import '../models/geo_point.dart';
import '../models/run_record.dart';
import '../models/running_course.dart';
import '../utils/geo_utils.dart';

/// 비즈니스 로직 계층: 코스 조회/등록. UI가 이해할 수 있는 형태로 오류를 바꿔준다.
class CourseService {
  CourseService(this._courseApi);

  final CourseApi _courseApi;

  Future<List<RunningCourse>> loadCourses({
    String? region,
    String? keyword,
  }) async {
    try {
      return await _courseApi.fetchCourses(region: region, keyword: keyword);
    } catch (e) {
      throw CourseException('코스 목록을 불러오지 못했어요.', e);
    }
  }

  Future<RunningCourse> loadCourse(String courseId) async {
    try {
      return await _courseApi.fetchCourse(courseId);
    } catch (e) {
      throw CourseException('코스 정보를 불러오지 못했어요.', e);
    }
  }

  /// 방금 달린 기록을 코스로 등록한다.
  Future<RunningCourse> uploadFromRecord({
    required RunRecord record,
    required String name,
    String? description,
    String? region,
    CourseDifficulty difficulty = CourseDifficulty.normal,
  }) {
    return uploadPath(
      path: record.path,
      name: name,
      description: description,
      region: region,
      difficulty: difficulty,
    );
  }

  Future<RunningCourse> uploadPath({
    required List<GeoPoint> path,
    required String name,
    String? description,
    String? region,
    CourseDifficulty difficulty = CourseDifficulty.normal,
  }) async {
    if (path.length < 2) {
      throw CourseException('코스로 등록하려면 경로가 2개 지점 이상이어야 해요.');
    }

    try {
      return await _courseApi.uploadCourse(
        CourseUploadRequest(
          name: name,
          description: description,
          region: region,
          difficulty: difficulty,
          distanceMeters: GeoUtils.pathLength(path),
          path: path,
        ),
      );
    } catch (e) {
      throw CourseException('코스 등록에 실패했어요.', e);
    }
  }
}

class CourseException implements Exception {
  CourseException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}
