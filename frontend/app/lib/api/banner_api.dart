import '../models/home_banner.dart';
import '../network/api_client.dart';

/// API 계층: 홈 화면 배너 관련 서버 엔드포인트.
class BannerApi {
  BannerApi(this._client);

  final ApiClient _client;

  Future<List<HomeBanner>> fetchBanners() async {
    final response = await _client.dio.get('/banners');

    return (response.data as List)
        .map((e) => HomeBanner.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
