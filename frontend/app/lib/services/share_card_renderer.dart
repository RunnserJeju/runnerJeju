import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

/// 화면에 그려진 공유 카드를 PNG 파일로 굽는다.
///
/// 래스터화 절차(경계 찾기 → 확대 → PNG → 임시 파일)를 여기 한 곳에만 둔다.
/// 지도 마커도 같은 이유로 `rasterizeMarker` 한 곳에 모여 있다.
class ShareCardRenderer {
  const ShareCardRenderer();

  /// 인스타 스토리 권장 해상도의 가로폭. 최소 720이면 되지만, 스토리는 기기
  /// 해상도로 늘려 보여주므로 여유를 둔다.
  static const int targetWidth = 1080;

  /// [boundaryKey]가 가리키는 [RepaintBoundary]를 [targetWidth] 폭의 PNG로
  /// 저장하고 그 파일을 돌려준다.
  ///
  /// 미리보기는 기기 폭에 맞춰 줄어들어 있으므로, 그 축소분을 되돌려 캡처해야
  /// 1080px이 나온다. 그래서 배율을 고정하지 않고 실제 그려진 폭에서 역산한다.
  Future<File> toPngFile(GlobalKey boundaryKey, {required String name}) async {
    final boundary =
        boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      throw StateError('공유 카드가 아직 화면에 없습니다');
    }

    // 아직 그려지지 않은 경계를 캡처하면 빈 이미지가 나온다. 한 프레임 기다려
    // 페인트가 끝난 걸 보장한다.
    //
    // 조건부로 걸러내지 않는다 — `debugNeedsPaint`는 디버그 전용 getter라서
    // 릴리스 빌드에서는 LateInitializationError가 난다. 한 프레임은 어차피
    // 사용자가 알아채지 못한다.
    await SchedulerBinding.instance.endOfFrame;

    final image = await boundary.toImage(
      pixelRatio: targetWidth / boundary.size.width,
    );

    final ByteData? data;
    try {
      data = await image.toByteData(format: ui.ImageByteFormat.png);
    } finally {
      image.dispose();
    }
    if (data == null) throw StateError('공유 카드를 이미지로 만들지 못했습니다');

    // 공유가 끝나면 쓸 일이 없는 파일이라 캐시 디렉터리에 둔다. OS가 알아서
    // 비운다. 같은 이름으로 덮어써서 공유할 때마다 파일이 쌓이지 않게 한다.
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/$name');
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    return file;
  }
}
