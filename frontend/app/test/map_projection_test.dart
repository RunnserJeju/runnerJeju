import 'package:flutter_test/flutter_test.dart';
import 'package:runners_jeju/models/geo_point.dart';
import 'package:runners_jeju/utils/map_projection.dart';

/// 공유 카드의 지도 배경과 그 위의 경로가 맞물리게 하는 투영.
///
/// 여기 값이 틀어지면 달린 길이 실제 도로에서 벗어난 채 인스타로 나간다.
/// 화면으로는 "그럴듯해" 보여서 놓치기 쉬우므로 숫자로 못 박아 둔다.
void main() {
  group('해상도', () {
    test('레벨당 2^(level-3) m/px다', () {
      // 실측값: 같은 레벨에서 중심을 정확히 2km 옮긴 두 이미지의 픽셀 이동량이
      // lv5=500px, lv6=250px, lv7=125px이었다.
      expect(MapProjection.metersPerPixel(3), 1);
      expect(MapProjection.metersPerPixel(5), 4);
      expect(MapProjection.metersPerPixel(6), 8);
      expect(MapProjection.metersPerPixel(7), 16);
    });

    test('레벨이 하나 오르면 두 배로 축소된다', () {
      for (var level = 1; level < 15; level++) {
        expect(
          MapProjection.metersPerPixel(level + 1),
          MapProjection.metersPerPixel(level) * 2,
        );
      }
    });
  });

  group('미터/도 환산', () {
    // 이 값들이 맞아야 실측이 정확한 2의 거듭제곱으로 떨어졌다는 사실과
    // 앞뒤가 맞는다.
    test('제주 위도에서 경도 1도는 약 93.2km다', () {
      expect(
        MapProjection.metersPerLongitudeDegree(33.22849),
        closeTo(93212, 5),
      );
    });

    test('제주 위도에서 위도 1도는 약 110.9km다', () {
      expect(
        MapProjection.metersPerLatitudeDegree(33.22849),
        closeTo(110908, 5),
      );
    });

    test('적도에서 멀어질수록 경도 1도가 짧아진다', () {
      expect(
        MapProjection.metersPerLongitudeDegree(60),
        lessThan(MapProjection.metersPerLongitudeDegree(33)),
      );
    });
  });

  group('레벨 선택', () {
    /// 중심에서 사방으로 [halfSpanMeters]만큼 뻗은 네모난 경로.
    List<GeoPoint> squarePath(double halfSpanMeters) {
      const lat = 33.22849;
      const lng = 126.30641;
      final dLat = halfSpanMeters / MapProjection.metersPerLatitudeDegree(lat);
      final dLng = halfSpanMeters / MapProjection.metersPerLongitudeDegree(lat);

      return [
        GeoPoint(latitude: lat - dLat, longitude: lng - dLng),
        GeoPoint(latitude: lat + dLat, longitude: lng + dLng),
      ];
    }

    test('경로가 영역 안에 다 들어간다', () {
      // 지도 영역은 920×560, 여유 40px씩. 여러 크기의 경로로 확인한다.
      for (final halfSpan in [100.0, 500.0, 2000.0, 8000.0]) {
        final path = squarePath(halfSpan);
        final projection = MapProjection.fit(
          path,
          width: 920,
          height: 560,
        );

        for (final point in path) {
          final px = projection.toPixel(point);
          expect(
            px.dx,
            inInclusiveRange(0, 920),
            reason: '반경 ${halfSpan}m 경로가 가로로 넘친다',
          );
          expect(
            px.dy,
            inInclusiveRange(0, 560),
            reason: '반경 ${halfSpan}m 경로가 세로로 넘친다',
          );
        }
      }
    });

    test('불필요하게 축소하지 않는다', () {
      // 한 단계 더 확대하면 넘쳐야 한다 — 그래야 "담을 수 있는 가장 확대된
      // 레벨"이다. 지나치게 축소하면 경로가 점처럼 작아진다.
      final path = squarePath(1500);
      final level = MapProjection.levelToFit(path, width: 920, height: 560);

      final tighter = MapProjection(
        center: const GeoPoint(latitude: 33.22849, longitude: 126.30641),
        level: level - 1,
        size: (width: 920, height: 560),
      );

      final overflows = path.any((p) {
        final px = tighter.toPixel(p);
        return px.dx < 0 || px.dx > 920 || px.dy < 0 || px.dy > 560;
      });
      expect(overflows, isTrue);
    });

    test('한 점에 머문 기록도 동네가 보이는 레벨을 준다', () {
      // 좌표 범위가 0이면 요구 해상도가 0이라 가장 확대된 레벨로 빨려 들어간다.
      // 그러면 건물 하나만 크게 나와 어디인지 알 수 없다.
      const stuck = [
        GeoPoint(latitude: 33.22849, longitude: 126.30641),
        GeoPoint(latitude: 33.22849, longitude: 126.30641),
      ];

      final level = MapProjection.levelToFit(stuck, width: 920, height: 560);
      expect(level, greaterThan(MapProjection.minLevel));
    });

    test('레벨은 카카오가 받는 범위 안이다', () {
      // 제주 전체를 덮는 경로(약 73km)도 상한을 넘지 않아야 한다.
      final level = MapProjection.levelToFit(
        squarePath(40000),
        width: 920,
        height: 560,
      );
      expect(level, inInclusiveRange(MapProjection.minLevel, MapProjection.maxLevel));
    });
  });

  group('픽셀 변환', () {
    const center = GeoPoint(latitude: 33.22849, longitude: 126.30641);
    const projection = MapProjection(
      center: center,
      level: 6, // 8 m/px
      size: (width: 920, height: 560),
    );

    test('중심은 이미지 한가운데다', () {
      final px = projection.toPixel(center);
      expect(px.dx, closeTo(460, 0.001));
      expect(px.dy, closeTo(280, 0.001));
    });

    test('동쪽으로 800m면 오른쪽으로 100px이다', () {
      // 800m / 8(m/px) = 100px.
      final east = GeoPoint(
        latitude: center.latitude,
        longitude: center.longitude +
            800 / MapProjection.metersPerLongitudeDegree(center.latitude),
      );

      final px = projection.toPixel(east);
      expect(px.dx, closeTo(560, 0.01));
      expect(px.dy, closeTo(280, 0.01));
    });

    test('북쪽은 화면 위쪽이다', () {
      final north = GeoPoint(
        latitude: center.latitude +
            800 / MapProjection.metersPerLatitudeDegree(center.latitude),
        longitude: center.longitude,
      );

      final px = projection.toPixel(north);
      // y는 아래로 자라므로 북쪽은 280보다 작아야 한다.
      expect(px.dy, closeTo(180, 0.01));
    });
  });
}
