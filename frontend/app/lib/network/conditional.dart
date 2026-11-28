/// 변경 확인 요청(If-None-Match)의 결과. 서버가 304면 [data] 없이 [notModified]만 참.
class Conditional<T> {
  const Conditional(T this.data, this.etag) : notModified = false;
  const Conditional.notModified()
    : data = null,
      etag = null,
      notModified = true;

  final T? data;
  final String? etag;
  final bool notModified;
}
