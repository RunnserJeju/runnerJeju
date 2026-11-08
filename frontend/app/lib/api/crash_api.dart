import 'package:dio/dio.dart';

import '../network/api_client.dart';

/// API 계층: 크래시 리포트 전송. 서버 routers/crash_reports.upload_crash_report에 대응한다.
class CrashApi {
  CrashApi(this._client);

  final ApiClient _client;

  /// 한 건. [dumpGz]는 gzip으로 압축한 원본 덤프. 성공은 204(이미 받은 id도 204).
  Future<void> upload({required String meta, List<int>? dumpGz}) async {
    await _client.dio.post(
      '/crash-reports',
      data: FormData.fromMap({
        'meta': meta,
        if (dumpGz != null)
          'dump': MultipartFile.fromBytes(
            dumpGz,
            filename: 'dump.gz',
            contentType: DioMediaType('application', 'gzip'),
          ),
      }),
    );
  }
}
