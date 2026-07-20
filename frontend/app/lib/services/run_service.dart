import '../api/run_api.dart';
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
      throw RunException('러닝 기록 저장에 실패했어요. 잠시 후 다시 시도해 주세요.', e);
    }
  }

  Future<List<RunRecord>> loadMyRecords({int limit = 20}) async {
    try {
      return await _runApi.fetchMyRecords(limit: limit);
    } catch (e) {
      throw RunException('러닝 기록을 불러오지 못했어요.', e);
    }
  }
}

class RunException implements Exception {
  RunException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}
