/// 위경도 한 점. 지도 SDK 타입에 의존하지 않는 순수 도메인 모델이다.
class GeoPoint {
  const GeoPoint({
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.recordedAt,
  });

  final double latitude;
  final double longitude;

  /// 고도(m). 코스 데이터에는 없을 수 있다.
  final double? altitude;

  /// 러닝 기록으로 수집된 점일 때의 수집 시각.
  final DateTime? recordedAt;

  factory GeoPoint.fromJson(Map<String, dynamic> json) => GeoPoint(
    latitude: (json['lat'] as num).toDouble(),
    longitude: (json['lng'] as num).toDouble(),
    altitude: (json['altitude'] as num?)?.toDouble(),
    recordedAt: json['recorded_at'] == null
        ? null
        : DateTime.parse(json['recorded_at'] as String),
  );

  Map<String, dynamic> toJson() => {
    'lat': latitude,
    'lng': longitude,
    if (altitude != null) 'altitude': altitude,
    if (recordedAt != null) 'recorded_at': recordedAt!.toIso8601String(),
  };

  @override
  String toString() => 'GeoPoint($latitude, $longitude)';
}
