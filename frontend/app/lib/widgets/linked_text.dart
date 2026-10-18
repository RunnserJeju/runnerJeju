import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

/// 본문 속 링크를 눌러 열 수 있게 그리는 텍스트.
///
/// 운영툴에서 넣는 두 형태를 링크로 본다.
/// - 주소를 그대로 붙여 넣은 것: `https://example.com`
/// - 글자에 링크를 건 것: `[신청하기](https://example.com)` → "신청하기"만 보인다
///
/// 누르면 외부 브라우저(또는 그 주소를 받는 앱)로 연다.
class LinkedText extends StatefulWidget {
  const LinkedText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  State<LinkedText> createState() => _LinkedTextState();

  /// 본문에서 링크 문법을 걷어 글자만 남긴다. 목록 미리보기처럼 누를 수 없는
  /// 자리에서 쓴다. [신청하기](https://…) → 신청하기. 맨 주소는 그대로 둔다.
  static String plainText(String text) =>
      text.replaceAllMapped(_pattern, (m) => m[1] ?? m[0]!);

  // [글자](주소) 또는 맨 주소. 주소는 http(s)만 받는다.
  static final _pattern = RegExp(
    r'\[([^\]\n]+)\]\((https?://[^\s)]+)\)|(https?://[^\s<>"]+)',
  );
}

class _LinkedTextState extends State<LinkedText> {
  // 문장 끝 마침표·쉼표·닫는 괄호는 주소가 아니다. 괄호는 짝이 안 맞을 때만 뗀다 —
  // 위키 문서 제목처럼 주소 자체가 ")"로 끝나는 경우가 있다.
  static final _trailing = RegExp(r'[.,!?;:\])]+$');

  static String _stripTrailing(String raw) {
    var url = raw.replaceFirst(_trailing, '');
    final cut = raw.substring(url.length);
    // 뗀 꼬리 앞쪽의 ")"는, 주소 안의 "("보다 ")"가 적은 동안 되돌린다.
    var opens = '('.allMatches(url).length;
    var closes = ')'.allMatches(url).length;
    var i = 0;
    while (i < cut.length && cut[i] == ')' && closes < opens) {
      url += ')';
      closes++;
      i++;
    }
    return url;
  }

  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('링크를 열지 못했어요.')));
    }
  }

  TextSpan _link(String label, String url) {
    final recognizer = TapGestureRecognizer()..onTap = () => _open(url);
    _recognizers.add(recognizer);
    return TextSpan(
      text: label,
      recognizer: recognizer,
      style: const TextStyle(
        color: AppColors.tintBlue,
        decoration: TextDecoration.underline,
        decorationColor: AppColors.tintBlue,
      ),
    );
  }

  List<InlineSpan> _spans(String text) {
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in LinkedText._pattern.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      if (match.group(1) case final label?) {
        spans.add(_link(label, match.group(2)!));
      } else {
        final raw = match.group(3)!;
        final url = _stripTrailing(raw);
        spans.add(_link(url, url));
        // 떼어 낸 문장부호는 일반 글자로 돌려준다.
        if (url.length < raw.length) {
          spans.add(TextSpan(text: raw.substring(url.length)));
        }
      }
      cursor = match.end;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    // 다시 그릴 때마다 링크 인식기를 새로 만든다. 옛 것은 여기서 버린다.
    _disposeRecognizers();
    return Text.rich(
      TextSpan(style: widget.style, children: _spans(widget.text)),
    );
  }
}
