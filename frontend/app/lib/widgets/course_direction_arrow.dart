import 'package:flutter/material.dart';
// 카카오맵 SDK는 머티리얼과 겹치는 이름을 내보내므로 접두사를 붙인다.
import 'package:kakao_map_sdk/kakao_map_sdk.dart' as kakao;

import 'marker_canvas.dart';

/// 코스 선 위에 일정 간격으로 반복해 찍는 진행방향 화살표.
///
/// 방향은 따로 계산하지 않는다. 코스 좌표를 넘긴 순서가 곧 진행방향이고,
/// 네이티브가 선 방향에 맞춰 이 이미지를 회전시켜 그린다.
///
/// 이때 진행방향이 되는 축은 이미지의 **세로(Y)** 다. 가로로 그렸더니 화살표가
/// 선과 정확히 90도를 이뤘다. 그래서 위(-Y)를 향한 화살촉을 그린다. 정반대를
/// 가리키게 되면 [front]/[back]의 부호를 뒤집는다.

const Color _arrowColor = Colors.white;

/// 이미지 한 변(dp). 회전 중심이 정중앙이 되도록 정사각이고,
/// 화살표가 대각선으로 놓여도 잘리지 않을 만큼은 커야 한다.
const double _arrowSize = 14;

/// 진행방향으로의 길이(dp). 길수록 뾰족해서 방향이 잘 읽히지만,
/// 꺾이는 지점에서 선 밖으로 삐져나오는 양도 커진다.
const double _arrowLength = 9;

/// 코스 선을 가로지르는 폭(dp). 선 굵기(RunMapView._courseLineWidth)보다
/// 좁아야 한다. 이미지는 선 굵기에 맞춰 줄여주지 않고 이 크기 그대로 찍힌다.
const double _arrowWidth = 4;

Future<kakao.KImage>? _cached;

/// 한 번 그린 이미지를 앱이 도는 동안 재사용한다.
Future<kakao.KImage> buildCourseDirectionArrow() => _cached ??= rasterizeMarker(
  width: _arrowSize,
  height: _arrowSize,
  draw: (canvas) {
    // 원점이 이미지 중앙. 위(-Y)를 향한 화살촉을 그린다.
    canvas.translate(_arrowSize / 2, _arrowSize / 2);
    const front = -_arrowLength / 2;
    const back = _arrowLength / 2;
    const half = _arrowWidth / 2;
    final path = Path()
      ..moveTo(0, front)
      ..lineTo(-half, back)
      ..lineTo(half, back)
      ..close();
    canvas.drawPath(path, Paint()..color = _arrowColor);
  },
);
