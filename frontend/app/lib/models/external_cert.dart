/// 가민·순토 링크로 한 코스 완주 인증의 결과.
enum ExternalCertOutcome {
  /// 통과. 스탬프를 받았다.
  granted,

  /// 이미 완주한 코스라 링크를 확인하지 않았다.
  alreadyCompleted,

  /// 이미 인증에 쓰인 링크.
  activityUsed,

  /// 경로가 코스와 충분히 일치하지 않는다([ExternalCertResult.matchRate]).
  mismatched,

  /// 링크에서 운동 경로를 읽지 못했다(비공개·삭제·GPS 없음·상대 서비스 장애).
  unreadable,
}

class ExternalCertResult {
  const ExternalCertResult(this.outcome, {this.matchRate, this.source});

  final ExternalCertOutcome outcome;

  /// 코스와의 일치율 0.0~1.0. 판정까지 간 경우에만 있다.
  final double? matchRate;

  /// 'garmin' | 'suunto'. 링크를 읽기 전에 끝났으면 null.
  final String? source;

  /// 일치율을 소수점 버린 백분율로(서버 안내 문구와 같은 기준이 되게 반올림).
  int? get matchPercent =>
      matchRate == null ? null : (matchRate! * 100).round();

  String? get sourceLabel => switch (source) {
    'garmin' => 'Garmin',
    'suunto' => 'Suunto',
    _ => null,
  };
}
