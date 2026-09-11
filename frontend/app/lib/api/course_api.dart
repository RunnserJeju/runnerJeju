import '../models/running_course.dart';
import '../network/api_client.dart';
import '../network/json.dart';

/// API 계층: 코스 관련 서버 엔드포인트 1개당 메서드 1개.
class CourseApi {
  CourseApi(this._client);

  final ApiClient _client;

  /// 코스 목록. keyword(이름 부분 일치)와 limit은 서버 쿼리 파라미터로 그대로 넘긴다.
  Future<List<RunningCourse>> fetchCourses({
    String? keyword,
    int? limit,
  }) async {
    final response = await _client.dio.get(
      '/courses',
      queryParameters: {
        if (keyword != null && keyword.isNotEmpty) 'keyword': keyword,
        'limit': ?limit,
      },
    );

    return parseList(response.data, RunningCourse.fromJson);
  }

  /// 코스 상세 (경로 좌표 포함).
  Future<RunningCourse> fetchCourse(String courseId) async {
    final response = await _client.dio.get('/courses/$courseId');
    return RunningCourse.fromJson(response.data as Map<String, dynamic>);
  }
}
