/// 현재 로그인한 사용자.
///
/// [role]은 서버 응답을 그대로 담아둘 뿐 앱에서 쓰지 않는다 — 운영 기능은
/// 전부 운영자 웹으로 옮겼다(docs/admin-web.md).
class User {
  const User({
    required this.id,
    required this.role,
    this.nickname,
    this.email,
    this.profileImageUrl,
    this.createdAt,
  });

  final String id;
  final String role;
  final String? nickname;
  final String? email;
  final String? profileImageUrl;

  /// 가입일.
  final DateTime? createdAt;

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'].toString(),
    role: json['role'] as String? ?? 'user',
    nickname: json['nickname'] as String?,
    email: json['email'] as String?,
    profileImageUrl: json['profile_image_url'] as String?,
    createdAt: json['created_at'] == null
        ? null
        : DateTime.parse(json['created_at'] as String),
  );
}
