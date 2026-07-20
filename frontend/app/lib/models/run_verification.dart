/// 경로 검증 상태.
///
/// 검증은 CPU를 오래 쓰는 GPX 비교 연산이라 언젠가 별도 검증 서버로 분리된다.
/// 그때 응답이 비동기가 되어도 클라이언트가 바뀌지 않도록, 지금부터
/// `pending`/`inProgress`를 포함한 비동기 상태 모델을 쓴다.
enum VerificationStatus {
  /// 검증 요청이 접수됐고 아직 시작되지 않음.
  pending('검증 대기 중'),

  /// 검증 연산이 진행 중.
  inProgress('경로를 검증하는 중'),

  /// 코스대로 달린 것으로 확인됨.
  matched('코스 완주가 확인됐어요'),

  /// 경로가 코스와 충분히 일치하지 않음.
  mismatched('코스와 경로가 달라요'),

  /// 검증 자체가 실패(서버 오류 등). 재시도 가능.
  failed('검증에 실패했어요');

  const VerificationStatus(this.message);

  final String message;

  /// 더 이상 폴링할 필요가 없는 상태.
  bool get isTerminal =>
      this == matched || this == mismatched || this == failed;

  bool get isPending => !isTerminal;

  static VerificationStatus fromName(String? name) =>
      VerificationStatus.values.firstWhere(
        (e) => e.name == name,
        orElse: () => VerificationStatus.failed,
      );
}

/// 러닝 경로가 코스와 일치하는지에 대한 검증 결과.
class RunVerification {
  const RunVerification({
    required this.id,
    required this.runId,
    required this.courseId,
    required this.status,
    this.matchRate,
    this.detail,
    this.completedAt,
  });

  final String id;
  final String runId;
  final String courseId;
  final VerificationStatus status;

  /// 코스와의 일치율 0.0~1.0. 검증이 끝나기 전에는 null.
  final double? matchRate;

  /// 서버가 내려주는 부가 설명(예: 이탈 구간 안내).
  final String? detail;

  final DateTime? completedAt;

  bool get isMatched => status == VerificationStatus.matched;

  /// 일치율을 백분율 문자열로. 아직 없으면 null.
  String? get matchRateLabel =>
      matchRate == null ? null : '${(matchRate! * 100).round()}%';

  factory RunVerification.fromJson(Map<String, dynamic> json) =>
      RunVerification(
        id: json['id'].toString(),
        runId: json['run_id'].toString(),
        courseId: json['course_id'].toString(),
        status: VerificationStatus.fromName(json['status'] as String?),
        matchRate: (json['match_rate'] as num?)?.toDouble(),
        detail: json['detail'] as String?,
        completedAt: json['completed_at'] == null
            ? null
            : DateTime.parse(json['completed_at'] as String),
      );
}
