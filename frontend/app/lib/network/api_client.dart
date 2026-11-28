import 'package:dio/dio.dart';

import 'auth_interceptor.dart';
import 'conditional.dart';

/// Transport 계층: HTTP 통신 자체만 담당한다. 엔드포인트나 응답 파싱은 모른다.
class ApiClient {
  ApiClient({
    required String baseUrl,
    Future<String?> Function()? readAccessToken,
    Future<String?> Function()? readRefreshToken,
    Future<String> Function(String refreshToken)? refreshAccessToken,
    Future<void> Function(String accessToken)? saveAccessToken,
    Future<void> Function()? onRefreshFailed,
    Interceptor? contextInterceptor,
  }) : dio = Dio(
         BaseOptions(
           baseUrl: baseUrl,
           connectTimeout: const Duration(seconds: 30),
           receiveTimeout: const Duration(seconds: 30),
         ),
       ) {
    // 앱 문맥 헤더(세션·플랫폼·앱 버전). 인증과 무관하게 모든 요청에 붙는다.
    if (contextInterceptor != null) dio.interceptors.add(contextInterceptor);
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

  /// 변경 확인 GET. [etag]를 보내고, 서버가 304면 본문 없이 notModified를 돌려준다.
  Future<Conditional<T>> getConditional<T>(
    String path, {
    required String? etag,
    required T Function(dynamic data) parse,
  }) async {
    final response = await dio.get(
      path,
      options: Options(
        headers: {'If-None-Match': ?etag},
        validateStatus: (status) =>
            status != null &&
            (status == 304 || (status >= 200 && status < 300)),
      ),
    );
    if (response.statusCode == 304) return const Conditional.notModified();
    return Conditional(parse(response.data), response.headers.value('etag'));
  }
}
