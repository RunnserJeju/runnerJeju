/// 홈 화면에 노출되는 공지사항. [imageUrl]이 있으면 상단 배너 캐러셀에도 실린다.
///
/// 노출 기간(startsAt/endsAt) 필터링은 서버가 한다 — 앱은 지금 노출 중인 공지만
/// 받는다. 그래도 기간을 파싱해 두는 건 상세 표기 등 나중 쓰임을 위해서다.
class Notice {
  const Notice({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.imageUrl,
    this.link,
    this.linkLabel,
    this.startsAt,
    this.endsAt,
  });

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;

  /// 배너 이미지. null이면 텍스트 공지만.
  final String? imageUrl;

  bool get hasImage => imageUrl != null;

  /// 상세 아래 버튼이 갈 곳. 없거나 이 앱 버전이 모르는 화면이면 null(버튼 없음).
  final NoticeLink? link;

  /// 버튼 문구. null이면 [NoticeLink.defaultLabel].
  final String? linkLabel;

  /// 노출 기간. null이면 제한 없음(상시).
  final DateTime? startsAt;
  final DateTime? endsAt;

  factory Notice.fromJson(Map<String, dynamic> json) => Notice(
    id: json['id'].toString(),
    title: json['title'] as String,
    body: json['body'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
    imageUrl: json['image_url'] as String?,
    link: NoticeLink.parse(json['link_url'] as String?),
    linkLabel: json['link_label'] as String?,
    startsAt: json['starts_at'] == null
        ? null
        : DateTime.parse(json['starts_at'] as String),
    endsAt: json['ends_at'] == null
        ? null
        : DateTime.parse(json['ends_at'] as String),
  );
}

/// 공지 버튼의 연결 대상. 서버 `notices.link_url` 값 —
/// 외부 주소(운영툴 입력) 또는 `app:화면`(개발자가 DB에 직접 넣음).
sealed class NoticeLink {
  const NoticeLink();

  String get defaultLabel;

  static NoticeLink? parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (raw == 'app:running-week') return const RunningWeekLink();
    final uri = Uri.tryParse(raw);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return ExternalLink(uri);
    }
    return null;
  }
}

class ExternalLink extends NoticeLink {
  const ExternalLink(this.uri);

  final Uri uri;

  @override
  String get defaultLabel => '자세히 보기';
}

class RunningWeekLink extends NoticeLink {
  const RunningWeekLink();

  @override
  String get defaultLabel => '러닝위크 보러 가기';
}
