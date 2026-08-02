import 'package:flutter/services.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../api/auth_api.dart' as api;
import '../exceptions/app_exception.dart';
import 'token_storage.dart';

/// 비즈니스 로직 계층: 카카오 SDK 로그인 → 우리 서버 JWT 교환 → 토큰 저장.
class AuthService {
  AuthService(this._authApi, this._tokenStorage);

  final api.AuthApi _authApi;
  final TokenStorage _tokenStorage;

  Future<bool> get isLoggedIn async =>
      await _tokenStorage.readAccessToken() != null;

  /// 카카오톡 앱이 있으면 앱 전환 로그인, 없으면 카카오계정(웹뷰) 로그인으로 자동 대체한다.
  Future<void> loginWithKakao() async {
    OAuthToken kakaoToken;

    try {
      if (await isKakaoTalkInstalled()) {
        try {
          kakaoToken = await UserApi.instance.loginWithKakaoTalk();
        } on PlatformException catch (e) {
          if (e.code == 'CANCELED') {
            throw AppException('로그인이 취소됐어요.');
          }
          kakaoToken = await UserApi.instance.loginWithKakaoAccount();
        }
      } else {
        kakaoToken = await UserApi.instance.loginWithKakaoAccount();
      }
    } on AppException {
      rethrow;
    } catch (e) {
      // 이 구간은 카카오 SDK가 카카오 서버와 직접 통신하는 단계라 우리 백엔드 로그에는
      // 아무것도 남지 않는다. 키 해시 미등록(KOE101) 같은 원인이 여기서 잡힌다.
      throw AppException('카카오 로그인에 실패했어요.', e);
    }

    try {
      final tokens = await _authApi.loginWithKakao(kakaoToken.accessToken);
      await _tokenStorage.save(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
    } catch (e) {
      throw AppException('서버 로그인에 실패했어요.', e);
    }
  }

  /// iOS 전용. 앱스토어 심사 가이드라인(4.8) 대응으로 iOS에서만 노출한다.
  Future<void> loginWithApple() async {
    AuthorizationCredentialAppleID credential;
    try {
      credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw AppException('로그인이 취소됐어요.');
      }
      throw AppException('애플 로그인에 실패했어요.', e);
    } catch (e) {
      throw AppException('애플 로그인에 실패했어요.', e);
    }

    final identityToken = credential.identityToken;
    if (identityToken == null) {
      throw AppException('애플 로그인에 실패했어요.');
    }

    // 이름은 애플이 최초 인가 시에만 내려준다. 이후 로그인부터는 null이라
    // 서버에 매번 새로 저장하지 않는다.
    final fullName = [
      credential.givenName,
      credential.familyName,
    ].whereType<String>().join(' ').trim();

    try {
      final tokens = await _authApi.loginWithApple(
        identityToken,
        email: credential.email,
        fullName: fullName.isEmpty ? null : fullName,
      );
      await _tokenStorage.save(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
    } catch (e) {
      throw AppException('서버 로그인에 실패했어요.', e);
    }
  }

  Future<void> logout() async {
    final refreshToken = await _tokenStorage.readRefreshToken();
    if (refreshToken != null) {
      try {
        await _authApi.logout(refreshToken);
      } catch (_) {
        // 서버 폐기가 실패해도 로컬 토큰은 지운다 — 어차피 곧 만료된다.
      }
    }
    await _tokenStorage.clear();
  }
}
