import '../api/favorite_api.dart';
import '../exceptions/app_exception.dart';
import '../models/running_course.dart';

/// 코스 찜.
///
/// 서버에 저장한다 — 기기를 바꾸거나 재설치해도 찜이 유지된다. 찜 여부 확인은
/// 잦고(코스를 누를 때마다) 서버 응답은 코스 전체라, id 집합을 세션 동안 캐시한다.
class FavoriteService {
  FavoriteService(this._api);

  final FavoriteApi _api;

  Set<String>? _ids;

  /// 찜한 코스를 코스 정보와 함께 돌려준다(찜한 순서, 최근이 위).
  Future<List<RunningCourse>> loadFavoriteCourses() async {
    try {
      final courses = await _api.fetchFavorites();
      _ids = {for (final c in courses) c.id};
      return courses;
    } catch (e) {
      throw AppException('찜한 코스를 불러오지 못했어요.', e);
    }
  }

  Future<bool> isFavorite(String courseId) async {
    final ids = _ids ?? {for (final c in await loadFavoriteCourses()) c.id};
    return ids.contains(courseId);
  }

  /// 찜을 토글하고 토글 후의 찜 여부를 돌려준다. 화면이 현재 상태를 알고 있으면
  /// [currently]로 넘겨 조회를 건너뛴다.
  Future<bool> toggle(String courseId, {bool? currently}) async {
    try {
      final was = currently ?? await isFavorite(courseId);
      if (was) {
        await _api.removeFavorite(courseId);
      } else {
        await _api.addFavorite(courseId);
      }
      was ? _ids?.remove(courseId) : _ids?.add(courseId);
      return !was;
    } on AppException {
      rethrow;
    } catch (e) {
      throw AppException('찜 상태를 바꾸지 못했어요.', e);
    }
  }
}
