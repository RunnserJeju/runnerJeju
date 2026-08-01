import 'package:dio/dio.dart';

/// Transport 계층: HTTP 통신 자체만 담당한다. 엔드포인트나 응답 파싱은 모른다.
class ApiClient {
  ApiClient({
    String baseUrl = 'http://10.0.2.2:8000',
    Future<String?> Function()? getAccessToken,
  }) : dio = Dio(
         BaseOptions(
           baseUrl: baseUrl,
           connectTimeout: const Duration(seconds: 30),
           receiveTimeout: const Duration(seconds: 30),
         ),
       ) {
    if (getAccessToken != null) {
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            final token = await getAccessToken();
            if (token != null) {
              options.headers['Authorization'] = 'Bearer $token';
            }
            handler.next(options);
          },
        ),
      );
    }
  }

  final Dio dio;
}
