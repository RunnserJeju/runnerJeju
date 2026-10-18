import '../models/home_curation.dart';
import '../network/api_client.dart';

/// API 계층: 홈 구성 엔드포인트. 편집은 운영 웹 몫이라 조회뿐이다.
class HomeApi {
  HomeApi(this._client);

  final ApiClient _client;

  Future<HomeCuration> fetchCuration() async {
    final response = await _client.dio.get('/home/curation');
    return HomeCuration.fromJson(response.data as Map<String, dynamic>);
  }
}
