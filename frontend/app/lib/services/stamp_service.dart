import '../api/stamp_api.dart';
import '../exceptions/app_exception.dart';
import '../models/run_stamp.dart';
import 'cached_resource.dart';

/// 비즈니스 로직 계층: 스탬프 조회.
class StampService {
  StampService(this._stampApi);

  final StampApi _stampApi;

  Future<List<RunStamp>> loadMyStamps() async {
    try {
      final stamps = await _stampApi.fetchMyStamps();
      stamps.sort((a, b) => b.acquiredAt.compareTo(a.acquiredAt));
      return stamps;
    } catch (e) {
      throw AppException('스탬프를 불러오지 못했어요.', e);
    }
  }

  late final _definitions = CachedResource<List<StampDefinition>>(
    (etag) => _stampApi.fetchDefinitions(etag: etag),
  );

  Future<List<StampDefinition>> loadDefinitions({bool refresh = false}) async {
    try {
      return List.of(await _definitions.get(refresh: refresh));
    } catch (e) {
      throw AppException('스탬프를 불러오지 못했어요.', e);
    }
  }

  Future<RunStamp> loadStamp(String stampId) async {
    try {
      return await _stampApi.fetchStamp(stampId);
    } catch (e) {
      throw AppException('스탬프 정보를 불러오지 못했어요.', e);
    }
  }
}
