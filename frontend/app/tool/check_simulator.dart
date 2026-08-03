// 결과를 콘솔에 찍는 것이 이 스크립트의 존재 이유다.
// ignore_for_file: avoid_print

// 시뮬레이터가 "코스를 따라가되 코스와 똑같지는 않게" 좌표를 만드는지 검사한다.
//
//     dart run tool/check_simulator.dart
//
// flutter_test가 아니라 순수 Dart로 도는 이유는 두 가지다. 검사 대상인
// RunPathSimulator가 Flutter에 의존하지 않고, 이 환경에서 `flutter test`가
// 로드 단계에서 죽어서 쓸 수 없다.
import 'dart:math' as math;

import 'package:runners_jeju/models/geo_point.dart';
import 'package:runners_jeju/test/run_path_simulator.dart';
import 'package:runners_jeju/utils/geo_utils.dart';

var _failures = 0;

void check(String label, bool passed, [String detail = '']) {
  print('  ${passed ? 'OK  ' : 'FAIL'}  $label${detail.isEmpty ? '' : '  ($detail)'}');
  if (!passed) _failures++;
}

/// 완만하게 굽은 약 2km 코스. 점 간격은 실제 GPX처럼 30m 안팎으로 둔다.
List<GeoPoint> buildCourse() => [
  for (var i = 0; i <= 70; i++)
    GeoPoint(
      latitude: 33.2300 + i * 0.00027,
      longitude: 126.3100 + math.sin(i / 9) * 0.0006,
      altitude: 10 + math.sin(i / 5) * 8,
    ),
];

/// 점에서 선분까지의 최단 거리(m).
///
/// GeoUtils.distanceToPath는 코스 *꼭짓점*까지만 재기 때문에 이탈 측정에 쓸 수
/// 없다. 점 간격이 30m면 선 위에 정확히 놓인 점도 최대 15m로 나온다.
double _distanceToSegment(GeoPoint p, GeoPoint a, GeoPoint b) {
  final lngToM = metersPerLngDegree(a.latitude);

  final bx = (b.longitude - a.longitude) * lngToM;
  final by = (b.latitude - a.latitude) * metersPerLatDegree;
  final px = (p.longitude - a.longitude) * lngToM;
  final py = (p.latitude - a.latitude) * metersPerLatDegree;

  final lengthSquared = bx * bx + by * by;
  final t = lengthSquared == 0
      ? 0.0
      : ((px * bx + py * by) / lengthSquared).clamp(0.0, 1.0);

  final cx = bx * t, cy = by * t;
  return math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
}

/// 점에서 코스 폴리라인까지의 최단 거리(m).
double deviation(GeoPoint p, List<GeoPoint> course) {
  var best = double.infinity;
  for (var i = 1; i < course.length; i++) {
    best = math.min(best, _distanceToSegment(p, course[i - 1], course[i]));
  }
  return best;
}

List<GeoPoint> simulate(List<GeoPoint> course, RunSimulationProfile profile) =>
    RunPathSimulator(
      route: course,
      profile: profile,
      random: math.Random(42),
    ).runToFinish();

