import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
// 카카오맵 SDK는 머티리얼과 겹치는 이름을 내보내므로 접두사를 붙인다.
import 'package:kakao_map_sdk/kakao_map_sdk.dart' as kakao;

/// 내 현위치 점. 러닝 탭 지도(CourseMapView)와 달리기 지도(RunMapView)가 같은
/// 모양을 쓴다. 좌표 정중앙에 놓으므로 PoiStyle의 anchor를 (0.5, 0.5)로 준다.
///
/// 도안은 SVG 에셋이고 카카오맵은 비트맵만 받으므로 처음 한 번 그려서 PNG로
/// 넘긴다. 두 지도가 같은 결과를 쓰도록 Future를 캐시한다.

/// 마커 한 변(dp).
const int myPositionMarkerSize = 21;

const String _asset = 'assets/icons/my_position.svg';
const double _pixelRatio = 3;

Future<kakao.KImage>? _cached;

Future<kakao.KImage> buildMyPositionMarker() => _cached ??= _build();

Future<kakao.KImage> _build() async {
  final info = await vg.loadPicture(const SvgAssetLoader(_asset), null);

  final px = (myPositionMarkerSize * _pixelRatio).round();
  final recorder = ui.PictureRecorder();
  Canvas(recorder)
    ..scale(px / info.size.width, px / info.size.height)
    ..drawPicture(info.picture);

  final image = await recorder.endRecording().toImage(px, px);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  info.picture.dispose();

  return kakao.KImage.fromData(
    data!.buffer.asUint8List(),
    myPositionMarkerSize,
    myPositionMarkerSize,
  );
}
