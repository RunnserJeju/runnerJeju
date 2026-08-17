import 'package:dio/dio.dart';

/// 요청에 access token을 붙이고, 401을 만나면 refresh token으로 재발급받아
/// 원래 요청을 자동으로 재시도한다.
///
/// 이렇게 해야 access token(1시간)이 만료돼도 사용자를 로그인 화면으로 튕기지 않고
/// refresh token(30일)이 살아 있는 동안은 세션이 조용히 유지된다.
///
/// 설계 요점:
/// - 여러 요청이 동시에 401을 받아도 refresh는 [_refreshing]에 편승해 한 번만 한다.
/// - refresh 요청 자체는 인터셉터가 없는 별도 Dio로 보내야 401 재귀가 안 생긴다
///   (그 배선은 [ApiClient]/service_locator에서 한다).
/// - 재시도한 요청이 또 401이면(`__retried__`) 포기해 무한 루프를 막는다.
/// - refresh가 실패(refresh token 만료/폐기)하면 [onRefreshFailed]로 알리고
///   원래 401을 그대로 올려보낸다 — 호출부(AsyncView)가 로그인 화면으로 보낸다.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.dio,
    required this.readAccessToken,
    required this.readRefreshToken,
    required this.refreshAccessToken,
    required this.saveAccessToken,
    required this.onRefreshFailed,
  });

  /// 원래 요청을 재시도할 때 쓴다. 보통 이 인터셉터가 붙은 Dio와 같은 인스턴스다.
  final Dio dio;

  final Future<String?> Function() readAccessToken;
  final Future<String?> Function() readRefreshToken;

  /// refresh token으로 새 access token을 받아온다. 실패하면 예외를 던진다.
  final Future<String> Function(String refreshToken) refreshAccessToken;

  /// 재발급받은 access token을 저장한다. 저장 직후 재시도 요청이 이 값을 읽어 쓴다.
  final Future<void> Function(String accessToken) saveAccessToken;

  /// refresh가 불가능/실패할 때(=재로그인 필요) 호출한다. 보통 저장된 토큰을 지운다.
  final Future<void> Function() onRefreshFailed;

  /// 진행 중인 refresh. 동시 요청이 여기에 편승해 refresh를 한 번만 하게 한다.
  Future<String?>? _refreshing;

  static const _retriedFlag = '__retried__';

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await readAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (!_shouldRefresh(err)) {
      return handler.next(err);
    }

    final newToken = await _refreshOnce();
    if (newToken == null) {
      // refresh 실패 — 토큰 정리는 _doRefresh가 이미 했다. 원래 401을 올린다.
      return handler.next(err);
    }

    try {
      handler.resolve(await _retry(err.requestOptions));
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  bool _shouldRefresh(DioException err) {
    if (err.response?.statusCode != 401) return false;
    // 이미 한 번 재시도한 요청이 또 401이면 포기한다(무한 루프 방지).
    if (err.requestOptions.extra[_retriedFlag] == true) return false;
    return true;
  }

  /// 진행 중인 refresh가 있으면 그 결과를 함께 기다린다. 없으면 새로 시작한다.
  /// 성공하면 새 access token을, 실패하면 null을 돌려준다.
  Future<String?> _refreshOnce() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<String?> _doRefresh() async {
    final refreshToken = await readRefreshToken();
    if (refreshToken == null) {
      await onRefreshFailed();
      return null;
    }
    try {
      final newToken = await refreshAccessToken(refreshToken);
      await saveAccessToken(newToken);
      return newToken;
    } catch (_) {
      await onRefreshFailed();
      return null;
    }
  }

  /// 새 access token은 [saveAccessToken]으로 이미 저장됐으므로, 재시도 요청의
  /// onRequest가 저장소에서 최신 토큰을 읽어 헤더에 붙인다.
  Future<Response<dynamic>> _retry(RequestOptions options) {
    options.extra[_retriedFlag] = true;
    return dio.fetch(options);
  }
}
