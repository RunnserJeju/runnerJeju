/// 현재 로그인한 사용자.
///
/// [role]은 admin 전용 UI를 보여줄지 정하는 데만 쓴다. 실제 권한 판정은 서버가
/// 하므로(관리자 전용 엔드포인트는 403으로 막힌다) 이 값을 믿고 화면을 정리할 뿐,
/// 여기에 보안을 기대지 않는다.
class User {
  const User({
    required this.id,
    required this.role,
    this.nickname,
    this.email,
    this.profileImageUrl,
  });

  final String id;
  final String role;
  final String? nickname;
  final String? email;
  final String? profileImageUrl;

  bool get isAdmin => role == 'admin';

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'].toString(),
    role: json['role'] as String? ?? 'user',
    nickname: json['nickname'] as String?,
    email: json['email'] as String?,
    profileImageUrl: json['profile_image_url'] as String?,
  );
}
