import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 서비스 계층 예외의 베이스.
///
/// 기본은 이 클래스를 그대로 쓴다 — 화면에 보여줄 [message]와 디버깅용 원인
/// [cause]면 대부분의 실패를 표현하기에 충분하다:
///
/// ```dart
/// throw AppException('코스 목록을 불러오지 못했어요.', e);
/// ```
///
/// 호출부에서 `on XxxException`으로 구분해 잡아야 할 때만 상속해서 구체화한다.
/// 구분할 이유가 없다면 이름만 다른 클래스를 늘리지 않는다:
///
/// ```dart
/// class SessionExpiredException extends AppException {
///   SessionExpiredException([Object? cause]) : super('다시 로그인해 주세요.', cause);
/// }
/// ```
class AppException implements Exception {
  AppException(this.message, [this.cause]) {
    final detail = describeCause(cause);
    if (detail != null) {
      // 하위 클래스면 그 이름으로 찍힌다.
      debugPrint('$runtimeType: $message ← $detail');
    }
  }

  final String message;
  final Object? cause;

  /// 화면에는 이 값을 보여준다 — 원인까지 포함해서 디버깅 중엔 바로 확인할 수 있다.
  @override
  String toString() {
    final detail = describeCause(cause);
    return detail == null ? message : '$message\n($detail)';
  }
}

/// [cause]를 사람이 읽을 수 있는 문자열로 풀어준다 — 화면/로그에서 타임아웃, 상태
/// 코드 같은 실제 원인을 바로 보려는 목적. cause가 없으면 null.
String? describeCause(Object? cause) {
  if (cause == null) return null;
  if (cause is PlatformException) {
    return 'PlatformException(code: ${cause.code}, message: ${cause.message}, '
        'details: ${cause.details})';
  }
  if (cause is DioException) {
    return 'DioException(type: ${cause.type}, status: ${cause.response?.statusCode}, '
        'body: ${cause.response?.data}, message: ${cause.message})';
  }
  return cause.toString();
}
