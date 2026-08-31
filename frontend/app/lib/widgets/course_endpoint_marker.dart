import 'dart:ui' as ui;

import 'package:flutter/material.dart';
// 카카오맵 SDK는 머티리얼과 겹치는 이름을 내보내므로 접두사를 붙인다.
import 'package:kakao_map_sdk/kakao_map_sdk.dart' as kakao;

import '../theme/app_theme.dart';

/// 코스 시작/끝점에 찍는 알약 모양 배지. 시설 배지처럼 CourseMapView와
/// RunMapView가 같은 모양을 써야 해서 여기로 뺐다. 좌표 정중앙에 놓으므로
/// PoiStyle의 anchor를 (0.5, 0.5)로 준다.

const Color startEndpointColor = AppColors.success;
const Color finishEndpointColor = AppColors.ink;

const String startEndpointLabel = '출발';
const String finishEndpointLabel = '도착';

/// 순환 코스에 하나만 찍을 때의 라벨. 색은 시작 배지를 따른다.
const String loopEndpointLabel = '왕복';

/// 시작점과 끝점이 이보다 가까우면(m) 순환 코스로 보고 배지를 하나만 찍는다.
const double loopEndpointThresholdMeters = 30;

const double _chipHeight = 20;
const double _chipHPadding = 8;
const double _chipBorder = 2;
const double _chipPixelRatio = 3;

/// 알약 배지 이미지를 그린다. 폭은 글자 길이에 맞춘다.
Future<kakao.KImage> buildCourseEndpointChip(Color color, String label) async {
  final painter = TextPainter(
    text: TextSpan(
      text: label,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        height: 1.0,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  final w = (painter.width + _chipHPadding * 2 + _chipBorder * 2).ceilToDouble();
  const h = _chipHeight;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(_chipPixelRatio);

  final chip = RRect.fromRectAndRadius(
    Rect.fromLTWH(
      _chipBorder / 2,
      _chipBorder / 2,
      w - _chipBorder,
      h - _chipBorder,
    ),
    const Radius.circular(h / 2),
  );
  canvas.drawRRect(chip, Paint()..color = color);
  canvas.drawRRect(
    chip,
    Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = _chipBorder,
  );
  painter.paint(
    canvas,
    Offset((w - painter.width) / 2, (h - painter.height) / 2),
  );

  final image = await recorder.endRecording().toImage(
    (w * _chipPixelRatio).round(),
    (h * _chipPixelRatio).round(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();

  return kakao.KImage.fromData(
    data!.buffer.asUint8List(),
    w.round(),
    h.round(),
  );
}
