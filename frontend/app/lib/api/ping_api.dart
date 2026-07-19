import '../network/api_client.dart';
/*
  FastAPI 서버의 api와 짝을 이루는 interface정의
*/
class PingResponse {
  PingResponse({required this.message});

  final String message;

  factory PingResponse.fromJson(Map<String, dynamic> json) =>
      PingResponse(message: json['message'] as String);
}

/// API 계층: 서버 엔드포인트 1개당 메서드 1개. 여기 없는 호출은 존재하지 않는다.
class PingApi {
  PingApi(this._client);

  final ApiClient _client;

  Future<PingResponse> ping() async {
    final response = await _client.dio.get('/ping');
    return PingResponse.fromJson(response.data as Map<String, dynamic>);
  }
}
