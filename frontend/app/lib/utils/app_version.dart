/// "2.3.0" 같은 버전 비교. 빌드 번호("+19")는 보지 않는다.
abstract final class AppVersion {
  /// [current]가 [minimum]보다 낮으면 true. 어느 쪽이든 읽을 수 없으면 false(막지 않는다).
  static bool isBelow(String current, String minimum) {
    final a = _parse(current);
    final b = _parse(minimum);
    if (a == null || b == null) return false;

    for (var i = 0; i < a.length || i < b.length; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x < y;
    }
    return false;
  }

  static List<int>? _parse(String version) {
    final parts = version.split('+').first.trim().split('.');
    final numbers = [for (final part in parts) int.tryParse(part)];
    if (numbers.isEmpty || numbers.contains(null)) return null;
    return numbers.cast<int>();
  }
}
