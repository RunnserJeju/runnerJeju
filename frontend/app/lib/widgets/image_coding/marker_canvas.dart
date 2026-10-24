import 'dart:ui' as ui;

import 'package:flutter/material.dart';
// 카카오맵 SDK는 머티리얼과 겹치는 이름을 내보내므로 접두사를 붙인다.
import 'package:kakao_map_sdk/kakao_map_sdk.dart' as kakao;

/// 지도 마커 비트맵을 화면 크기(dp)보다 이만큼 크게 그린다. 고밀도 화면에서
/// 가장자리가 뭉개지지 않게 하려는 것이다.
const double kMarkerPixelRatio = 3;

/// dp 크기 [width]×[height]짜리 마커를 [draw]로 그려 카카오맵 이미지로 만든다.
/// [draw]가 받는 캔버스의 좌표계는 dp다. 마커를 그리는 곳이 여럿이라 래스터화
/// 절차(녹화 → 확대 → PNG → 해제)는 여기 한 곳에만 둔다.
Future<kakao.KImage> rasterizeMarker({
  required double width,
  required double height,
  required void Function(Canvas canvas) draw,
}) async {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder)..scale(kMarkerPixelRatio));

  final image = await recorder.endRecording().toImage(
    (width * kMarkerPixelRatio).round(),
    (height * kMarkerPixelRatio).round(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();

  return kakao.KImage.fromData(
    data!.buffer.asUint8List(),
    width.round(),
    height.round(),
  );
}
