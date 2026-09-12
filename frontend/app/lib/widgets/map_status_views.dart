import 'package:flutter/material.dart';
import 'package:kakao_map_sdk/kakao_map_sdk.dart' as kakao;
import '../theme/app_theme.dart';

/// 지도를 못 그릴 때 대신 보여주는 화면들.
///
/// 지도를 쓰는 위젯이 둘([RunMapView], [CourseMapView])이고 실패 원인은 똑같이
/// 앱 키와 SDK 인증이라, 안내도 한 벌만 둔다.

/// 지도를 어디에 놓을지 아직 모를 때(=현위치 조회 중) 보여주는 자리.
///
/// 임시 좌표로 지도를 먼저 띄우지 않는다. 카카오맵은 생성할 때 받은 중심을 한
/// 번만 읽어서, 임시로 띄우면 좌표가 도착한 뒤 카메라를 다시 옮겨야 하고 그
/// 이동이 화면에서 점프로 보인다.
class MapLoadingView extends StatelessWidget {
  const MapLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.surfaceMuted,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(height: 14),
            Text(
              '현재 위치를 찾고 있어요',
              style: TextStyle(fontSize: 13, color: AppColors.iconSubtle),
            ),
          ],
        ),
      ),
    );
  }
}

/// 그릴 것이 아무것도 없을 때. 좌표가 한 점도 없는 러닝 기록이 여기 걸린다
/// (첫 GPS가 잡히기 전에 끝낸 러닝 — [RunTracker.buildRecord]는 막지 않는다).
///
/// 예전에는 이럴 때 제주시청 지도를 띄웠는데, 아무 관계 없는 동네를 보여주느니
/// 그릴 게 없다고 말하는 편이 낫다.
class MapEmptyView extends StatelessWidget {
  const MapEmptyView({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.surfaceMuted,
      child: Center(
        child: Text(
          '표시할 경로가 없어요',
          style: TextStyle(fontSize: 13, color: AppColors.iconSubtle),
        ),
      ),
    );
  }
}

/// 카카오 앱 키 없이 빌드했을 때 지도 대신 보여주는 안내.
class MissingMapKeyPlaceholder extends StatelessWidget {
  const MissingMapKeyPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surfaceMuted,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.map_outlined,
                size: 40,
                color: AppColors.textSubtle,
              ),
              const SizedBox(height: 12),
              Text(
                '지도를 표시하려면 카카오 앱 키가 필요해요',
                style: Theme.of(context).textTheme.titleSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              const Text(
                'config/app_config.dart의 kakaoNativeAppKey가 비어 있어요',
                style: TextStyle(fontSize: 11, color: AppColors.iconSubtle),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 지도 SDK가 오류를 낸 경우 빈 화면 대신 원인과 조치를 보여준다.
class MapErrorView extends StatelessWidget {
  const MapErrorView({super.key, required this.error, this.keyHash});

  final Object error;

  /// 안드로이드에서 이 앱이 실제로 쓰는 키 해시. 인증 실패는 대개 이 값이
  /// 콘솔에 등록되지 않아서 나므로, 바로 복사해 등록할 수 있게 보여준다.
  final String? keyHash;

  @override
  Widget build(BuildContext context) {
    final hash = keyHash;

    return ColoredBox(
      color: AppColors.surfaceMuted,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 40,
                color: AppColors.textSubtle,
              ),
              const SizedBox(height: 12),
              Text(
                '지도를 불러오지 못했어요',
                style: Theme.of(context).textTheme.titleSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _reason,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.iconSubtle,
                ),
                textAlign: TextAlign.center,
              ),
              if (hash != null) ...[
                const SizedBox(height: 16),
                const Text(
                  '이 앱의 키 해시',
                  style: TextStyle(fontSize: 11, color: AppColors.iconSubtle),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  hash,
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: Color(0xFF2B3138),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 16),
              Text(
                '$error',
                style: const TextStyle(fontSize: 10, color: Color(0xFF8A929E)),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 오류를 "무엇을 해야 하는지"가 드러나는 문장으로 바꾼다.
  String get _reason {
    final e = error;

    if (e is kakao.KakaoAuthError) {
      return switch (e.code) {
        400 => '요청에 필요한 정보가 빠졌어요.',
        401 => '앱 키가 올바르지 않아요.\nAppConfig.kakaoNativeAppKey를 확인해 주세요.',
        403 =>
          '이 앱에 카카오맵 사용 권한이 없어요.\n콘솔에서 카카오맵 약관 동의와 '
              '플랫폼 등록(패키지명·키 해시)을 확인해 주세요.',
        429 => '카카오맵 사용량을 초과했어요.\n잠시 후 다시 시도해 주세요.',
        499 => '네트워크에 연결하지 못했어요.',
        _ => e.message ?? '알 수 없는 인증 오류예요.',
      };
    }

    if (e is kakao.KakaoMapError) {
      return e.message ?? e.className;
    }

    return '$e';
  }
}
