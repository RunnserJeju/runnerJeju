import 'package:dio/dio.dart';

import '../network/api_client.dart';

/// API 계층: 가민·순토 링크로 코스 완주 인증.
class ExternalCertApi {
  ExternalCertApi(this._client);

  final ApiClient _client;

  /// 서버가 링크를 읽고 판정·보상까지 한 번에 끝낸다. 상대 서비스가 느리면 오래 걸려
  /// 기본보다 길게 기다린다.
  Future<Map<String, dynamic>> submit({
    required String courseId,
    required String url,
  }) async {
    final response = await _client.dio.post(
      '/courses/$courseId/external-completions',
      data: {'url': url},
      options: Options(receiveTimeout: const Duration(seconds: 60)),
    );
    return response.data as Map<String, dynamic>;
  }
}
