import 'package:flutter/material.dart';

import '../../models/course_partner.dart';
import '../../models/geo_point.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../utils/geo_utils.dart';
import '../../widgets/partner_category_tile.dart';
import '../../widgets/sheet_handle.dart';
import 'course_list_sheet.dart';

/// 협력업체 모드의 목록 시트. 코스 탐색 시트([CourseListSheet])와 같은 자리·높이를
/// 쓰고, 현위치에서 가까운 순으로 업체를 보여준다.
///
/// 지도(전체 협력업체 핀)와 이 시트는 같은 목록의 두 표현이다. 항목을 고르면 지도가
/// 그 업체로 옮겨 가고 상세([PartnerPreviewSheet])가 이 자리를 대신한다.
class PartnerListSheet extends StatefulWidget {
  const PartnerListSheet({
    super.key,
    required this.controller,
    required this.partners,
    required this.myPosition,
    required this.isLoading,
    required this.hasError,
    required this.onSelect,
    required this.onRetry,
    required this.onClose,
  });

  final DraggableScrollableController controller;
  final List<CoursePartner> partners;

  /// 정렬 기준이 되는 현위치. 없으면 서버가 준 순서(이름순) 그대로 보여준다.
  final GeoPoint? myPosition;

  final bool isLoading;
  final bool hasError;

  final ValueChanged<CoursePartner> onSelect;
  final VoidCallback onRetry;

  /// 협력업체 모드를 끈다(코스 탐색으로 돌아간다).
  final VoidCallback onClose;

  @override
  State<PartnerListSheet> createState() => _PartnerListSheetState();
}

class _PartnerListSheetState extends State<PartnerListSheet> {
  /// 거리순 목록과 그 기준 위치. 코스 시트와 같은 이유로, 기준에서
  /// [_resortDistance]보다 멀어졌을 때만 다시 줄 세운다(스크롤 중 뒤섞임 방지).
  List<({CoursePartner partner, double? distance})> _sorted = const [];
  GeoPoint? _anchor;

  static const double _resortDistance = 100;

  @override
  void initState() {
    super.initState();
    _resort();
  }

  @override
  void didUpdateWidget(covariant PartnerListSheet old) {
    super.didUpdateWidget(old);
    final me = widget.myPosition;
    final anchor = _anchor;
    final moved =
        me != null &&
        (anchor == null || GeoUtils.distanceBetween(anchor, me) > _resortDistance);
    if (!identical(old.partners, widget.partners) || moved) _resort();
  }

  void _resort() {
    final me = widget.myPosition;
    _anchor = me;
    _sorted = sortPartnersByDistance(widget.partners, me);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final peek = CourseListSheet.peekHeight / constraints.maxHeight;
        return DraggableScrollableSheet(
          controller: widget.controller,
          // 버튼을 눌러 연 시트라 접힌 채가 아니라 반쯤 펼친 채로 시작한다.
          initialChildSize: CourseListSheet.halfSize,
          minChildSize: peek,
          maxChildSize: CourseListSheet.fullSize,
          snap: true,
          snapSizes: const [CourseListSheet.halfSize],
          // 손잡이·제목도 스크롤 뷰 안에 둔다(CourseListSheet와 같은 이유).
          builder: (context, scrollController) => DecoratedBox(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(color: Colors.black12, blurRadius: 16, offset: Offset(0, -2)),
              ],
            ),
            child: CustomScrollView(
              controller: scrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      const SheetHandle(),
                      _Header(count: widget.partners.length, onClose: widget.onClose),
                      const Divider(height: 1, color: AppColors.lineSoft),
                    ],
                  ),
                ),
                _body(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _body() {
    if (_sorted.isEmpty) {
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
        sliver: SliverToBoxAdapter(child: _emptyState()),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      sliver: SliverList.separated(
        itemCount: _sorted.length,
        separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.lineSoft),
        itemBuilder: (context, index) {
          final item = _sorted[index];
          return PartnerListTile(
            partner: item.partner,
            distanceLabel: item.distance == null
                ? null
                : Formatters.awayDistance(item.distance!),
            onTap: () => widget.onSelect(item.partner),
          );
        },
      ),
    );
  }

  Widget _emptyState() {
    if (widget.isLoading) return const Center(child: CircularProgressIndicator());

    if (widget.hasError) {
      return Column(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 36, color: Color(0xFFC3C9D2)),
          const SizedBox(height: 12),
          const Text(
            '협력업체를 불러오지 못했어요',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: widget.onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('다시 시도'),
          ),
        ],
      );
    }

    return const Column(
      children: [
        Icon(Icons.storefront_rounded, size: 36, color: Color(0xFFC3C9D2)),
        SizedBox(height: 12),
        Text(
          '아직 등록된 협력업체가 없어요',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink),
        ),
      ],
    );
  }
}

/// [partners]를 [me]에서 가까운 순으로. 위치를 모르면 받은 순서 그대로(거리 null).
List<({CoursePartner partner, double? distance})> sortPartnersByDistance(
  List<CoursePartner> partners,
  GeoPoint? me,
) {
  final items = [
    for (final partner in partners)
      (
        partner: partner,
        distance: me == null ? null : GeoUtils.distanceBetween(me, partner.point),
      ),
  ];
  if (me != null) items.sort((a, b) => a.distance!.compareTo(b.distance!));
  return items;
}

class _Header extends StatelessWidget {
  const _Header({required this.count, required this.onClose});

  final int count;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
      child: Row(
        children: [
          const Text(
            '협력업체',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$count',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.muted,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
            tooltip: '협력업체 닫기',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

/// 협력업체 목록 한 줄: 업종 타일 + 이름·업종 + 혜택 + 주소(와 거리).
class PartnerListTile extends StatelessWidget {
  const PartnerListTile({
    super.key,
    required this.partner,
    required this.onTap,
    this.distanceLabel,
  });

  final CoursePartner partner;
  final VoidCallback onTap;

  /// '1.2km' 같은 현위치 거리. 위치를 모르면 null이라 숨긴다.
  final String? distanceLabel;

  @override
  Widget build(BuildContext context) {
    final address = partner.address;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            PartnerCategoryTile(category: partner.category),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: Text(
                          partner.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        partner.category.label,
                        style: const TextStyle(fontSize: 11, color: AppColors.muted),
                      ),
                    ],
                  ),
                  if (partner.benefit != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      partner.benefit!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                  if (address != null || distanceLabel != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      [?distanceLabel, ?address].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: AppColors.textSubtle),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}
