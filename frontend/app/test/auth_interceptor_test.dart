import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runners_jeju/network/auth_interceptor.dart';

/// AuthInterceptor를 실제 Dio 파이프라인에 붙이고, 응답을 우리가 통제하는
/// 가짜 어댑터로 검증한다. 어댑터는 요청의 Authorization 헤더를 보고 응답을
/// 정하므로, "만료 토큰 → 401 → refresh → 새 토큰으로 재시도 → 200" 흐름을
/// 그대로 재현할 수 있다.

const _jsonHeaders = {
  Headers.contentTypeHeader: [Headers.jsonContentType],
};

/// 요청마다 [respond] 콜백으로 응답을 만드는 어댑터. 실제 네트워크는 타지 않는다.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.respond);

  final ResponseBody Function(RequestOptions options) respond;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => respond(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Map<String, dynamic> body, int status) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: _jsonHeaders);

/// 저장소를 흉내 낸다. saveAccessToken이 갱신한 값을 readAccessToken이 읽으므로
/// 재시도 요청이 새 토큰을 집어가는 실제 동작을 그대로 따른다.
class _FakeStore {
  _FakeStore({this.access, this.refresh});

  String? access;
  String? refresh;
  bool cleared = false;

  void clear() {
    access = null;
    refresh = null;
    cleared = true;
  }
}

/// [store]와 refresh 동작을 주입해 인터셉터가 붙은 Dio를 만든다.
Dio _buildDio({
  required _FakeStore store,
  required ResponseBody Function(RequestOptions options) respond,
  required Future<String> Function(String refreshToken) refreshAccessToken,
}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://test.local'));
  dio.httpClientAdapter = _FakeAdapter(respond);
  dio.interceptors.add(
    AuthInterceptor(
      dio: dio,
      readAccessToken: () async => store.access,
      readRefreshToken: () async => store.refresh,
      refreshAccessToken: refreshAccessToken,
      saveAccessToken: (t) async => store.access = t,
      onRefreshFailed: () async => store.clear(),
    ),
  );
  return dio;
}

