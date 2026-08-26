import '../api/favorite_api.dart';
import '../exceptions/app_exception.dart';
import '../models/running_course.dart';

/// 코스 찜.
///
/// 서버에 저장한다 — 기기를 바꾸거나 재설치해도 찜이 유지된다.
class FavoriteService {
  FavoriteService(this._api);

  final FavoriteApi _api;

  /// 찜한 코스를 코스 정보와 함께 돌려준다(찜한 순서, 최근이 위).
  Future<List<RunningCourse>> loadFavoriteCourses() async {
    try {
      return await _api.fetchFavorites();
    } catch (e) {
      throw AppException('찜한 코스를 불러오지 못했어요.', e);
    }
  }

  /// 찜한 코스 id 집합. 찜 목록에서 뽑아낸다.
  Future<Set<String>> loadFavoriteIds() async {
    final courses = await loadFavoriteCourses();
    return courses.map((c) => c.id).toSet();
  }

  Future<bool> isFavorite(String courseId) async =>
      (await loadFavoriteIds()).contains(courseId);

  /// 찜을 토글하고 토글 후의 찜 여부를 돌려준다.
  Future<bool> toggle(String courseId) async {
    final currently = await isFavorite(courseId);
    try {
      if (currently) {
        await _api.removeFavorite(courseId);
        return false;
      }
      await _api.addFavorite(courseId);
      return true;
    } catch (e) {
      throw AppException('찜 상태를 바꾸지 못했어요.', e);
    }
  }
}
