import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
// 카카오맵 SDK는 머티리얼과 겹치는 이름을 내보내므로 접두사를 붙인다.
import 'package:kakao_map_sdk/kakao_map_sdk.dart' as kakao;

import '../../theme/app_theme.dart';
import 'marker_canvas.dart';

/// 내 현위치 점. 러닝 탭 지도(CourseMapView)와 달리기 지도(RunMapView)가 같은
/// 모양을 쓴다. 좌표 정중앙에 놓으므로 PoiStyle의 anchor를 (0.5, 0.5)로 준다.
///
/// 도안은 SVG 에셋이고 카카오맵은 비트맵만 받으므로 처음 한 번 그려서 PNG로
/// 넘긴다. 두 지도가 같은 결과를 쓰도록 Future를 캐시한다.
///
/// 달리기 지도는 원을 1dp 작게 쓰고, 방향을 알면 원 바깥에 삼각형을 붙인
/// 판([buildRunHeadingMarker])으로 바꿔 끼운다.

/// 마커 한 변(dp).
const double myPositionMarkerSize = 21;

/// 달리기 지도의 원 지름(dp).
const double runPositionMarkerSize = 20;

const String _asset = 'assets/icons/my_position.svg';

// 방향 삼각형(dp). 원 가장자리에서 [_triangleGap]만큼 띄워 붙인다.
const double _triangleBase = 9;
const double _triangleHeight = 6;
const double _triangleGap = 2;

/// 방향 판의 한 변. 원 중심이 판 중심이어야 회전해도 원이 제자리에 있으므로,
/// 삼각형 끝(+외곽선 여유 1)까지를 반지름으로 잡은 정사각형이다.
const double _headingCanvasSize =
    2 * (runPositionMarkerSize / 2 + _triangleGap + _triangleHeight + 1);

Future<kakao.KImage>? _cached;
Future<kakao.KImage>? _cachedRun;
Future<kakao.KImage>? _cachedRunHeading;

Future<kakao.KImage> buildMyPositionMarker() =>
    _cached ??= _buildDot(myPositionMarkerSize, withHeading: false);

/// 달리기 지도의 방향 모르는 현위치(원만).
Future<kakao.KImage> buildRunPositionMarker() =>
    _cachedRun ??= _buildDot(runPositionMarkerSize, withHeading: false);

/// 달리기 지도의 방향 아는 현위치. 삼각형이 위(북쪽)를 가리키게 그려 두고,
/// 지도가 Poi를 방향만큼 돌린다.
Future<kakao.KImage> buildRunHeadingMarker() =>
    _cachedRunHeading ??= _buildDot(runPositionMarkerSize, withHeading: true);

Future<kakao.KImage> _buildDot(
  double dotSize, {
  required bool withHeading,
}) async {
  final info = await vg.loadPicture(const SvgAssetLoader(_asset), null);
  final canvasSize = withHeading ? _headingCanvasSize : dotSize;
  try {
    return await rasterizeMarker(
      width: canvasSize,
      height: canvasSize,
      draw: (canvas) {
        if (withHeading) _drawTriangle(canvas, canvasSize / 2, dotSize / 2);
        final offset = (canvasSize - dotSize) / 2;
        canvas
          ..save()
          ..translate(offset, offset)
          ..scale(dotSize / info.size.width, dotSize / info.size.height)
          ..drawPicture(info.picture)
          ..restore();
      },
    );
  } finally {
    info.picture.dispose();
  }
}

/// 원과 같은 빨강 + 흰 외곽선. 지도 위 어떤 바탕에서도 원과 한 몸으로 보이게.
void _drawTriangle(Canvas canvas, double center, double dotRadius) {
  final tipY = center - dotRadius - _triangleGap - _triangleHeight;
  final baseY = center - dotRadius - _triangleGap;
  final path = Path()
    ..moveTo(center, tipY)
    ..lineTo(center + _triangleBase / 2, baseY)
    ..lineTo(center - _triangleBase / 2, baseY)
    ..close();
  canvas
    ..drawPath(path, Paint()..color = AppColors.danger)
    ..drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..strokeJoin = StrokeJoin.round,
    );
}
