import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
// 카카오맵 SDK는 머티리얼과 겹치는 이름을 내보내므로 접두사를 붙인다.
import 'package:kakao_map_sdk/kakao_map_sdk.dart' as kakao;

/// 코스 선 위에 일정 간격으로 반복해 찍는 진행방향 화살표.
///
/// 방향은 따로 계산하지 않는다. 코스 좌표를 넘긴 순서가 곧 진행방향이고,
/// 네이티브가 선 방향에 맞춰 이 이미지를 회전시켜 그린다.
///
/// 이때 진행방향이 되는 축은 이미지의 **세로(Y)** 다. 가로로 그렸더니 화살표가
/// 선과 정확히 90도를 이뤘다. 그래서 위(-Y)를 향한 화살촉을 그린다.

/// 코스 선(주황) 위에서 읽히는 회색.
const Color _arrowColor = Color(0xFF5F666D);

/// 이미지 한 변(dp). 회전 중심이 정중앙이 되도록 정사각이고,
/// 화살표가 대각선으로 놓여도 잘리지 않을 만큼은 커야 한다.
const int _arrowSize = 14;

/// 진행방향으로의 길이(dp). 길수록 뾰족해서 방향이 잘 읽힌다.
const double _arrowLength = 11;

/// 코스 선을 가로지르는 폭(dp).
///
/// 코스 선 굵기(RunMapView._courseLineWidth = 8)보다 좁아야 선 밖으로
/// 삐져나오지 않는다. 이미지는 선 굵기에 맞춰 줄여주지 않고 이 크기 그대로 찍힌다.
const double _arrowWidth = 5;

/// 밑변 가운데를 파낸 깊이(dp). 그냥 삼각형보다 화살촉으로 읽혀서 방향이 분명해진다.
const double _arrowNotch = 3;

const double _arrowPixelRatio = 3;

/// 화살표가 진행방향의 정반대를 가리키면 0.5로 바꾼다(turn 단위).
const double _arrowTurns = 0;

Future<kakao.KImage> buildCourseDirectionArrow() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(_arrowPixelRatio);

  final s = _arrowSize.toDouble();
  canvas
    ..translate(s / 2, s / 2)
    ..rotate(_arrowTurns * 2 * math.pi);

  // 원점이 이미지 중앙. 위(-Y)를 향한 화살촉을 그린다.
  final front = -_arrowLength / 2;
  final back = _arrowLength / 2;
  final half = _arrowWidth / 2;

  final path = Path()
    ..moveTo(0, front)
    ..lineTo(-half, back)
    ..lineTo(0, back - _arrowNotch)
    ..lineTo(half, back)
    ..close();
  canvas.drawPath(path, Paint()..color = _arrowColor);

  final image = await recorder.endRecording().toImage(
    (s * _arrowPixelRatio).round(),
    (s * _arrowPixelRatio).round(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();

  return kakao.KImage.fromData(data!.buffer.asUint8List(), _arrowSize, _arrowSize);
}
