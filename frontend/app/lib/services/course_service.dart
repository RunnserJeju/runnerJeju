import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../api/course_api.dart';
import '../exceptions/app_exception.dart';
import '../models/running_course.dart';

/// 비즈니스 로직 계층: 코스 조회. UI가 이해할 수 있는 형태로 오류를 바꿔준다.
class CourseService {
  CourseService(this._courseApi);

  final CourseApi _courseApi;

  static const MethodChannel _downloadsChannel = MethodChannel(
    'runners_jeju/downloads',
  );

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

  /// 코스 GPX 원본을 받아 임시 파일로 저장한다. 다운로드 폴더로 복사하거나
  /// 공유 시트로 넘길 파일이다.
  ///
  /// 넘기고 나면 쓸 일이 없어 캐시 디렉터리에 두고 OS가 비우게 한다. 같은
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

  /// 받은 GPX를 기기의 다운로드 폴더에 넣는다. 안드로이드 10+에서만 되고, 그 밖
  /// (iOS·구형 안드로이드)에는 false를 돌려 호출부가 공유 시트를 쓰게 한다.
  Future<bool> saveGpxToDownloads(File file) async {
    if (!Platform.isAndroid) return false;
    try {
      final saved = await _downloadsChannel.invokeMethod<bool>(
        'saveToDownloads',
        {
          'path': file.path,
          'name': file.uri.pathSegments.last,
          'mimeType': 'application/gpx+xml',
        },
      );
      return saved ?? false;
    } catch (e) {
      throw AppException('GPX 파일을 저장하지 못했어요.', e);
    }
  }

  /// 이 기기에 깔린 GPX 받는 워치 앱(안드로이드만).
  Future<List<GpxApp>> installedGpxApps() async {
    if (!Platform.isAndroid) return const [];
    try {
      final installed = await _downloadsChannel.invokeListMethod<String>(
        'installedPackages',
        {'packages': GpxApp.values.map((app) => app.package).toList()},
      );
      return GpxApp.values
          .where((app) => installed?.contains(app.package) ?? false)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// [app]에 GPX를 연다. 그 앱이 파일을 직접 받지 않으면 다운로드 폴더에 저장하고
  /// 앱만 띄운 뒤 false를 돌린다 — 사용자가 앱 안에서 가져오기로 골라야 한다.
  Future<bool> openGpxInApp(File file, GpxApp app) async {
    try {
      final opened = await _downloadsChannel.invokeMethod<bool>('openInApp', {
        'path': file.path,
        'mimeType': 'application/gpx+xml',
        'package': app.package,
      });
      if (opened ?? false) return true;
      if (!await saveGpxToDownloads(file)) {
        throw AppException('GPX 파일을 저장하지 못했어요.');
      }
      await _downloadsChannel.invokeMethod<bool>('launchApp', {
        'package': app.package,
      });
      return false;
    } on AppException {
      rethrow;
    } catch (e) {
      throw AppException('${app.label} 앱을 열지 못했어요.', e);
    }
  }

  /// iOS: GPX를 받는다고 선언한 앱(가민·순토 등) 목록을 띄운다. 그런 앱이 없으면 false.
  Future<bool> openInGpxApps(File file) async {
    try {
      final shown = await _downloadsChannel.invokeMethod<bool>('openInGpxApp', {
        'path': file.path,
      });
      return shown ?? false;
    } catch (e) {
      throw AppException('GPX 파일을 열지 못했어요.', e);
    }
  }

  /// iOS: 공유 시트. share_plus와 달리 GPX 형식 두 가지를 함께 붙여 넘긴다.
  Future<void> shareGpxOnIOS(File file) async {
    try {
      await _downloadsChannel.invokeMethod<bool>('share', {'path': file.path});
    } catch (e) {
      throw AppException('GPX 파일을 열지 못했어요.', e);
    }
  }

  static String gpxFileName(String courseName) {
    var name = courseName.replaceAll(_unsafeFilename, '_').trim();
    name = name.replaceAll(RegExp(r'^[ .]+|[ .]+$'), '');
    return '${name.isEmpty ? 'course' : name}.gpx';
  }
}

/// GPX 다운로드에서 바로 여는 워치 앱. 패키지를 바꾸면 AndroidManifest의
/// `<queries>`도 함께 바꾼다.
enum GpxApp {
  garmin('Garmin Connect', 'com.garmin.android.apps.connectmobile', '코스로 가져와요'),
  suunto('Suunto', 'com.stt.android.suunto', '경로로 가져와요');

  const GpxApp(this.label, this.package, this.description);

  final String label;
  final String package;
  final String description;
}
