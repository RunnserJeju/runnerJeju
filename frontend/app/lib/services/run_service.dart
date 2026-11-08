import 'package:dio/dio.dart';

import '../api/run_api.dart';
import '../exceptions/app_exception.dart';
import '../models/run_record.dart';

/// 비즈니스 로직 계층: 러닝 기록 업로드/조회.
class RunService {
  RunService(this._runApi);

  final RunApi _runApi;

  /// 완료된 러닝을 서버에 올린다. 완주 조건을 만족하면 결과에 스탬프 id가 담긴다.
  ///
  /// 이어달리기 구간이면 원래 기록 뒤에 붙인다. 서버가 붙이기를 거절하면(원래 기록이
  /// 그새 완주됐거나 사라짐) 구간을 따로 저장한다 — 달린 기록을 잃는 것보다 낫다.
  Future<RunUploadResult> saveRecord(RunRecord record) async {
    try {
      if (record.isContinuation) {
        try {
          return await _runApi.continueRecord(record);
        } on DioException catch (e) {
          if (!_isRejected(e)) rethrow;
        }
        return await _runApi.uploadRecord(record.asStandalone());
      }
      return await _runApi.uploadRecord(record);
    } catch (e) {
      throw AppException('러닝 기록 저장에 실패했어요. 잠시 후 다시 시도해 주세요.', e);
    }
  }

  /// 다시 보내도 같은 답이 올 거절인지(네트워크·서버 오류가 아닌지).
  static bool _isRejected(DioException e) =>
      const {404, 409, 422}.contains(e.response?.statusCode);

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

  /// 이어 달릴 수 있는 미완주 기록(최근 7일, 최근 순).
  Future<List<RunRecord>> loadContinuableRecords({int limit = 20}) async {
    try {
      return await _runApi.fetchContinuableRecords(limit: limit);
    } catch (e) {
      throw AppException('미완주 기록을 불러오지 못했어요.', e);
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
