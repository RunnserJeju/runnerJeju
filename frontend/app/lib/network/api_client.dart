import 'package:dio/dio.dart';

/// Transport 계층: HTTP 통신 자체만 담당한다. 엔드포인트나 응답 파싱은 모른다.
class ApiClient {
  ApiClient({String baseUrl = 'http://10.0.2.2:8000'})
    : dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );

  final Dio dio;
}
