import '../models/course_partner.dart';
import '../network/api_client.dart';
import '../network/conditional.dart';
import '../network/json.dart';

/// API 계층: 협력업체 엔드포인트. 등록·수정은 운영 웹 몫이라 조회뿐이다.
class PartnerApi {
  PartnerApi(this._client);

  final ApiClient _client;

  /// 협력업체 전체(이름순). 항목마다 연결된 코스가 붙어 온다.
  Future<Conditional<List<CoursePartner>>> fetchPartners({String? etag}) =>
      _client.getConditional(
        '/partners',
        etag: etag,
        parse: (data) => parseList(data, CoursePartner.fromJson),
      );
}
