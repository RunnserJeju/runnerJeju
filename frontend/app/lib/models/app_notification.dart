/// 알림함의 알림 한 건(서버 `GET /notifications`).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.link,
    required this.readAt,
    required this.createdAt,
  });

  final String id;
  final String type;
  final String title;
  final String body;

  /// 눌렀을 때 열 화면(`app:stamps` 등). 없으면 홈.
  final String? link;
  final DateTime? readAt;
  final DateTime createdAt;

  bool get isRead => readAt != null;

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as String,
        type: json['type'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        link: json['link_url'] as String?,
        readAt: json['read_at'] == null
            ? null
            : DateTime.parse(json['read_at'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

/// 기기의 OS 알림 권한. 서버 `device_tokens.permission`과 같은 값이다.
enum PushPermission {
  authorized('authorized'),
  denied('denied'),
  notDetermined('not_determined');

  const PushPermission(this.wire);

  final String wire;
}
