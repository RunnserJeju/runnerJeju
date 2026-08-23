/// 코스 근처 편의시설 한 곳(주차장 또는 화장실). 서버 `Facility`(schemas.py)와
/// 1:1이다 — 좌표는 등록 시점에 주소를 변환(GET /geo/geocode)해 채운 값이라
/// 지도에 그대로 마커로 찍을 수 있다.
class CourseFacility {
  const CourseFacility({
    this.name,
    required this.address,
    required this.lat,
    required this.lng,
  });

  /// 표시용 이름(예: "송악산 공영주차장"). 없으면 주소만 보여준다.
  final String? name;
  final String address;
  final double lat;
  final double lng;

  factory CourseFacility.fromJson(Map<String, dynamic> json) => CourseFacility(
    name: json['name'] as String?,
    address: json['address'] as String,
    lat: (json['lat'] as num).toDouble(),
    lng: (json['lng'] as num).toDouble(),
  );

  /// 서버는 name이 null이어도 받는다(Facility.name 기본값 None). 굳이 null을
  /// 실어 보내지 않고 값이 있을 때만 넣는다.
  Map<String, dynamic> toJson() => {
    if (name != null) 'name': name,
    'address': address,
    'lat': lat,
    'lng': lng,
  };
}

/// 등록 폼의 편의시설 입력 한 줄. 화면이 자기 컨트롤러 값을 이 형태로 모아
/// [collectFacilities]에 넘긴다 — 검증 로직을 위젯에서 떼어내 테스트하기 위함이다.
class FacilityFormEntry {
  const FacilityFormEntry({
    required this.name,
    required this.address,
    this.confirmed,
  });

  /// 앞뒤 공백을 제거한 값이어야 한다.
  final String name;
  final String address;

  /// "확인"을 눌러 좌표를 확보했으면 그 결과. 주소를 다시 고치면 화면이 null로
  /// 되돌려, 좌표와 주소가 어긋난 채 제출되는 것을 막는다.
  final CourseFacility? confirmed;

  bool get isBlank => name.isEmpty && address.isEmpty;
}

/// 입력이 아직 제출할 수 없는 상태일 때(주소 누락 / 좌표 미확인) 던진다.
/// 화면이 message를 그대로 사용자에게 보여준다.
class FacilityInputException implements Exception {
  FacilityInputException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 폼 입력들을 업로드할 편의시설 목록으로 바꾼다.
///
/// - 완전히 빈 줄은 무시한다(추가만 하고 안 채운 행).
/// - 주소는 있는데 "확인"을 안 눌렀으면(좌표 없음) 제출을 막는다 — 좌표 없는
///   시설은 지도에 찍을 수 없기 때문이다.
List<CourseFacility> collectFacilities(
  List<FacilityFormEntry> entries, {
  required String label,
}) {
  final result = <CourseFacility>[];

  for (final entry in entries) {
    if (entry.isBlank) continue;

    if (entry.address.isEmpty) {
      throw FacilityInputException('$label 주소를 입력하거나 빈 칸을 지워 주세요.');
    }
    if (entry.confirmed == null) {
      throw FacilityInputException("$label '${entry.address}'는 '확인'을 눌러 주소를 확인해 주세요.");
    }

    // 좌표는 확인 결과에서, 이름/주소는 현재 입력값에서 가져온다.
    result.add(
      CourseFacility(
        name: entry.name.isEmpty ? null : entry.name,
        address: entry.address,
        lat: entry.confirmed!.lat,
        lng: entry.confirmed!.lng,
      ),
    );
  }

  return result;
}
