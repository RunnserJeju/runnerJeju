import 'package:dio/dio.dart';

import '../models/running_course.dart';
import '../network/api_client.dart';

/// API 계층: 코스 관련 서버 엔드포인트 1개당 메서드 1개.
class CourseApi {
  CourseApi(this._client);

  final ApiClient _client;

  /// 코스 목록. keyword는 서버 쿼리 파라미터로 그대로 넘긴다.
  Future<List<RunningCourse>> fetchCourses({String? keyword}) async {
    final response = await _client.dio.get(
      '/courses',
      queryParameters: {
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

  /// GPX 파일로 코스를 등록한다 (관리자 전용).
  ///
  /// 항상 새 코스가 생긴다 — 같은 파일을 두 번 올리면 코스도 두 개가 된다.
  /// 거리·난이도·주소는 GPX에서 알 수 없으므로 폼으로 함께 보낸다.
  Future<RunningCourse> uploadGpx({
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
    final formData = FormData.fromMap({
      'name': name,
      'distance_km': distanceKm,
      'difficulty': difficulty.value,
      'address': address,
      'tags': ?tags,
      'parking_address': ?parkingAddress,
      'restroom_address': ?restroomAddress,
      'description': ?description,
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });

    final response = await _client.dio.post(
      '/courses/gpx',
      data: formData,
      options: Options(sendTimeout: const Duration(seconds: 30)),
    );

    return RunningCourse.fromJson(response.data as Map<String, dynamic>);
  }
}
