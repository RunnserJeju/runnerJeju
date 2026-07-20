import '../models/running_course.dart';
import '../network/api_client.dart';

/// API 계층: 코스 관련 서버 엔드포인트 1개당 메서드 1개.
class CourseApi {
  CourseApi(this._client);

  final ApiClient _client;

  /// 코스 목록. region/keyword는 서버 쿼리 파라미터로 그대로 넘긴다.
  Future<List<RunningCourse>> fetchCourses({
    String? region,
    String? keyword,
  }) async {
    final response = await _client.dio.get(
      '/courses',
      queryParameters: {
        'region': ?region,
        if (keyword != null && keyword.isNotEmpty) 'keyword': keyword,
      },
    );

    return (response.data as List)
        .map((e) => RunningCourse.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 코스 상세 (경로 좌표 포함).
  Future<RunningCourse> fetchCourse(String courseId) async {
    final response = await _client.dio.get('/courses/$courseId');
    return RunningCourse.fromJson(response.data as Map<String, dynamic>);
  }

  /// 내가 달린 경로를 새 코스로 등록.
  Future<RunningCourse> uploadCourse(CourseUploadRequest request) async {
    final response = await _client.dio.post('/courses', data: request.toJson());
    return RunningCourse.fromJson(response.data as Map<String, dynamic>);
  }
}
