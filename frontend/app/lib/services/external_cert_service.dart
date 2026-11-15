import 'package:dio/dio.dart';

import '../api/external_cert_api.dart';
import '../exceptions/app_exception.dart';
import '../models/external_cert.dart';

/// 비즈니스 로직 계층: 가민·순토 링크로 코스 완주 인증.
class ExternalCertService {
  ExternalCertService(this._api);

  final ExternalCertApi _api;

  /// 인증을 요청하고 결과를 돌려준다. 결과 화면으로 풀 수 없는 실패(네트워크, 지원하지
  /// 않는 링크 등)만 [AppException]으로 던진다.
  Future<ExternalCertResult> certify({
    required String courseId,
    required String url,
  }) async {
    try {
      final json = await _api.submit(courseId: courseId, url: url);
      final outcome = switch (json['status']) {
        'matched' => ExternalCertOutcome.granted,
        'mismatched' => ExternalCertOutcome.mismatched,
        _ => ExternalCertOutcome.unreadable,
      };
      return ExternalCertResult(
        outcome,
        matchRate: (json['match_rate'] as num?)?.toDouble(),
        source: json['source'] as String?,
      );
    } on DioException catch (e) {
      final detail = e.response?.data is Map
          ? e.response?.data['detail']
          : null;
      // 409는 {code, message}로 온다.
      if (detail is Map) {
        switch (detail['code']) {
          case 'already_completed':
            return const ExternalCertResult(
              ExternalCertOutcome.alreadyCompleted,
            );
          case 'activity_used':
            return const ExternalCertResult(ExternalCertOutcome.activityUsed);
        }
      }
      if (e.response?.statusCode == 422) {
        throw AppException('Garmin 또는 Suunto의 운동 공유 링크를 넣어 주세요.', e);
      }
      throw AppException('인증을 요청하지 못했어요. 잠시 후 다시 시도해 주세요.', e);
    }
  }
}
