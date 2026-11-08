/// 이어달리기 기간: 기록을 시작한 날(KST)을 포함해 7일째 되는 날까지.
///
/// 판정은 서버가 한다(run_continuation.py). 여기서는 남은 날을 보여주고, 기간이 지난
/// 기록에 이어달리기를 권하지 않는 데만 쓴다 — 그래서 기기 시간대가 아니라 서버와
/// 같은 KST 날짜로 센다.
class ContinuationWindow {
  const ContinuationWindow._();

  /// 오늘을 포함한 날 수. 서버 CONTINUABLE_DAYS와 같아야 한다.
  static const int days = 7;

  /// 이어 달릴 수 있는 마지막 날. KST 날짜를 UTC 자정에 담은 값이라 toLocal 없이 읽는다.
  static DateTime lastDay(DateTime startedAt) =>
      _kstDate(startedAt).add(const Duration(days: days - 1));

  /// 마지막 날까지 남은 날 수. 오늘이 마지막 날이면 0, 지났으면 음수.
  static int daysLeft(DateTime startedAt, {DateTime? now}) =>
      lastDay(startedAt).difference(_kstDate(now ?? DateTime.now())).inDays;

  static bool isOpen(DateTime startedAt, {DateTime? now}) =>
      daysLeft(startedAt, now: now) >= 0;

  static DateTime _kstDate(DateTime t) {
    final kst = t.toUtc().add(const Duration(hours: 9));
    return DateTime.utc(kst.year, kst.month, kst.day);
  }
}
