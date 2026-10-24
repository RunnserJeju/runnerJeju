import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
// 카카오맵 SDK는 머티리얼과 겹치는 이름을 내보내므로 접두사를 붙인다.
import 'package:kakao_map_sdk/kakao_map_sdk.dart' as kakao;

import '../../models/course_partner.dart';
import '../../models/running_course.dart';
import '../../theme/app_theme.dart';
import 'marker_canvas.dart';

/// 코스·협력업체 말풍선 마커: 둥근 아이콘 + 이름을 담은 알약 모양에 아래 꼬리.
///
/// 이름이 그림 안에 들어가므로 마커마다 이미지가 다르다. 같은 이름·선택 여부는
/// 한 번만 그린다. 꼬리 끝이 좌표에 놓이도록 anchor는 [bubbleMarkerAnchor].
/// 코스 선택 지도(CourseMapView)와 달리기 지도(RunMapView)가 같이 쓴다.

const kakao.KPoint bubbleMarkerAnchor = kakao.KPoint(0.5, 1.0);

/// 이름 최대 글자 수. 넘으면 잘라서 말줄임표를 붙인다.
const int bubbleMaxChars = 16;

const double _height = 22;
const double _selectedHeight = 26;
const double _iconInset = 2.5;
const double _gap = 4;
const double _paddingRight = 8;
const double _tailWidth = 7;
const double _tailHeight = 4;

/// 그림자가 잘리지 않게 위·좌우로 남기는 여백. 아래는 꼬리 끝이 좌표라 두지 않는다.
const double _margin = 3;

final _cache = <String, Future<kakao.KImage>>{};
typedef _IconPainter = void Function(Canvas canvas, Rect rect);

final _assetIcons = <String, Future<_IconPainter>>{};

String bubbleLabel(String name) {
  final chars = name.trim().characters;
  return chars.length <= bubbleMaxChars
      ? chars.toString()
      : '${chars.take(bubbleMaxChars)}…';
}

/// 코스 말풍선. 아이콘은 카테고리별 에셋.
Future<kakao.KImage> buildCourseBubble(
  RunningCourse course, {
  bool selected = false,
}) {
  final asset = course.category.markerIcon;
  final label = bubbleLabel(course.name);
  return _cache['course|$asset|$label|$selected'] ??= _loadIcon(
    asset,
  ).then((drawIcon) => _build(label, selected, drawIcon));
}

/// 협력업체 말풍선. 아이콘은 업종 색 원에 흰 업종 글리프.
Future<kakao.KImage> buildPartnerBubble(
  CoursePartner partner, {
  bool selected = false,
}) {
  final category = partner.category;
  final label = bubbleLabel(partner.name);
  return _cache['partner|${category.wire}|$label|$selected'] ??= _build(
    label,
    selected,
    (canvas, rect) {
      canvas.drawCircle(
        rect.center,
        rect.width / 2,
        Paint()..color = category.tint,
      );
      final glyph = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(category.icon.codePoint),
          style: TextStyle(
            fontFamily: category.icon.fontFamily,
            package: category.icon.fontPackage,
            fontSize: rect.width * 0.62,
            color: Colors.white,
            height: 1.0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      glyph.paint(
        canvas,
        rect.center - Offset(glyph.width / 2, glyph.height / 2),
      );
    },
  );
}

/// 에셋 아이콘을 [rect]에 맞춰 그리는 함수. SVG는 벡터라 크기와 상관없이 선명하고,
/// PNG는 원본 픽셀을 늘리므로 그리는 크기의 3배(kMarkerPixelRatio) 이상이어야 또렷하다.
/// 읽지 못하면 아이콘 자리를 비운 채 그린다 — 아이콘 하나 때문에 코스 마커가
/// 통째로 안 찍히지 않게. 실패는 캐시하지 않아 다음에 다시 읽는다.
Future<_IconPainter> _loadIcon(String path) => _assetIcons[path] ??=
    (path.endsWith('.svg') ? _loadSvg(path) : _loadPng(path)).catchError((
      Object error,
    ) {
      debugPrint('마커 아이콘을 읽지 못함 $path: $error');
      _assetIcons.remove(path);
      return (Canvas canvas, Rect rect) {};
    });

Future<_IconPainter> _loadSvg(String path) async {
  final info = await vg.loadPicture(SvgAssetLoader(path), null);
  return (canvas, rect) => canvas
    ..save()
    ..translate(rect.left, rect.top)
    ..scale(rect.width / info.size.width, rect.height / info.size.height)
    ..drawPicture(info.picture)
    ..restore();
}

Future<_IconPainter> _loadPng(String path) async {
  final data = await rootBundle.load(path);
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  final image = (await codec.getNextFrame()).image;
  final source = Rect.fromLTWH(
    0,
    0,
    image.width.toDouble(),
    image.height.toDouble(),
  );
  return (canvas, rect) => canvas.drawImageRect(
    image,
    source,
    rect,
    Paint()..filterQuality = FilterQuality.high,
  );
}

/// 선택되면 강조색 바탕에 검정 글씨로 한 단계 크게.
Future<kakao.KImage> _build(
  String label,
  bool selected,
  void Function(Canvas canvas, Rect rect) drawIcon,
) {
  final bodyHeight = selected ? _selectedHeight : _height;
  final iconSize = bodyHeight - _iconInset * 2;
  final background = selected ? AppColors.accent : AppColors.ink;
  final foreground = selected ? AppColors.ink : Colors.white;

  final text = TextPainter(
    text: TextSpan(
      text: label,
      style: TextStyle(
        fontSize: selected ? 11 : 10,
        fontWeight: FontWeight.w600,
        color: foreground,
        height: 1.0,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();

  final bodyWidth =
      _iconInset + iconSize + _gap + text.width.ceilToDouble() + _paddingRight;
  final width = (bodyWidth + _margin * 2).ceilToDouble();
  final height = _margin + bodyHeight + _tailHeight;

  return rasterizeMarker(
    width: width,
    height: height,
    draw: (canvas) {
      final body = Rect.fromLTWH(
        (width - bodyWidth) / 2,
        _margin,
        bodyWidth,
        bodyHeight,
      );
      final cx = width / 2;
      // 몸통과 꼬리를 하나의 외곽선으로 합쳐 그림자가 이어지게 한다.
      final shape = Path.combine(
        ui.PathOperation.union,
        Path()..addRRect(
          RRect.fromRectAndRadius(body, Radius.circular(bodyHeight / 2)),
        ),
        Path()
          ..moveTo(cx - _tailWidth / 2, body.bottom - 1)
          ..lineTo(cx, height)
          ..lineTo(cx + _tailWidth / 2, body.bottom - 1)
          ..close(),
      );
      canvas.drawShadow(shape, Colors.black, 2, false);
      canvas.drawPath(shape, Paint()..color = background);

      final iconRect = Rect.fromLTWH(
        body.left + _iconInset,
        body.top + _iconInset,
        iconSize,
        iconSize,
      );
      canvas.save();
      canvas.clipPath(Path()..addOval(iconRect));
      drawIcon(canvas, iconRect);
      canvas.restore();

      text.paint(
        canvas,
        Offset(iconRect.right + _gap, body.center.dy - text.height / 2),
      );
    },
  );
}
