import '../utils/geo_utils.dart';
import 'geo_point.dart';

/// 고도 그래프의 점 하나. x는 코스 시작점부터의 거리, y는 고도다.
class ElevationSample {
  const ElevationSample({
    required this.distanceMeters,
    required this.altitudeMeters,
  });

  final double distanceMeters;
  final double altitudeMeters;
}

/// 코스 경로에서 뽑아낸 고도 프로파일.
///
/// 코스 경로(`RunningCourse.path`)는 서버가 15m 균등 간격으로 리샘플하면서 점별
/// 고도까지 채워 내려준다(server `app/gpx.py`). 그래프는 그 값을 그대로 그린다 —
/// 여기서 하는 일은 x축에 쓸 누적 거리와, y축 범위에 쓸 최소/최대를 한 번
/// 계산해 두는 것뿐이다.
class ElevationProfile {
  const ElevationProfile._({
    required this.samples,
    required this.minAltitude,
    required this.maxAltitude,
  });

  final List<ElevationSample> samples;

  final double minAltitude;
  final double maxAltitude;

  /// 코스 전체 길이(m).
  double get distanceMeters => samples.last.distanceMeters;

  /// 경로에서 프로파일을 만든다. 고도를 그릴 수 없는 코스면 null.
  ///
  /// 한 점이라도 고도가 비어 있으면 통째로 포기한다. 빈 자리를 건너뛰고 이으면
  /// 그 구간의 오르내림이 실제와 무관한 모양이 되기 때문이다(서버도 같은 이유로
  /// 고도가 온전하지 않은 GPX는 고도를 전부 버린다 — 우도런 코스가 여기 해당한다).
  static ElevationProfile? of(List<GeoPoint> path) {
    if (path.length < 2) return null;
    if (path.any((point) => point.altitude == null)) return null;

    final samples = <ElevationSample>[];
    var distance = 0.0;

    for (var i = 0; i < path.length; i++) {
      if (i > 0) distance += GeoUtils.distanceBetween(path[i - 1], path[i]);
      samples.add(
        ElevationSample(
          distanceMeters: distance,
          altitudeMeters: path[i].altitude!,
        ),
      );
    }

    // 길이가 0이면 x축을 그릴 수 없다(같은 자리에 찍힌 점들).
    if (distance <= 0) return null;

    final altitudes = samples.map((s) => s.altitudeMeters).toList();

    return ElevationProfile._(
      samples: samples,
      minAltitude: altitudes.reduce((a, b) => a < b ? a : b),
      maxAltitude: altitudes.reduce((a, b) => a > b ? a : b),
    );
  }
}