void main() {
  final course = buildCourse();
  final courseLength = GeoUtils.pathLength(course);

  print(
    '\n코스: ${courseLength.toStringAsFixed(0)}m, 점 ${course.length}개, '
    '평균 간격 ${(courseLength / (course.length - 1)).toStringAsFixed(1)}m\n',
  );

  // --- 프로파일별 특성 요약 ------------------------------------------------
  final profiles = {
    'normal': RunSimulationProfile.normal,
    'timeLapse': RunSimulationProfile.timeLapse,
    'noisyGps': RunSimulationProfile.noisyGps,
    'offCourse': RunSimulationProfile.offCourse,
  };

  final meanDeviations = <String, double>{};

  for (final entry in profiles.entries) {
    final samples = simulate(course, entry.value);
    final measured = GeoUtils.pathLength(samples);
    final devs = [for (final s in samples) deviation(s, course)];
    final mean = devs.reduce((a, b) => a + b) / devs.length;
    meanDeviations[entry.key] = mean;

    final spacing = measured / (samples.length - 1);
    // 앱에서 진짜 타이머로 돌렸을 때 완주까지 기다려야 하는 시간.
    final realSeconds =
        samples.length * entry.value.interval.inMilliseconds / 1000;

    print(
      '${entry.key.padRight(10)} '
      '점 ${samples.length.toString().padLeft(4)} | '
      '간격 ${spacing.toStringAsFixed(1).padLeft(4)}m | '
      '측정거리 ${measured.toStringAsFixed(0).padLeft(4)}m '
      '(코스의 ${(measured / courseLength * 100).toStringAsFixed(0)}%) | '
      '이탈 평균 ${mean.toStringAsFixed(1).padLeft(4)}m '
      '최대 ${devs.reduce(math.max).toStringAsFixed(1).padLeft(5)}m | '
      '완주까지 ${realSeconds.toStringAsFixed(0).padLeft(4)}초',
    );
  }

  // --- 검사 ---------------------------------------------------------------
  final samples = simulate(course, RunSimulationProfile.normal);
  final devs = [for (final s in samples) deviation(s, course)];
  final measured = GeoUtils.pathLength(samples);

  print('\n[코스와 똑같지 않게 만드는가]');

  final exact = samples
      .where(
        (s) => course.any(
          (c) => c.latitude == s.latitude && c.longitude == s.longitude,
        ),
      )
      .length;
  check('코스 점을 그대로 복사하지 않는다', exact == 0, '일치 $exact개');

  final unique = samples.map((s) => '${s.latitude},${s.longitude}').toSet();
  check('모든 관측점이 서로 다르다', unique.length == samples.length);

  final meanDev = devs.reduce((a, b) => a + b) / devs.length;
  check('코스 선에 붙어 있지 않다 (평균 이탈 > 0.5m)', meanDev > 0.5,
      '${meanDev.toStringAsFixed(2)}m');

  print('\n[그러면서도 코스를 따라가는가]');

  final maxDev = devs.reduce(math.max);
  // lateralDrift(4m) + gpsNoise(2.5m)가 상한이다.
  check('최대 이탈이 프로파일 범위 안 (< 6.5m)', maxDev < 6.5,
      '${maxDev.toStringAsFixed(2)}m');

  check(
    '출발점에서 시작한다 (< 10m)',
    GeoUtils.distanceBetween(samples.first, course.first) < 10,
    '${GeoUtils.distanceBetween(samples.first, course.first).toStringAsFixed(1)}m',
  );

  final toFinish = GeoUtils.distanceBetween(samples.last, course.last);
  check(
    '도착점 완주 판정 반경(60m) 안에서 끝난다',
    toFinish < 60,
    '${toFinish.toStringAsFixed(1)}m',
  );

  print('\n[누적 거리가 왜곡되지 않는가]');
  // 잡음이 상관 없이 튀면 누적 거리가 몇 배로 부푼다. 평균 회귀 랜덤워크를
  // 쓰는 이유가 이것이라, 여기서 무너지면 잡음 설계가 잘못된 것이다.
  final ratio = measured / courseLength;
  check('코스 길이의 95~130%', ratio > 0.95 && ratio < 1.30,
      '${(ratio * 100).toStringAsFixed(1)}%');

  print('\n[프로파일이 의도대로 갈리는가]');
  final lapse = simulate(course, RunSimulationProfile.timeLapse);
  final normalSpacing =
      GeoUtils.pathLength(samples) / (samples.length - 1);
  final lapseSpacing = GeoUtils.pathLength(lapse) / (lapse.length - 1);
  check(
    'timeLapse가 점 간격을 유지한다',
    (normalSpacing - lapseSpacing).abs() < 0.5,
    'normal ${normalSpacing.toStringAsFixed(2)}m vs '
        'timeLapse ${lapseSpacing.toStringAsFixed(2)}m',
  );
  check(
    'timeLapse가 완주까지 걸리는 시간을 10배 이상 줄인다',
    lapse.length * 0.05 < samples.length * 1.0 / 10,
    '${(samples.length * 1.0).toStringAsFixed(0)}초 → '
        '${(lapse.length * 0.05).toStringAsFixed(0)}초',
  );
  check(
    'offCourse가 normal보다 5배 이상 벗어난다',
    meanDeviations['offCourse']! > meanDeviations['normal']! * 5,
    '${meanDeviations['normal']!.toStringAsFixed(1)}m → '
        '${meanDeviations['offCourse']!.toStringAsFixed(1)}m',
  );

  print('\n[코스 없는 자유 러닝]');
  final free = RunPathSimulator(
    route: circularRoute(
      const GeoPoint(latitude: 33.4996, longitude: 126.5312),
      400,
    ),
    random: math.Random(1),
  ).runToFinish();
  check('경로가 생성된다', free.length > 10, '${free.length}점');
  check(
    '원형이라 출발점 근처로 돌아온다 (< 60m)',
    GeoUtils.distanceBetween(free.first, free.last) < 60,
    '${GeoUtils.distanceBetween(free.first, free.last).toStringAsFixed(1)}m',
  );

  print(_failures == 0 ? '\n전부 통과\n' : '\n실패 $_failures건\n');
}