void main() {
  group('AuthInterceptor', () {
    test('요청에 access token을 Bearer로 붙인다', () async {
      final store = _FakeStore(access: 'abc');
      String? seenAuth;
      final dio = _buildDio(
        store: store,
        respond: (options) {
          seenAuth = options.headers['Authorization'] as String?;
          return _json({'ok': true}, 200);
        },
        refreshAccessToken: (_) async => fail('refresh를 부르면 안 된다'),
      );

      await dio.get('/me');

      expect(seenAuth, 'Bearer abc');
    });

    test('access token 만료(401)면 refresh 후 새 토큰으로 재시도해 성공한다', () async {
      final store = _FakeStore(access: 'expired', refresh: 'r');
      var refreshCalls = 0;
      final seenAuths = <String?>[];

      final dio = _buildDio(
        store: store,
        respond: (options) {
          final auth = options.headers['Authorization'] as String?;
          seenAuths.add(auth);
          if (auth == 'Bearer fresh') return _json({'ok': true}, 200);
          return _json({'detail': 'expired'}, 401);
        },
        refreshAccessToken: (rt) async {
          refreshCalls++;
          expect(rt, 'r');
          return 'fresh';
        },
      );

      final res = await dio.get('/me');

      expect(res.statusCode, 200);
      expect(refreshCalls, 1);
      // 첫 요청은 만료 토큰, 재시도는 새 토큰으로 나갔다.
      expect(seenAuths, ['Bearer expired', 'Bearer fresh']);
      // 새 토큰이 저장소에 반영됐다.
      expect(store.access, 'fresh');
      expect(store.cleared, isFalse);
    });

    test('동시에 여러 요청이 401이어도 refresh는 딱 한 번만 한다', () async {
      final store = _FakeStore(access: 'expired', refresh: 'r');
      var refreshCalls = 0;
      final gate = Completer<void>();

      final dio = _buildDio(
        store: store,
        respond: (options) {
          final auth = options.headers['Authorization'] as String?;
          if (auth == 'Bearer fresh') return _json({'ok': true}, 200);
          return _json({'detail': 'expired'}, 401);
        },
        refreshAccessToken: (rt) async {
          refreshCalls++;
          // 세 요청이 모두 401을 받고 refresh에 편승할 때까지 붙잡아 둔다.
          await gate.future;
          return 'fresh';
        },
      );

      final futures = Future.wait([
        dio.get('/a'),
        dio.get('/b'),
        dio.get('/c'),
      ]);
      // 세 요청이 401을 받고 refresh 대기에 모이도록 이벤트 큐를 비운다.
      await pumpEventQueue();
      gate.complete();
      final results = await futures;

      expect(results.map((r) => r.statusCode), everyElement(200));
      expect(refreshCalls, 1);
      expect(store.access, 'fresh');
    });

    test('refresh token이 만료/폐기(refresh 실패)면 토큰을 지우고 401을 그대로 올린다', () async {
      final store = _FakeStore(access: 'expired', refresh: 'dead');

      final dio = _buildDio(
        store: store,
        respond: (_) => _json({'detail': 'expired'}, 401),
        refreshAccessToken: (_) async =>
            throw DioException(
              requestOptions: RequestOptions(path: '/auth/refresh'),
              response: Response(
                requestOptions: RequestOptions(path: '/auth/refresh'),
                statusCode: 401,
              ),
            ),
      );

      DioException? thrown;
      try {
        await dio.get('/me');
      } on DioException catch (e) {
        thrown = e;
      }

      expect(thrown, isNotNull);
      expect(thrown!.response?.statusCode, 401);
      expect(store.cleared, isTrue);
      expect(store.access, isNull);
      expect(store.refresh, isNull);
    });

    test('refresh token이 없으면 refresh를 시도하지 않고 토큰을 지운다', () async {
      final store = _FakeStore(access: 'expired'); // refresh 없음
      var refreshCalls = 0;

      final dio = _buildDio(
        store: store,
        respond: (_) => _json({'detail': 'expired'}, 401),
        refreshAccessToken: (_) async {
          refreshCalls++;
          return 'fresh';
        },
      );

      await expectLater(dio.get('/me'), throwsA(isA<DioException>()));
      expect(refreshCalls, 0);
      expect(store.cleared, isTrue);
    });

    test('401이 아닌 에러(500)는 refresh 없이 그대로 통과시킨다', () async {
      final store = _FakeStore(access: 'ok', refresh: 'r');
      var refreshCalls = 0;

      final dio = _buildDio(
        store: store,
        respond: (_) => _json({'detail': 'boom'}, 500),
        refreshAccessToken: (_) async {
          refreshCalls++;
          return 'fresh';
        },
      );

      DioException? thrown;
      try {
        await dio.get('/me');
      } on DioException catch (e) {
        thrown = e;
      }

      expect(thrown!.response?.statusCode, 500);
      expect(refreshCalls, 0);
      expect(store.cleared, isFalse);
    });

    test('재시도한 요청이 또 401이면 다시 refresh하지 않고 포기한다(무한 루프 방지)', () async {
      final store = _FakeStore(access: 'expired', refresh: 'r');
      var refreshCalls = 0;

      final dio = _buildDio(
        store: store,
        // 토큰이 뭐든 항상 401 — refresh가 성공해도 재시도가 또 401이 된다.
        respond: (_) => _json({'detail': 'expired'}, 401),
        refreshAccessToken: (_) async {
          refreshCalls++;
          return 'fresh';
        },
      );

      await expectLater(dio.get('/me'), throwsA(isA<DioException>()));
      // refresh는 딱 한 번만 — 재시도의 401이 또 refresh를 부르면 안 된다.
      expect(refreshCalls, 1);
    });
  });
}
