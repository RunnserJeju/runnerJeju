import 'package:flutter/material.dart';

/// 미획득 스탬프를 자기 도안 그대로 흑백·반투명으로 그릴 때 쓰는 공통 톤.
///
/// 흑백 변환에 더해 밝기를 60~180으로 눌러, 흰 요소는 연한 회색이 되고 난이도별
/// 색(빨강·노랑·초록)의 진하기 차이도 줄어든다. 빙고판·스탬프 탭·팝업이 같이 쓴다.
const ColorFilter stampLockedFilter = ColorFilter.matrix(<double>[
  0.0999, 0.3361, 0.0339, 0, 60, //
  0.0999, 0.3361, 0.0339, 0, 60, //
  0.0999, 0.3361, 0.0339, 0, 60, //
  0, 0, 0, 1, 0,
]);

const double stampLockedOpacity = 0.6;

/// [child]를 미획득 톤으로 감싼다.
Widget stampLockedTone(Widget child) => Opacity(
  opacity: stampLockedOpacity,
  child: ColorFiltered(colorFilter: stampLockedFilter, child: child),
);
