/// 공지 카테고리. [key]는 서버 `notices.category`(고정 5종)와 값이 같아야 한다.
/// 라벨은 앱이 가지며(서버는 키만 저장), 알 수 없는 값이 오면 [etc]로 떨어진다.
enum NoticeCategory {
  appGuide('app_guide', '이용 안내'),
  newCourse('new_course', '신규 코스'),
  event('event', '이벤트'),
  maintenance('maintenance', '점검'),
  etc('etc', '기타');

  const NoticeCategory(this.key, this.label);

  final String key;
  final String label;

  static NoticeCategory fromKey(String? key) => values.firstWhere(
    (c) => c.key == key,
    orElse: () => NoticeCategory.etc,
  );
}

/// 홈 화면에 노출되는 공지사항.
///
/// 노출 기간(startsAt/endsAt) 필터링은 서버가 한다 — 앱은 지금 노출 중인 공지만
/// 받는다. 그래도 기간을 파싱해 두는 건 상세 표기 등 나중 쓰임을 위해서다.
class Notice {
  const Notice({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.createdAt,
    this.startsAt,
    this.endsAt,
  });

  final String id;
  final String title;
  final String body;
  final NoticeCategory category;
  final DateTime createdAt;

  /// 노출 기간. null이면 제한 없음(상시).
  final DateTime? startsAt;
  final DateTime? endsAt;

  factory Notice.fromJson(Map<String, dynamic> json) => Notice(
    id: json['id'].toString(),
    title: json['title'] as String,
    body: json['body'] as String,
    category: NoticeCategory.fromKey(json['category'] as String?),
    createdAt: DateTime.parse(json['created_at'] as String),
    startsAt: json['starts_at'] == null
        ? null
        : DateTime.parse(json['starts_at'] as String),
    endsAt: json['ends_at'] == null
        ? null
        : DateTime.parse(json['ends_at'] as String),
  );
}
