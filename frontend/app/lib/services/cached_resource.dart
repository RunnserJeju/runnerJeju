import '../network/conditional.dart';

/// 서버 응답 하나를 메모리에 잠깐 기억한다. 서비스가 조회 메서드 뒤에 둔다.
///
/// - 동시에 여러 화면이 불러도 요청은 한 번만 나간다.
/// - [ttl] 안에는 기억한 값을 준다. 지나면 가진 etag로 서버에 바뀌었는지만 묻는다.
/// - 내 행동으로 값이 달라졌으면 [invalidateAll], 계정이 바뀌면 [clearAll].
class CachedResource<T> {
  CachedResource(this._fetch, {this.ttl = const Duration(minutes: 5)}) {
    _all.add(this);
  }

  static final List<CachedResource<dynamic>> _all = [];

  /// 다음 조회 때 서버에 다시 묻게 한다(값과 etag는 남겨 304를 받을 수 있게).
  static void invalidateAll() {
    for (final resource in _all) {
      resource._fetchedAt = null;
    }
  }

  /// 로그아웃·탈퇴. 계정마다 응답이 달라서 전부 버린다.
  static void clearAll() {
    for (final resource in _all) {
      resource._clear();
    }
  }

  final Future<Conditional<T>> Function(String? etag) _fetch;
  final Duration ttl;

  T? _value;
  String? _etag;
  DateTime? _fetchedAt;
  Future<T>? _inFlight;

  /// [_clear]마다 올라간다. 그 전에 나간 요청의 응답은 저장하지 않는다.
  int _generation = 0;

  /// [refresh]면 기억한 값이 있어도 서버에 다시 묻는다(당겨서 새로고침).
  Future<T> get({bool refresh = false}) {
    final running = _inFlight;
    if (running != null) return running;

    final value = _value;
    final fetchedAt = _fetchedAt;
    if (!refresh &&
        value != null &&
        fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < ttl) {
      return Future.value(value);
    }

    late final Future<T> request;
    request = _load().whenComplete(() {
      if (identical(_inFlight, request)) _inFlight = null;
    });
    return _inFlight = request;
  }

  Future<T> _load() async {
    final generation = _generation;
    final held = _value;
    final result = await _fetch(held == null ? null : _etag);

    final T value;
    if (result.notModified && held != null) {
      value = held;
    } else {
      value = result.data as T;
    }
    if (generation == _generation) {
      _value = value;
      if (!result.notModified) _etag = result.etag;
      _fetchedAt = DateTime.now();
    }
    return value;
  }

  void _clear() {
    _generation++;
    _value = null;
    _etag = null;
    _fetchedAt = null;
    _inFlight = null;
  }
}
