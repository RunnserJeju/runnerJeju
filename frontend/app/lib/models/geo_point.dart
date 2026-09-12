/// 위경도 한 점. 지도 SDK 타입에 의존하지 않는 순수 도메인 모델이다.
/// (순수 Dart 도구가 이 파일을 쓰므로 Flutter·지도 SDK를 import하지 않는다.)
class GeoPoint {
  const GeoPoint({
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.recordedAt,
    this.startsNewSegment = false,
    this.accuracy,
    this.speed,
  });

  final double latitude;
  final double longitude;

  /// 고도(m). **코스 경로에만 있다.**
  ///
  /// 서버가 GPX에서 읽어 코스 경로에 실어 주고, 코스 상세의 고도 그래프
  /// (ElevationProfile)가 유일한 소비처다. 러닝 기록은 고도를 수집하지 않는다 —
  /// 보여주는 곳도, 거리·페이스·검증에 쓰는 곳도 없어서 실어 나를 이유가 없다.
  /// 그래서 러닝 경로의 점은 늘 null이다.
  final double? altitude;

  /// 러닝 기록으로 수집된 점일 때의 수집 시각.
  final DateTime? recordedAt;

  /// 이 점 **앞에서 기록이 끊겼는지**. 일시정지 동안 이동한 구간이 여기 해당한다.
  ///
  /// 끊긴 구간은 달린 것으로 치지 않는다 — 거리에도, 코스 커버리지에도 넣지
  /// 않는다. 그런데 서버는 올라온 경로를 **다시 재서** 검증하므로, 표시를 남기지
  /// 않으면 서버만 그 구간을 달린 것으로 세어 앱과 판정이 갈라진다. 그래서 끊긴
  /// 자리를 점에 적어 함께 올린다.
  ///
  /// 러닝 경로에서만 의미가 있다. 코스 경로는 끊기는 자리가 없다.
  final bool startsNewSegment;

  // 오차범위
  final double? accuracy;

  // 이동 속도(m/s). GPS가 직접 내주는 값이라 좌표 차이로 계산한 것보다 안정적이다.
  // 못 잰 점은 null이다(0이 아니다 — 0은 "서 있다"라는 뜻이다).
  final double? speed;

  /// 같은 좌표에 [startsNewSegment] 표시만 붙인 사본.
  ///
  /// 러닝 경로에서만 쓰므로 [altitude]는 옮기지 않는다(늘 null이다).
  GeoPoint asSegmentStart() => GeoPoint(
    latitude: latitude,
    longitude: longitude,
    recordedAt: recordedAt,
    accuracy: accuracy,
    speed: speed,
    startsNewSegment: true,
  );

  factory GeoPoint.fromJson(Map<String, dynamic> json) => GeoPoint(
    latitude: (json['lat'] as num).toDouble(),
    longitude: (json['lng'] as num).toDouble(),
    altitude: (json['altitude'] as num?)?.toDouble(),
    recordedAt: json['recorded_at'] == null
        ? null
        : DateTime.parse(json['recorded_at'] as String),
    startsNewSegment: json['segment_break'] as bool? ?? false,
  );

  /// 러닝 기록을 서버로 올릴 때 쓴다(코스는 서버가 내려주기만 하므로 이 방향이 없다).
  /// 그래서 [altitude]는 싣지 않는다 — 러닝 경로에는 애초에 없는 값이다.
  ///
  /// 끊긴 자리에만 키를 넣는다. 러닝 하나의 경로가 천 점을 넘는데 대부분은 끊긴
  /// 자리가 아니라, false를 전부 실어 보내면 그만큼이 그대로 낭비다.
  Map<String, dynamic> toJson() => {
    'lat': latitude,
    'lng': longitude,
    if (recordedAt != null)
      'recorded_at': recordedAt!.toUtc().toIso8601String(),
    if (startsNewSegment) 'segment_break': true,
  };

  @override
  String toString() => 'GeoPoint($latitude, $longitude)';
}
