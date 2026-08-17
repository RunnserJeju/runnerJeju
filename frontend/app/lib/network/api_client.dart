import 'package:dio/dio.dart';

import 'auth_interceptor.dart';

/// Transport 계층: HTTP 통신 자체만 담당한다. 엔드포인트나 응답 파싱은 모른다.
class ApiClient {
  ApiClient({
    String baseUrl = 'http://10.0.2.2:8000',
    Future<String?> Function()? readAccessToken,
    Future<String?> Function()? readRefreshToken,
    Future<String> Function(String refreshToken)? refreshAccessToken,
    Future<void> Function(String accessToken)? saveAccessToken,
    Future<void> Function()? onRefreshFailed,
  }) : dio = Dio(
         BaseOptions(
           baseUrl: baseUrl,
           connectTimeout: const Duration(seconds: 30),
           receiveTimeout: const Duration(seconds: 30),
         ),
       ) {
    // access token을 읽을 수 있을 때만 인증 인터셉터를 붙인다. refresh 전용 클라이언트처럼
    // 토큰이 필요 없는 경우엔 붙이지 않아 401 재귀를 원천 차단한다.
    if (readAccessToken != null) {
      dio.interceptors.add(
        AuthInterceptor(
          dio: dio,
          readAccessToken: readAccessToken,
          readRefreshToken: readRefreshToken ?? (() async => null),
          refreshAccessToken:
              refreshAccessToken ??
              ((_) async => throw StateError('refreshAccessToken이 설정되지 않았어요.')),
          saveAccessToken: saveAccessToken ?? ((_) async {}),
          onRefreshFailed: onRefreshFailed ?? (() async {}),
        ),
      );
    }
  }

  final Dio dio;
}
