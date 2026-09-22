import 'package:dio/dio.dart';

/// 모든 요청에 앱 문맥(세션·플랫폼·앱 버전)을 헤더로 싣는다.
///
/// 서버가 직접 남기는 행동 로그(코스 상세 조회 등)가 앱이 보내는 로그와 같은
/// 세션으로 묶이게 하려는 것이다(서버 deps.client_context). 값은 요청 시점에
/// 읽는다 — 세션은 백그라운드 복귀 때 바뀔 수 있어서 생성자에서 고정하지 않는다.
class ClientContextInterceptor extends Interceptor {
  ClientContextInterceptor({
    required this.sessionId,
    required this.platform,
    required this.appVersion,
  });

  final String Function() sessionId;
  final String Function() platform;
  final String Function() appVersion;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers['X-Session-Id'] = sessionId();
    options.headers['X-Platform'] = platform();
    options.headers['X-App-Version'] = appVersion();
    handler.next(options);
  }
}
