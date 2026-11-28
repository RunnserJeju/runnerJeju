import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../models/running_course.dart';
import '../network/api_client.dart';
import '../network/conditional.dart';
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

  /// 조건 없는 전체 목록. 서비스가 기억해 두고 [etag]로 바뀌었는지만 묻는다.
  Future<Conditional<List<RunningCourse>>> fetchAllCourses({String? etag}) =>
      _client.getConditional(
        '/courses',
        etag: etag,
        parse: (data) => parseList(data, RunningCourse.fromJson),
      );

  /// 코스 상세 (경로 좌표 포함).
  Future<RunningCourse> fetchCourse(String courseId) async {
    final response = await _client.dio.get('/courses/$courseId');
    return RunningCourse.fromJson(response.data as Map<String, dynamic>);
  }

  /// 코스 GPX 원본 파일 바이트. 서버에 원본이 없는 코스는 404.
  Future<Uint8List> downloadGpx(String courseId) async {
    final response = await _client.dio.get<List<int>>(
      '/courses/$courseId/gpx',
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data ?? const []);
  }
}
