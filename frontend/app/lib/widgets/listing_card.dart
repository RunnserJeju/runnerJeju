import 'package:flutter/material.dart';

/// 목록 카드의 공통 틀: 왼쪽 정사각 썸네일 + 제목 줄 + 한 줄 부제 + 바닥 한 줄.
///
/// 코스 목록([CourseCard])과 협력업체 목록([PartnerCard])이 같은 틀을 써서 두 목록이
/// 같은 밀도로 보인다. 카드 높이는 썸네일 한 변으로 고정된다 — 내용이 몇 줄이든
/// 모든 카드가 같은 높이다.
class ListingCard extends StatelessWidget {
  const ListingCard({
    super.key,
    required this.thumbnail,
    required this.title,
    this.titleTrailing = const [],
    this.subtitle,
    this.subtitleStyle,
    this.footer,
    this.onTap,
  });

  /// 썸네일 한 변. 카드 내용 높이도 이 값이다.
  static const double thumbnailSize = 96;

  /// 정사각 썸네일 자리를 꽉 채우는 위젯(이미지나 아이콘 타일).
  final Widget thumbnail;
  final String title;

  /// 제목 오른쪽에 붙는 작은 것들(완주 표시, 거리 등).
  final List<Widget> titleTrailing;

  /// 제목 아래 한 줄. 넘치면 말줄임.
  final String? subtitle;
  final TextStyle? subtitleStyle;

  /// 카드 바닥 한 줄(태그 칩, 주소 등). 높이 30에 맞춰 그린다.
  final Widget? footer;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = this.subtitle;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            height: thumbnailSize,
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox.square(dimension: thumbnailSize, child: thumbnail),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          ...titleTrailing,
                        ],
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              subtitleStyle ??
                              theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                              ),
                        ),
                      ],
                      const Spacer(),
                      if (footer != null)
                        // 높이를 한 줄로 고정한다. 넘치는 내용은 ClipRect가 숨긴다 —
                        // 전체는 상세 시트에서 보인다.
                        SizedBox(height: 30, child: ClipRect(child: footer)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
