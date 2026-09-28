import 'dart:ui' as ui;

import 'package:flutter/material.dart';
// 카카오맵 SDK는 머티리얼과 겹치는 이름을 내보내므로 접두사를 붙인다.
import 'package:kakao_map_sdk/kakao_map_sdk.dart' as kakao;

import '../models/course_partner.dart';
import 'marker_canvas.dart';

/// 협력업체 지도 마커: 업종 색 핀 머리에 흰 업종 아이콘을 새긴다.
///
/// 주차장/화장실(작은 원형 배지)이나 코스 핀(검정 핀 + 흰 점)과 한눈에 구별되도록
/// 핀 모양에 글리프를 넣었다. 에셋 대신 그리는 이유는 코스 핀과 같다 — 업종 × 선택
/// 여부 조합마다 PNG를 두면 관리할 벌이 늘어난다.
///
/// 코스 선택 지도(CourseMapView)와 달리기 지도(RunMapView)가 같이 쓴다. 핀 끝이
/// 좌표에 놓이도록 PoiStyle의 anchor는 (0.5, 1.0)으로 준다([partnerPinAnchor]).

const kakao.KPoint partnerPinAnchor = kakao.KPoint(0.5, 1.0);

const double _width = 30;
const double _height = 38;
const double _selectedWidth = 38;
const double _selectedHeight = 48;
const double _border = 2;

final _cache = <String, Future<kakao.KImage>>{};

/// [category] 업종 핀. [selected]면 한 단계 크게 그린다(목록/지도에서 고른 업체).
Future<kakao.KImage> buildPartnerPin(
  PartnerCategory category, {
  bool selected = false,
}) => _cache['${category.wire}|$selected'] ??= _build(category, selected);

Future<kakao.KImage> _build(PartnerCategory category, bool selected) {
  final w = selected ? _selectedWidth : _width;
  final h = selected ? _selectedHeight : _height;
  final radius = w / 2 - _border;
  final center = Offset(w / 2, radius + _border);

  final glyph = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(category.icon.codePoint),
      style: TextStyle(
        fontFamily: category.icon.fontFamily,
        package: category.icon.fontPackage,
        fontSize: radius * 1.15,
        color: Colors.white,
        height: 1.0,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  return rasterizeMarker(
    width: w,
    height: h,
    draw: (canvas) {
      // 머리(원)와 꼬리(삼각형)를 합쳐 하나의 외곽선으로 — 겹친 자리에 흰 테두리가
      // 가로지르지 않게(코스 핀과 같은 방식).
      final head = Path()..addOval(Rect.fromCircle(center: center, radius: radius));
      final tail = Path()
        ..moveTo(center.dx - radius * 0.6, center.dy + radius * 0.6)
        ..lineTo(center.dx, h - _border / 2)
        ..lineTo(center.dx + radius * 0.6, center.dy + radius * 0.6)
        ..close();
      final pin = Path.combine(ui.PathOperation.union, head, tail);

      canvas.drawShadow(pin, Colors.black, 2, false);
      canvas.drawPath(pin, Paint()..color = category.tint);
      canvas.drawPath(
        pin,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = _border,
      );
      glyph.paint(canvas, center - Offset(glyph.width / 2, glyph.height / 2));
    },
  );
}

/// 핀 아래 업체 이름 글씨. 지도 위 글씨라 흰 외곽선을 둘러 어느 지형에서든 읽힌다.
const List<kakao.PoiTextStyle> partnerLabelStyle = [
  kakao.PoiTextStyle(size: 12, color: Color(0xFF0D0D0D), stroke: 3, strokeColor: Colors.white),
];
