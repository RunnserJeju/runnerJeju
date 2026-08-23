import 'package:flutter_test/flutter_test.dart';
import 'package:runners_jeju/api/geo_api.dart';

void main() {
  group('GeoCandidate.fromJson', () {
    test('도로명 주소가 있으면 읽는다', () {
      final candidate = GeoCandidate.fromJson({
        'address': '제주 대정읍 상모리 4165',
        'road_address': '제주 대정읍 송악관광로 42',
        'lat': 33.21,
        'lng': 126.29,
      });

      expect(candidate.address, '제주 대정읍 상모리 4165');
      expect(candidate.roadAddress, '제주 대정읍 송악관광로 42');
      expect(candidate.lat, 33.21);
      expect(candidate.lng, 126.29);
    });

    test('도로명 주소가 없으면(null) roadAddress가 null이다', () {
      final candidate = GeoCandidate.fromJson({
        'address': '제주 대정읍 상모리 4165',
        'road_address': null,
        'lat': 33.21,
        'lng': 126.29,
      });

      expect(candidate.roadAddress, isNull);
    });
  });
}
