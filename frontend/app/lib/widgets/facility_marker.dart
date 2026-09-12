import 'package:flutter/material.dart';
// 카카오맵 SDK는 머티리얼과 겹치는 이름을 내보내므로 접두사를 붙인다.
import 'package:kakao_map_sdk/kakao_map_sdk.dart' as kakao;

import 'marker_canvas.dart';

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

const double _badgeSize = 22;
const double _badgeBorder = 2;

final _cache = <String, Future<kakao.KImage>>{};

/// 원형 배지 이미지. 에셋 대신 그려서 색·글자만 바꿔 쓴다(코스 핀과 같은 이유).
/// 종류가 둘뿐이라 색·라벨별로 한 번만 그려 두고 재사용한다.
Future<kakao.KImage> buildFacilityBadge(Color color, String label) =>
    _cache['${color.toARGB32()}|$label'] ??= _build(color, label);

Future<kakao.KImage> _build(Color color, String label) {
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

  return rasterizeMarker(
    width: _badgeSize,
    height: _badgeSize,
    draw: (canvas) {
      const center = Offset(_badgeSize / 2, _badgeSize / 2);
      const radius = _badgeSize / 2 - _badgeBorder;
      canvas.drawCircle(center, radius, Paint()..color = color);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = _badgeBorder,
      );
      painter.paint(
        canvas,
        center - Offset(painter.width / 2, painter.height / 2),
      );
    },
  );
}
