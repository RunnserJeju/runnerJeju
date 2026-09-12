import 'package:intl/intl.dart';

/// 러닝 지표를 화면 문자열로 바꾸는 포매터 모음.
class Formatters {
  const Formatters._();

  /// 미터 → "5.23" (km 단위 문자열, 단위 기호는 붙이지 않는다)
  static String distanceKm(double meters) =>
      (meters / 1000).toStringAsFixed(2);

  /// 미터 → "320m" / "1.2km". 얼마나 떨어져 있는지 한 줄로 말할 때 쓴다.
  /// [distanceKm]와 달리 단위를 붙이고, 가까우면 m로 말한다.
  static String awayDistance(double meters) => meters < 1000
      ? '${meters.round()}m'
      : '${(meters / 1000).toStringAsFixed(1)}km';

  /// 초 → "00:32:41" 또는 "32:41"
  static String duration(Duration elapsed) {
    final h = elapsed.inHours;
    final m = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '${h.toString().padLeft(2, '0')}:$m:$s' : '$m:$s';
  }

  /// km당 초 → "5'42\"". 계산 불가하면 "--'--\""
  static String pace(double? secondsPerKm) {
    if (secondsPerKm == null || secondsPerKm.isInfinite || secondsPerKm.isNaN) {
      return "--'--\"";
    }
    final total = secondsPerKm.round();
    final m = total ~/ 60;
    final s = (total % 60).toString().padLeft(2, '0');
    return "$m'$s\"";
  }

  static String date(DateTime value) =>
      DateFormat('yyyy.MM.dd').format(value.toLocal());

  /// "7.28" — 스탬프 카드처럼 좁은 자리용.
  static String monthDay(DateTime value) =>
      DateFormat('M.d').format(value.toLocal());

  static String dateTime(DateTime value) =>
      DateFormat('yyyy.MM.dd HH:mm').format(value.toLocal());
}
