import '../api/banner_api.dart';
import '../exceptions/app_exception.dart';
import '../models/home_banner.dart';

/// 비즈니스 로직 계층: 홈 화면 배너 조회/등록.
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

  Future<HomeBanner> uploadBanner({
    required List<int> bytes,
    required String filename,
  }) async {
    if (bytes.isEmpty) {
      throw AppException('이미지 파일이 비어 있어요.');
    }

    try {
      return await _bannerApi.uploadBanner(bytes: bytes, filename: filename);
    } catch (e) {
      throw AppException('배너 등록에 실패했어요.', e);
    }
  }

  Future<void> deleteBanner(String id) async {
    try {
      await _bannerApi.deleteBanner(id);
    } catch (e) {
      throw AppException('배너 삭제에 실패했어요.', e);
    }
  }
}
