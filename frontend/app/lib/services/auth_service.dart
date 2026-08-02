import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
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
  ///
  /// 반환값 true면 아직 닉네임이 없다는 뜻 — 호출부가 닉네임 설정 화면으로 보내야 한다.
  Future<bool> loginWithKakao() async {
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
      return tokens.needsNickname;
    } catch (e) {
      throw AppException('서버 로그인에 실패했어요.', e);
    }
  }

  /// iOS 전용. 앱스토어 심사 가이드라인(4.8) 대응으로 iOS에서만 노출한다.
  ///
  /// 반환값 true면 아직 닉네임이 없다는 뜻 — 호출부가 닉네임 설정 화면으로 보내야 한다.
  Future<bool> loginWithApple() async {
    AuthorizationCredentialAppleID credential;
    try {
      credential = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email],
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

    try {
      final tokens = await _authApi.loginWithApple(
        identityToken,
        email: credential.email,
      );
      await _tokenStorage.save(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
      return tokens.needsNickname;
    } catch (e) {
      throw AppException('서버 로그인에 실패했어요.', e);
    }
  }

  /// 구글 계정 선택 UI를 띄우고, idToken을 서버에 보내 로그인한다.
  ///
  /// 반환값 true면 아직 닉네임이 없다는 뜻 — 호출부가 닉네임 설정 화면으로 보내야 한다.
  Future<bool> loginWithGoogle() async {
    String? idToken;
    try {
      final account = await GoogleSignIn.instance.authenticate();
      idToken = account.authentication.idToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw AppException('로그인이 취소됐어요.');
      }
      throw AppException('구글 로그인에 실패했어요.', e);
    } catch (e) {
      throw AppException('구글 로그인에 실패했어요.', e);
    }

    if (idToken == null) {
      throw AppException('구글 로그인에 실패했어요.');
    }

    try {
      final tokens = await _authApi.loginWithGoogle(idToken);
      await _tokenStorage.save(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
      return tokens.needsNickname;
    } catch (e) {
      throw AppException('서버 로그인에 실패했어요.', e);
    }
  }

  /// 닉네임 설정 화면에서 호출한다.
  Future<void> setNickname(String nickname) async {
    try {
      await _authApi.updateNickname(nickname);
    } catch (e) {
      throw AppException('닉네임을 저장하지 못했어요.', e);
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
