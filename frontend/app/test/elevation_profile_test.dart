import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runners_jeju/models/elevation_profile.dart';
import 'package:runners_jeju/models/geo_point.dart';
import 'package:runners_jeju/widgets/elevation_chart.dart';

/// 제주 안의 한 점에서 북쪽으로 [index]칸(약 11m씩) 떨어진 좌표.
GeoPoint point(int index, double? altitude) => GeoPoint(
  latitude: 33.2000 + index * 0.0001,
  longitude: 126.3000,
  altitude: altitude,
);

List<GeoPoint> pathOf(List<double?> altitudes) => [
  for (var i = 0; i < altitudes.length; i++) point(i, altitudes[i]),
];

void main() {
  group('ElevationProfile.of', () {
    test('경로가 짧으면 null', () {
      expect(ElevationProfile.of(const []), isNull);
      expect(ElevationProfile.of(pathOf([10])), isNull);
    });

    test('고도가 빠진 점이 있으면 통째로 포기한다', () {
      // 우도런처럼 서버가 고도를 버린 코스가 이 경우다.
      expect(ElevationProfile.of(pathOf([10, null, 12])), isNull);
      expect(ElevationProfile.of(pathOf([null, null, null])), isNull);
    });

    test('같은 자리에 찍힌 점들만 있으면 null', () {
      // x축(거리)이 0이라 그래프를 그릴 수 없다.
      const same = GeoPoint(latitude: 33.2, longitude: 126.3, altitude: 5);
      expect(ElevationProfile.of(const [same, same, same]), isNull);
    });

    test('누적 거리를 x축으로 채운다', () {
      final profile = ElevationProfile.of(pathOf([10, 20, 30]))!;

      expect(profile.samples.first.distanceMeters, 0);
      // 0.0001도씩 벌어진 세 점 = 약 11.1m 간격.
      expect(profile.samples[1].distanceMeters, closeTo(11.1, 0.3));
      expect(profile.distanceMeters, closeTo(22.2, 0.6));
    });

    test('최저·최고 고도', () {
      final profile = ElevationProfile.of(pathOf([12, 4, 30, 21]))!;

      expect(profile.minAltitude, 4);
      expect(profile.maxAltitude, 30);
    });
  });

  group('ElevationChart', () {
    testWidgets('평지 코스도 예외 없이 그린다', (tester) async {
      // 고도차가 4m뿐인 해안 코스(사계해안도로 2.5~6.8m) — y축 범위 계산이
      // 0으로 나누거나 뒤집히지 않아야 한다.
      final profile = ElevationProfile.of(pathOf([2.5, 3.0, 6.8, 4.1]))!;

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: ElevationChart(profile: profile))),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(ElevationChart), findsOneWidget);
    });

    testWidgets('고도차가 큰 코스도 그린다', (tester) async {
      final profile = ElevationProfile.of(pathOf([503.6, 640, 807.3, 700]))!;

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: ElevationChart(profile: profile))),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('고도가 모두 같아도 그린다', (tester) async {
      final profile = ElevationProfile.of(pathOf([5, 5, 5, 5]))!;

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: ElevationChart(profile: profile))),
      );

      expect(tester.takeException(), isNull);
    });
  });
}
