import '../api/stamp_api.dart';
import '../models/run_stamp.dart';

/// 비즈니스 로직 계층: 완주 스탬프 조회.
class StampService {
  StampService(this._stampApi);

  final StampApi _stampApi;

  Future<List<RunStamp>> loadMyStamps() async {
    try {
      final stamps = await _stampApi.fetchMyStamps();
      stamps.sort((a, b) => b.acquiredAt.compareTo(a.acquiredAt));
      return stamps;
    } catch (e) {
      throw StampException('스탬프를 불러오지 못했어요.', e);
    }
  }

  Future<RunStamp> loadStamp(String stampId) async {
    try {
      return await _stampApi.fetchStamp(stampId);
    } catch (e) {
      throw StampException('스탬프 정보를 불러오지 못했어요.', e);
    }
  }
}

class StampException implements Exception {
  StampException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}
