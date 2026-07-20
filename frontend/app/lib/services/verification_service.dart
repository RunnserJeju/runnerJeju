import '../api/verification_api.dart';
import '../models/run_verification.dart';

/// 비즈니스 로직 계층: 경로 검증 요청과 결과 대기.
///
/// 지금은 FastAPI가 검증까지 동기로 처리해 첫 응답이 바로 terminal 상태로 온다.
/// 검증 서버가 분리되면 pending으로 돌아오기 시작하는데, 그때는 [awaitResult]의
/// 폴링이 그대로 동작하므로 화면 코드는 바뀌지 않는다.
class VerificationService {
  VerificationService(this._verificationApi);

  final VerificationApi _verificationApi;

  /// 폴링 간격. 검증 서버 분리 후 실제 연산 시간에 맞춰 조정한다.
  static const Duration _pollInterval = Duration(seconds: 2);

  /// 폴링을 포기하는 시점. 초과하면 마지막으로 받은 상태를 그대로 돌려준다.
  static const Duration _pollTimeout = Duration(seconds: 60);

  /// 검증을 요청하고 결과가 확정될 때까지 기다린다.
  Future<RunVerification> verify({
    required String runId,
    required String courseId,
  }) async {
    final RunVerification requested;
    try {
      requested = await _verificationApi.requestVerification(
        runId: runId,
        courseId: courseId,
      );
    } catch (e) {
      throw VerificationException('경로 검증을 요청하지 못했어요.', e);
    }

    if (requested.status.isTerminal) return requested;

    return awaitResult(requested);
  }

  /// pending 상태의 검증이 끝날 때까지 폴링한다.
  Future<RunVerification> awaitResult(RunVerification verification) async {
    var latest = verification;
    final deadline = DateTime.now().add(_pollTimeout);

    while (latest.status.isPending && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(_pollInterval);

      try {
        latest = await _verificationApi.fetchVerification(latest.id);
      } catch (e) {
        throw VerificationException('검증 결과를 확인하지 못했어요.', e);
      }
    }

    return latest;
  }
}

class VerificationException implements Exception {
  VerificationException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}
