import 'package:flutter_test/flutter_test.dart';
import 'package:runners_jeju/models/course_facility.dart';

void main() {
  group('CourseFacility JSON', () {
    test('fromJson이 좌표와 이름을 읽는다', () {
      final facility = CourseFacility.fromJson({
        'name': '송악산 주차장',
        'address': '제주 대정읍 상모리 4165',
        'lat': 33.21,
        'lng': 126.29,
      });

      expect(facility.name, '송악산 주차장');
      expect(facility.address, '제주 대정읍 상모리 4165');
      expect(facility.lat, 33.21);
      expect(facility.lng, 126.29);
    });

    test('name이 null이면 toJson에서 키를 뺀다', () {
      const facility = CourseFacility(address: '제주 A', lat: 33.5, lng: 126.5);

      expect(facility.toJson().containsKey('name'), isFalse);
      expect(facility.toJson(), {'address': '제주 A', 'lat': 33.5, 'lng': 126.5});
    });

    test('name이 있으면 toJson에 포함한다', () {
      const facility = CourseFacility(
        name: '주차장',
        address: '제주 A',
        lat: 33.5,
        lng: 126.5,
      );

      expect(facility.toJson()['name'], '주차장');
    });
  });

  group('collectFacilities', () {
    const confirmed = CourseFacility(address: '제주 A', lat: 33.5, lng: 126.5);

    test('빈 줄은 건너뛴다', () {
      final result = collectFacilities(
        const [FacilityFormEntry(name: '', address: '')],
        label: '주차장',
      );

      expect(result, isEmpty);
    });

    test('주소가 있는데 확인을 안 눌렀으면 예외', () {
      expect(
        () => collectFacilities(
          const [FacilityFormEntry(name: '', address: '제주 어딘가')],
          label: '주차장',
        ),
        throwsA(isA<FacilityInputException>()),
      );
    });

    test('이름만 있고 주소가 없으면 예외', () {
      expect(
        () => collectFacilities(
          const [FacilityFormEntry(name: '이름만', address: '')],
          label: '화장실',
        ),
        throwsA(isA<FacilityInputException>()),
      );
    });

    test('확인된 항목은 좌표까지 담아 반환한다', () {
      final result = collectFacilities(
        const [FacilityFormEntry(name: '', address: '제주 A', confirmed: confirmed)],
        label: '주차장',
      );

      expect(result, hasLength(1));
      expect(result.first.address, '제주 A');
      expect(result.first.lat, 33.5);
      expect(result.first.lng, 126.5);
      // 이름이 비어 있으면 null로 저장한다.
      expect(result.first.name, isNull);
    });

    test('이름이 있으면 그대로 담는다', () {
      final result = collectFacilities(
        const [
          FacilityFormEntry(name: '공영주차장', address: '제주 A', confirmed: confirmed),
        ],
        label: '주차장',
      );

      expect(result.first.name, '공영주차장');
    });

    test('여러 항목을 섞어도 확인된 것만, 빈 줄은 무시하고 모은다', () {
      final result = collectFacilities(
        const [
          FacilityFormEntry(name: '', address: '', confirmed: null), // 빈 줄
          FacilityFormEntry(name: 'A', address: '제주 A', confirmed: confirmed),
          FacilityFormEntry(name: 'B', address: '제주 A', confirmed: confirmed),
        ],
        label: '주차장',
      );

      expect(result.map((f) => f.name), ['A', 'B']);
    });
  });
}
