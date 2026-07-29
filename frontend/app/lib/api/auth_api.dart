import '../network/api_client.dart';

class TokenPair {
  const TokenPair({required this.accessToken, required this.refreshToken});

  factory TokenPair.fromJson(Map<String, dynamic> json) => TokenPair(
    accessToken: json['access_token'] as String,
    refreshToken: json['refresh_token'] as String,
  );

  final String accessToken;
  final String refreshToken;
}

/// API 계층: 인증 관련 서버 엔드포인트.
class AuthApi {
  AuthApi(this._client);

  final ApiClient _client;

  /// 카카오 SDK 로그인으로 받은 accessToken을 서버에 보내 우리 서비스의 JWT를 받는다.
  Future<TokenPair> loginWithKakao(String kakaoAccessToken) async {
    final response = await _client.dio.post(
      '/auth/kakao',
      data: {'access_token': kakaoAccessToken},
    );
    return TokenPair.fromJson(response.data as Map<String, dynamic>);
  }

  Future<String> refresh(String refreshToken) async {
    final response = await _client.dio.post(
      '/auth/refresh',
      data: {'refresh_token': refreshToken},
    );
    return (response.data as Map<String, dynamic>)['access_token'] as String;
  }

  Future<void> logout(String refreshToken) {
    return _client.dio.post('/auth/logout', data: {'refresh_token': refreshToken});
  }
}
