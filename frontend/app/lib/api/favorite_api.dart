import '../models/running_course.dart';
import '../network/api_client.dart';
import '../network/json.dart';

/// API 계층: 코스 찜 관련 서버 엔드포인트.
class FavoriteApi {
  FavoriteApi(this._client);

  final ApiClient _client;

  /// 내가 찜한 코스 목록. 응답은 코스 목록(GET /courses)과 같은 형태다.
  Future<List<RunningCourse>> fetchFavorites() async {
    final response = await _client.dio.get('/favorites');

    return parseList(response.data, RunningCourse.fromJson);
  }

  /// 코스를 찜한다. 서버가 멱등이라 이미 찜한 코스여도 성공한다.
  Future<void> addFavorite(String courseId) async {
    await _client.dio.post('/favorites/$courseId');
  }

  /// 찜을 해제한다. 찜하지 않은 코스여도 성공한다(멱등).
  Future<void> removeFavorite(String courseId) async {
    await _client.dio.delete('/favorites/$courseId');
  }
}
