import 'package:dio/dio.dart';

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

  /// 이미지 파일로 배너를 등록한다. **관리자 전용**(서버가 require_admin으로 막는다).
  Future<HomeBanner> uploadBanner({
    required List<int> bytes,
    required String filename,
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });

    final response = await _client.dio.post(
      '/banners',
      data: formData,
      options: Options(sendTimeout: const Duration(seconds: 30)),
    );

    return HomeBanner.fromJson(response.data as Map<String, dynamic>);
  }

  /// **관리자 전용**(서버가 require_admin으로 막는다).
  Future<void> deleteBanner(String id) async {
    await _client.dio.delete('/banners/$id');
  }
}
