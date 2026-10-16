import '../api/home_api.dart';
import '../exceptions/app_exception.dart';
import '../models/home_curation.dart';

/// 비즈니스 로직 계층: 홈 구성 조회.
class HomeService {
  HomeService(this._homeApi);

  final HomeApi _homeApi;

  Future<HomeCuration> loadCuration() async {
    try {
      return await _homeApi.fetchCuration();
    } catch (e) {
      throw AppException('홈 구성을 불러오지 못했어요.', e);
    }
  }
}
