/// 서비스 계층 예외의 공통 인터페이스.
///
/// 각 서비스가 원인 예외(cause)를 통일된 방식으로 들고 있게 해서, AsyncView 같은
/// 공용 위젯이 어떤 서비스에서 온 에러인지 몰라도 원인(예: 401)을 꺼내볼 수 있다.
abstract interface class AppException implements Exception {
  String get message;
  Object? get cause;
}
