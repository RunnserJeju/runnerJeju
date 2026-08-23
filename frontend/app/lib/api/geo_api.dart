import '../network/api_client.dart';

/// 주소 좌표 변환 결과 후보 하나(GET /geo/geocode 응답의 results 원소).
class GeoCandidate {
  const GeoCandidate({
    required this.address,
    this.roadAddress,
    required this.lat,
    required this.lng,
  });

  /// 지번 주소(항상 있음).
  final String address;

  /// 도로명 주소(카카오가 매칭했을 때만).
  final String? roadAddress;
  final double lat;
  final double lng;

  factory GeoCandidate.fromJson(Map<String, dynamic> json) => GeoCandidate(
    address: json['address'] as String,
    roadAddress: json['road_address'] as String?,
    lat: (json['lat'] as num).toDouble(),
    lng: (json['lng'] as num).toDouble(),
  );
}

/// API 계층: 지오코딩 프록시.
class GeoApi {
  GeoApi(this._client);

  final ApiClient _client;

  /// 주소를 좌표 후보 목록으로 바꾼다. **빈 목록이면 "주소를 못 찾음"이다**
  /// (서버가 200 + results:[]로 내려준다). 호출 자체가 실패하면(502 등) throw.
  Future<List<GeoCandidate>> geocode(String address) async {
    final response = await _client.dio.get(
      '/geo/geocode',
      queryParameters: {'address': address},
    );

    final results = (response.data['results'] as List?) ?? const [];
    return results
        .map((e) => GeoCandidate.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
