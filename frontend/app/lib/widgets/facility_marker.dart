import 'dart:ui' as ui;

import 'package:flutter/material.dart';
// 카카오맵 SDK는 머티리얼과 겹치는 이름을 내보내므로 접두사를 붙인다.
import 'package:kakao_map_sdk/kakao_map_sdk.dart' as kakao;

/// 코스 주차장/화장실을 지도에 찍는 원형 배지.
///
/// 러닝 탭 지도(CourseMapView)와 달리기 지도(RunMapView)가 같은 모양을 써야 해서
/// 여기로 뺐다. 배지는 좌표 정중앙에 놓으므로 PoiStyle의 anchor를 (0.5, 0.5)로 준다.

/// 주차장(파랑) / 화장실(초록) 배지 색.
const Color parkingBadgeColor = Color(0xFF2F6BFF);
const Color restroomBadgeColor = Color(0xFF12B886);

/// 배지에 새길 짧은 글자.
const String parkingBadgeLabel = 'P';
const String restroomBadgeLabel = 'WC';

const int _badgeSize = 22;
const double _badgeBorder = 2;
const double _badgePixelRatio = 3;

/// 원형 배지 이미지를 그린다. 에셋 대신 그려서 색·글자만 바꿔 쓴다(코스 핀과 같은 이유).
Future<kakao.KImage> buildFacilityBadge(Color color, String label) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(_badgePixelRatio);

  final s = _badgeSize.toDouble();
  final center = Offset(s / 2, s / 2);
  final radius = s / 2 - _badgeBorder;

  canvas.drawCircle(center, radius, Paint()..color = color);
  canvas.drawCircle(
    center,
    radius,
    Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = _badgeBorder,
  );

  final painter = TextPainter(
    text: TextSpan(
      text: label,
      style: TextStyle(
        color: Colors.white,
        fontSize: label.length > 1 ? 9 : 12,
        fontWeight: FontWeight.w800,
        height: 1.0,
      ),
    ),
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));

  final image = await recorder.endRecording().toImage(
    (s * _badgePixelRatio).round(),
    (s * _badgePixelRatio).round(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();

  return kakao.KImage.fromData(data!.buffer.asUint8List(), _badgeSize, _badgeSize);
}
