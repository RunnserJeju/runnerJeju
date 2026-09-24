import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// 공유 카드 배경으로 그리는 제주 지형.
///
/// 지도 타일을 받아오지 않고 앱이 직접 그린다. 이유는 둘이다.
///
/// - **약관**: 카카오·구글 지도는 받은 이미지를 저장하거나 밖으로 내보내는 것을
///   금지한다(카카오 데브톡 #151132: "원천 데이터의 저장 및 2차 가공"). 공유
///   카드는 그 자체가 이미지를 만들어 내보내는 기능이라 쓸 수 없다.
///   OpenStreetMap은 ODbL이라 출처만 밝히면 재배포가 허용된다.
/// - **모양**: 색을 직접 정할 수 있어 카드의 일부처럼 보인다. 남의 지도를
///   오려 붙인 것처럼 겉돌지 않는다.
///
/// 데이터는 제주만 담아 170KB다. 전 세계 지도가 아니라 섬 하나라서 통째로
/// 들고 다닐 수 있다.
class JejuBasemap {
  const JejuBasemap._({
    required this.coastline,
    required this.majorRoads,
    required this.midRoads,
    required this.minorRoads,
    required this.labels,
  });

  /// 해안선. 섬마다 하나씩, **닫힌 고리**다(마지막 점이 첫 점으로 이어진다).
  /// OSM의 조각난 해안선을 빌드 단계에서 이어 붙인 결과다 —
  /// scripts/basemap/build_jeju_basemap.py 참고.
  final List<BasemapWay> coastline;

  /// 고속도로·국도. 가장 굵게 그린다.
  final List<BasemapWay> majorRoads;

  /// 지방도·마을길. 지도의 뼈대를 이룬다.
  final List<BasemapWay> midRoads;

  /// 골목·등산로. 이게 있어야 지도가 비어 보이지 않는다 —
  /// 오름 코스에서는 등산로가 곧 달린 길이다.
  final List<BasemapWay> minorRoads;

  final List<BasemapLabel> labels;

  /// 카드에 반드시 들어가야 하는 출처 표기(ODbL).
  static const String attribution = '© OpenStreetMap contributors';

  static const String _assetPath = 'assets/geo/jeju_basemap.bin';

  /// 좌표는 1e-5도 단위 정수로 저장돼 있다(약 1.1m).
  static const double _scale = 100000;

  /// 한 번 읽으면 앱이 사는 동안 들고 있는다. 170KB짜리 상수 데이터라
  /// 화면을 드나들 때마다 다시 읽을 이유가 없다.
  static Future<JejuBasemap>? _cached;

  static Future<JejuBasemap> load() => _cached ??= _decode();

  static Future<JejuBasemap> _decode() async {
    final data = await rootBundle.load(_assetPath);
    final bytes = data.buffer.asByteData(
      data.offsetInBytes,
      data.lengthInBytes,
    );

    var offset = 0;

    int u8() => bytes.getUint8(offset++);
    int u16() {
      final v = bytes.getUint16(offset, Endian.little);
      offset += 2;
      return v;
    }

    int i16() {
      final v = bytes.getInt16(offset, Endian.little);
      offset += 2;
      return v;
    }

    int i32() {
      final v = bytes.getInt32(offset, Endian.little);
      offset += 4;
      return v;
    }

    int u32() {
      final v = bytes.getUint32(offset, Endian.little);
      offset += 4;
      return v;
    }

    final magic = String.fromCharCodes([u8(), u8(), u8(), u8()]);
    if (magic != 'RJGE') {
      throw StateError('제주 지형 데이터가 아닙니다 ($magic)');
    }
    final version = u8();
    if (version != 3) {
      throw StateError('모르는 제주 지형 데이터 버전 $version');
    }

    final layers = <int, List<BasemapWay>>{};
    final layerCount = u8();
    for (var l = 0; l < layerCount; l++) {
      final id = u8();
      u8(); // closed 플래그. 레이어 번호로 이미 아는 값이라 읽고 버린다.
      final wayCount = u32();
      final ways = <BasemapWay>[];

      for (var w = 0; w < wayCount; w++) {
        final minLat = i32() / _scale;
        final minLng = i32() / _scale;
        final maxLat = i32() / _scale;
        final maxLng = i32() / _scale;
        final pointCount = u16();
        // [lat, lng, lat, lng, ...] 한 줄로 둔다. 점마다 객체를 만들면
        // 5만 개짜리 배열에서는 그 자체가 비용이다.
        final points = Float64List(pointCount * 2);

        var lat = i32();
        var lng = i32();
        points[0] = lat / _scale;
        points[1] = lng / _scale;

        for (var p = 1; p < pointCount; p++) {
          lat += i16();
          lng += i16();
          points[p * 2] = lat / _scale;
          points[p * 2 + 1] = lng / _scale;
        }
        ways.add(
          BasemapWay(
            points: points,
            minLatitude: minLat,
            minLongitude: minLng,
            maxLatitude: maxLat,
            maxLongitude: maxLng,
          ),
        );
      }
      layers[id] = ways;
    }

    final labels = <BasemapLabel>[];
    final labelCount = u16();
    for (var i = 0; i < labelCount; i++) {
      final lat = i32() / _scale;
      final lng = i32() / _scale;
      final kind = u8();
      final nameLength = u8();
      final name = utf8.decode(
        bytes.buffer.asUint8List(bytes.offsetInBytes + offset, nameLength),
      );
      offset += nameLength;
      labels.add(
        BasemapLabel(
          latitude: lat,
          longitude: lng,
          kind: BasemapLabelKind.values[kind],
          name: name,
        ),
      );
    }

    return JejuBasemap._(
      coastline: layers[0] ?? const [],
      majorRoads: layers[1] ?? const [],
      midRoads: layers[2] ?? const [],
      minorRoads: layers[3] ?? const [],
      labels: labels,
    );
  }
}

/// 선 하나(해안선 고리 또는 길).
class BasemapWay {
  const BasemapWay({
    required this.points,
    required this.minLatitude,
    required this.minLongitude,
    required this.maxLatitude,
    required this.maxLongitude,
  });

  /// [lat, lng, lat, lng, ...]. 점마다 객체를 만들면 13만 개짜리 데이터에서는
  /// 그 자체가 비용이라 한 줄로 둔다.
  final Float64List points;

  /// 이 선을 감싸는 범위.
  ///
  /// 카드 한 장은 3~6km만 그리는데, 이게 없으면 화면 밖 제주 반대편 골목까지
  /// 전부 좌표 변환하게 된다. 먼저 이 범위만 견줘 걸러낸다.
  final double minLatitude;
  final double minLongitude;
  final double maxLatitude;
  final double maxLongitude;

  /// [bounds] 안에 조금이라도 걸치는지.
  bool intersects(
    ({double minLat, double minLng, double maxLat, double maxLng}) bounds,
  ) =>
      maxLatitude >= bounds.minLat &&
      minLatitude <= bounds.maxLat &&
      maxLongitude >= bounds.minLng &&
      minLongitude <= bounds.maxLng;
}

/// 지도에 이름을 얹을 자리.
class BasemapLabel {
  const BasemapLabel({
    required this.latitude,
    required this.longitude,
    required this.kind,
    required this.name,
  });

  final double latitude;
  final double longitude;
  final BasemapLabelKind kind;
  final String name;
}

/// 라벨 종류. 좁은 카드에 다 넣을 수 없어 이 순서대로 자리를 준다.
enum BasemapLabelKind {
  city,
  town,
  village,
  suburb,
  island,

  /// 오름·산봉우리. 제주에서는 이게 마을만큼 좋은 이정표다.
  peak,
}
