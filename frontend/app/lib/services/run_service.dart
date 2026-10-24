import '../api/run_api.dart';
import '../exceptions/app_exception.dart';
import '../models/run_record.dart';

/// 비즈니스 로직 계층: 러닝 기록 업로드/조회.
class RunService {
  RunService(this._runApi);

  final RunApi _runApi;

  /// 완료된 러닝을 서버에 올린다. 완주 조건을 만족하면 결과에 스탬프 id가 담긴다.
  Future<RunUploadResult> saveRecord(RunRecord record) async {
    try {
      return await _runApi.uploadRecord(record);
    } catch (e) {
      throw AppException('러닝 기록 저장에 실패했어요. 잠시 후 다시 시도해 주세요.', e);
    }
  }

  Future<List<RunRecord>> loadMyRecords({
    int limit = 20,
    DateTime? since,
    DateTime? until,
    bool withPath = true,
  }) async {
    try {
      return await _runApi.fetchMyRecords(
        limit: limit,
        since: since,
        until: until,
        withPath: withPath,
      );
    } catch (e) {
      throw AppException('러닝 기록을 불러오지 못했어요.', e);
    }
  }

  /// 경로까지 담긴 기록 하나. 경로 없이 받은 기록의 상세를 열 때 쓴다.
  Future<RunRecord> loadRecord(String id) async {
    try {
      return await _runApi.fetchRecord(id);
    } catch (e) {
      throw AppException('러닝 기록을 불러오지 못했어요.', e);
    }
  }
}
