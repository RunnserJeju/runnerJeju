import '../api/partner_api.dart';
import '../exceptions/app_exception.dart';
import '../models/course_partner.dart';

/// 비즈니스 로직 계층: 협력업체 조회. UI가 이해할 수 있는 형태로 오류를 바꿔준다.
class PartnerService {
  PartnerService(this._partnerApi);

  final PartnerApi _partnerApi;

  Future<List<CoursePartner>> loadPartners() async {
    try {
      return await _partnerApi.fetchPartners();
    } catch (e) {
      throw AppException('협력업체를 불러오지 못했어요.', e);
    }
  }
}
