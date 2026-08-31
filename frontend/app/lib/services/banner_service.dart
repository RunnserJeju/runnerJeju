import '../api/banner_api.dart';
import '../exceptions/app_exception.dart';
import '../models/home_banner.dart';

/// 비즈니스 로직 계층: 홈 화면 배너 조회.
class BannerService {
  BannerService(this._bannerApi);

  final BannerApi _bannerApi;

  Future<List<HomeBanner>> loadBanners() async {
    try {
      return await _bannerApi.fetchBanners();
    } catch (e) {
      throw AppException('배너를 불러오지 못했어요.', e);
    }
  }
}
