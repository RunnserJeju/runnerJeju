import 'package:flutter_test/flutter_test.dart';
import 'package:runners_jeju/models/course_partner.dart';
import 'package:runners_jeju/models/geo_point.dart';
import 'package:runners_jeju/screens/running/partner_list_sheet.dart';

Map<String, dynamic> _json({
  String id = 'p1',
  String name = '송악 카페',
  double lat = 33.2,
  double lng = 126.3,
  Map<String, dynamic>? detail,
  String? instagram,
  List<Map<String, dynamic>>? courses,
}) => {
  'id': id,
  'name': name,
  'address': null,
  'lat': lat,
  'lng': lng,
  'comment': null,
  'instagram': instagram,
  'benefit': '러너 10% 할인',
  'detail': ?detail,
  'courses': ?courses,
};

void main() {
  group('CoursePartner.fromJson', () {
    test('GET /partners 응답의 연결 코스를 읽는다', () {
      final partner = CoursePartner.fromJson(
        _json(courses: [
          {'id': 'c1', 'name': '사계 해안도로'},
        ]),
      );

      expect(partner.courses.single.id, 'c1');
      expect(partner.courses.single.name, '사계 해안도로');
    });

    test('코스 응답처럼 courses·detail이 없으면 비어 있다', () {
      final partner = CoursePartner.fromJson(_json());

      expect(partner.courses, isEmpty);
      expect(partner.detail, isEmpty);
    });
  });

  group('category', () {
    test('detail.category 값으로 업종을 정한다', () {
      final partner = CoursePartner.fromJson(_json(detail: {'category': 'cafe'}));

      expect(partner.category, PartnerCategory.cafe);
    });

    test('모르는 값이나 빈 detail은 etc', () {
      expect(
        CoursePartner.fromJson(_json(detail: {'category': 'spa'})).category,
        PartnerCategory.etc,
      );
      expect(CoursePartner.fromJson(_json()).category, PartnerCategory.etc);
    });
  });

  group('instagramUrl', () {
    test('계정명(@ 유무 무관)이면 프로필 URL을 만든다', () {
      expect(
        CoursePartner.fromJson(_json(instagram: '@songak_cafe')).instagramUrl.toString(),
        'https://www.instagram.com/songak_cafe/',
      );
      expect(
        CoursePartner.fromJson(_json(instagram: 'songak_cafe')).instagramUrl.toString(),
        'https://www.instagram.com/songak_cafe/',
      );
    });

    test('URL이면 그대로 쓴다', () {
      const url = 'https://instagram.com/p/abc';
      expect(CoursePartner.fromJson(_json(instagram: url)).instagramUrl.toString(), url);
    });

    test('비어 있으면 null이라 버튼을 숨긴다', () {
      expect(CoursePartner.fromJson(_json()).instagramUrl, isNull);
      expect(CoursePartner.fromJson(_json(instagram: '  ')).instagramUrl, isNull);
    });
  });

  group('sortPartnersByDistance', () {
    final near = CoursePartner.fromJson(_json(id: 'near', lat: 33.50, lng: 126.50));
    final far = CoursePartner.fromJson(_json(id: 'far', lat: 33.30, lng: 126.30));
    const me = GeoPoint(latitude: 33.51, longitude: 126.51);

    test('현위치에서 가까운 순으로 줄 세운다', () {
      final sorted = sortPartnersByDistance([far, near], me);

      expect(sorted.map((e) => e.partner.id), ['near', 'far']);
      expect(sorted.first.distance, lessThan(sorted.last.distance!));
    });

    test('위치를 모르면 받은 순서 그대로, 거리는 null', () {
      final sorted = sortPartnersByDistance([far, near], null);

      expect(sorted.map((e) => e.partner.id), ['far', 'near']);
      expect(sorted.every((e) => e.distance == null), isTrue);
    });
  });
}
