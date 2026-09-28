import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../api/course_api.dart';
import '../exceptions/app_exception.dart';
import '../models/running_course.dart';

/// 비즈니스 로직 계층: 코스 조회. UI가 이해할 수 있는 형태로 오류를 바꿔준다.
class CourseService {
  CourseService(this._courseApi);

  final CourseApi _courseApi;

  /// 파일명에 쓸 수 없는 문자(Windows 기준이 가장 엄격하다)와 제어 문자.
  /// 서버의 다운로드 파일명 규칙(routers/courses.py `_gpx_filename`)과 같다.
  static final RegExp _unsafeFilename = RegExp(r'[\\/:*?"<>|\x00-\x1f]+');

  Future<List<RunningCourse>> loadCourses({String? keyword, int? limit}) async {
    try {
      return await _courseApi.fetchCourses(keyword: keyword, limit: limit);
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

  /// 코스 GPX 원본을 받아 임시 파일로 저장한다. 공유 시트로 넘길 파일이다.
  ///
  /// 공유가 끝나면 쓸 일이 없어 캐시 디렉터리에 두고 OS가 비우게 한다. 같은
  /// 코스는 같은 이름으로 덮어써서 누를 때마다 파일이 쌓이지 않는다.
  Future<File> downloadGpx(RunningCourse course) async {
    try {
      final bytes = await _courseApi.downloadGpx(course.id);
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/${gpxFileName(course.name)}');
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        throw AppException('이 코스는 GPX 파일이 아직 없어요.', e);
      }
      throw AppException('GPX 파일을 받지 못했어요.', e);
    } catch (e) {
      throw AppException('GPX 파일을 받지 못했어요.', e);
    }
  }

  static String gpxFileName(String courseName) {
    var name = courseName.replaceAll(_unsafeFilename, '_').trim();
    name = name.replaceAll(RegExp(r'^[ .]+|[ .]+$'), '');
    return '${name.isEmpty ? 'course' : name}.gpx';
  }
}
