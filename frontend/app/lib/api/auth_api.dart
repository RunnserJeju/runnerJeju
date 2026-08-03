import '../models/user.dart';
import '../network/api_client.dart';

class TokenPair {
  const TokenPair({
    required this.accessToken,
    required this.refreshToken,
    required this.needsNickname,
  });

  factory TokenPair.fromJson(Map<String, dynamic> json) => TokenPair(
    accessToken: json['access_token'] as String,
    refreshToken: json['refresh_token'] as String,
    needsNickname: json['needs_nickname'] as bool,
  );

  final String accessToken;
  final String refreshToken;

  /// true면 아직 닉네임이 없다는 뜻 — 클라이언트가 닉네임 설정 화면으로 보내야 한다.
  final bool needsNickname;
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

  /// Sign in with Apple로 받은 identityToken을 서버에 보내 우리 서비스의 JWT를 받는다.
  ///
  /// email은 애플이 최초 인가 시에만 내려주므로, 받았을 때만 함께 보낸다.
  Future<TokenPair> loginWithApple(String identityToken, {String? email}) async {
    final response = await _client.dio.post(
      '/auth/apple',
      data: {
        'identity_token': identityToken,
        'email': ?email,
      },
    );
    return TokenPair.fromJson(response.data as Map<String, dynamic>);
  }

  /// Google Sign-In으로 받은 idToken을 서버에 보내 우리 서비스의 JWT를 받는다.
  Future<TokenPair> loginWithGoogle(String idToken) async {
    final response = await _client.dio.post(
      '/auth/google',
      data: {'id_token': idToken},
    );
    return TokenPair.fromJson(response.data as Map<String, dynamic>);
  }

  /// 현재 로그인한 사용자. role이 담겨 있어 admin 전용 UI 판단에 쓴다.
  Future<User> fetchMe() async {
    final response = await _client.dio.get('/auth/me');
    return User.fromJson(response.data as Map<String, dynamic>);
  }

  /// 로그인 직후(닉네임 없을 때) 닉네임 설정 화면에서 호출한다.
  Future<void> updateNickname(String nickname) {
    return _client.dio.patch('/auth/nickname', data: {'nickname': nickname});
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
