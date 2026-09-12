/// JSON 배열 응답을 모델 목록으로 바꾼다. null이거나 배열이 아니면 빈 목록.
List<T> parseList<T>(
  dynamic data,
  T Function(Map<String, dynamic> json) fromJson,
) => [
  for (final item in (data as List?) ?? const [])
    fromJson(item as Map<String, dynamic>),
];
