import 'package:flutter/material.dart';

import '../../models/elevation_profile.dart';
import '../../models/geo_point.dart';
import '../../models/running_course.dart';
import '../../theme/app_theme.dart';
import '../../widgets/course_thumbnail.dart';
import '../../widgets/elevation_chart.dart';
import '../../widgets/sheet_handle.dart';
import '../../widgets/section_title.dart';
import '../../widgets/tag_chip.dart';

/// 지도에서 코스 라벨을 눌렀을 때 아래에서 올라오는 시트.
///
/// 접힌 상태에서 이름·거리·난이도와 시작 버튼까지 보이고, 끌어올리면 설명과
/// 주차·화장실 안내가 이어진다. 상세를 별도 화면으로 띄우지 않는 이유는 지도가
/// 계속 보여야 하기 때문이다 — 코스를 몇 개 눌러 보며 고르는 화면이라,
/// 화면을 갈아 끼우면 매번 지도로 돌아오는 왕복이 생긴다.
///
/// 시트가 모달이 아니라 [Stack]에 얹히는 위젯인 것도 같은 이유다. 모달이면
/// 뒤에 장막이 깔려 지도를 만질 수 없다.
class CoursePreviewSheet extends StatelessWidget {
  const CoursePreviewSheet({
    super.key,
    required this.course,
    required this.detail,
    required this.detailError,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onClose,
    required this.onRetryDetail,
    required this.onStart,
    required this.isDownloadingGpx,
    required this.onDownloadGpx,
    required this.isReversed,
    required this.onReverse,
  });

  /// 목록에서 온 코스. 이름·거리처럼 시트에 바로 보여줄 값은 여기 다 있다.
  final RunningCourse course;

  /// 경로까지 담긴 상세. 아직 받아오는 중이면 null이고, 그동안 시작 버튼이 잠긴다.
  final RunningCourse? detail;

  final Object? detailError;

  /// 찜 상태·토글은 부모(running_screen)가 들고 있다.
  final bool isFavorite;
  final VoidCallback onToggleFavorite;

  final VoidCallback onClose;
  final VoidCallback onRetryDetail;
  final VoidCallback onStart;

  /// GPX 받기도 부모가 한다 — 받은 파일을 공유 시트로 넘기는 일이 화면 몫이다.
  final bool isDownloadingGpx;
  final VoidCallback onDownloadGpx;

  /// 출발·도착을 바꿔 보고 있는지. [detail]은 이미 뒤집힌 사본으로 온다 — 시트는
  /// 문구만 바꾼다. 저장하지 않는 값이라 코스를 바꾸거나 시트를 닫으면 풀린다.
  final bool isReversed;
  final VoidCallback onReverse;

  /// 접힌 높이. 시작 버튼까지는 끌어올리지 않아도 보여야 한다.
  static const double _collapsedSize = 0.36;

  /// 펼친 높이. 검색바와 지도 일부는 남겨 둔다.
  static const double _expandedSize = 0.88;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: _collapsedSize,
      minChildSize: _collapsedSize,
      maxChildSize: _expandedSize,
      // 접힘/펼침 두 자리만 있다. 중간에서 손을 떼면 가까운 쪽으로 붙는다
      // (min·max는 스냅 지점에 저절로 포함되므로 snapSizes를 따로 주지 않는다).
      snap: true,
      builder: (context, scrollController) => DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 16,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            children: [
              const Center(child: SheetHandle()),
              const SizedBox(height: 14),
              _Header(course: course, onClose: onClose),
              const SizedBox(height: 12),
              _MetaChips(course: course),
              const SizedBox(height: 16),
              // 시작이 주 동작이라 남는 폭을 다 쓰고, 찜·GPX는 옆에 작은 칸으로 붙는다.
              Row(
                children: [
                  Expanded(
                    child: _StartButton(
                      isReady: detail != null,
                      hasError: detailError != null,
                      onStart: onStart,
                      onRetry: onRetryDetail,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _ActionTile(
                    icon: isFavorite
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    iconColor: isFavorite ? AppColors.accent : null,
                    label: '찜',
                    tooltip: isFavorite ? '찜 해제' : '찜하기',
                    onTap: onToggleFavorite,
                  ),
                  const SizedBox(width: 8),
                  _ActionTile(
                    icon: Icons.download_rounded,
                    label: 'GPX다운',
                    tooltip: 'GPX 파일 받기',
                    isBusy: isDownloadingGpx,
                    onTap: onDownloadGpx,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(height: 1, color: AppColors.lineFaint),
              const SizedBox(height: 20),
              ..._details(context),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _details(BuildContext context) {
    final description = course.description;

    return [
      if (description != null && description.isNotEmpty) ...[
        const SectionTitle('코스 소개', small: true),
        const SizedBox(height: 8),
        Text(
          description,
          style: const TextStyle(
            fontSize: 14,
            height: 1.6,
            color: AppColors.textBody,
          ),
        ),
        const SizedBox(height: 20),
      ],
      const SectionTitle('위치', small: true),
      const SizedBox(height: 8),
      // 코스 주소는 원래 출발점 기준이라, 방향을 바꾸면 도착지 주소가 된다.
      _InfoRow(
        icon: Icons.place_outlined,
        label: isReversed ? '도착지' : '출발지',
        value: course.address,
      ),
      _InfoRow(
        icon: Icons.local_parking_rounded,
        label: '주차',
        value: course.parkings.map((f) => f.label).join('\n'),
      ),
      _InfoRow(
        icon: Icons.wc_rounded,
        label: '화장실',
        value: course.restrooms.map((f) => f.label).join('\n'),
      ),
      // 협력업체는 없는 코스가 대부분이라 '정보 없음' 줄을 두지 않고 있을 때만 보인다.
      if (course.partners.isNotEmpty)
        _InfoRow(
          icon: Icons.storefront_rounded,
          label: '제휴',
          value: course.partners.map((p) => p.label).join('\n'),
        ),
      if (course.tagList.isNotEmpty) ...[
        const SizedBox(height: 20),
        const SectionTitle('태그', small: true),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [for (final tag in course.tagList) TagChip(label: tag)],
        ),
      ],
      // 고도는 경로에 딸려 오므로 목록의 course가 아니라 상세(detail)를 본다.
      // 상세가 오기 전에는 "없음"인지 아직 모르는 것이라 섹션을 그리지 않는다.
      if (detail != null) _ElevationSection(path: detail!.path),
      const SizedBox(height: 24),
      // 방향을 바꾸려면 뒤집을 경로가 있어야 해서 상세가 오기 전엔 잠근다.
      OutlinedButton.icon(
        onPressed: (detail?.path.length ?? 0) >= 2 ? onReverse : null,
        icon: const Icon(Icons.swap_vert_rounded),
        label: Text(isReversed ? '원래 방향으로 되돌리기' : '코스 방향 바꾸기'),
      ),
    ];
  }
}

/// 코스 고도 섹션. 제목은 늘 그리고, 고도가 없는 코스는 그래프 자리에 그렇다고
/// 적는다(원본 GPX의 고도가 온전하지 않아 서버가 버린 코스 — 우도런 3개가 그렇다).
/// 섹션째 빼면 "이 앱은 고도를 안 보여주나?"와 "이 코스만 없나?"가 구분되지 않는다.
///
/// StatefulWidget인 것은 프로파일을 캐시하기 위해서다. 시트를 끌어올리는 동안
/// DraggableScrollableSheet의 builder가 프레임마다 다시 불리는데, 그때마다 수백
/// 점의 거리를 다시 잴 이유가 없다.
class _ElevationSection extends StatefulWidget {
  const _ElevationSection({required this.path});

  final List<GeoPoint> path;

  @override
  State<_ElevationSection> createState() => _ElevationSectionState();
}

class _ElevationSectionState extends State<_ElevationSection> {
  ElevationProfile? _profile;

  @override
  void initState() {
    super.initState();
    _profile = ElevationProfile.of(widget.path);
  }

  @override
  void didUpdateWidget(_ElevationSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.path, widget.path)) {
      _profile = ElevationProfile.of(widget.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('고도', small: true),
          const SizedBox(height: 10),
          if (profile == null)
            const _ElevationUnavailable()
          else
            ElevationChart(profile: profile),
        ],
      ),
    );
  }
}

/// 고도 그래프가 들어갈 자리에 대신 놓는 안내. 그래프와 같은 높이라 코스를
/// 바꿔 가며 볼 때 아래 내용이 들썩이지 않는다.
class _ElevationUnavailable extends StatelessWidget {
  const _ElevationUnavailable();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 150,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Center(
        child: Text(
          '고도 데이터 없음',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textFaint,
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.course, required this.onClose});

  final RunningCourse course;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox.square(
            dimension: 72,
            child: CourseThumbnail(url: course.thumbnailUrl, iconSize: 26),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      course.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  if (course.isCompletedByMe) ...[
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.verified_rounded,
                      size: 20,
                      color: AppColors.success,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                course.address,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSubtle,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded),
          tooltip: '닫기',
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

class _MetaChips extends StatelessWidget {
  const _MetaChips({required this.course});

  final RunningCourse course;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        TagChip(
          icon: Icons.straighten_rounded,
          label: '왕복 ${course.distanceKmLabel}km',
        ),
        TagChip(
          icon: Icons.trending_up_rounded,
          label: course.difficulty.label,
        ),
        if (course.estimatedTimeLabel != null)
          TagChip(
            icon: Icons.schedule_rounded,
            label: course.estimatedTimeLabel!,
          ),
        TagChip(
          icon: Icons.emoji_events_outlined,
          label: '완주 ${course.completedCount}명',
        ),
      ],
    );
  }
}

/// 시작 버튼. 경로가 있어야 코스를 따라 달릴 수 있어서, 상세를 받아오는 동안은
/// 눌러도 아무 일이 없는 대신 기다리는 중임을 버튼 자체가 보여준다.
class _StartButton extends StatelessWidget {
  const _StartButton({
    required this.isReady,
    required this.hasError,
    required this.onStart,
    required this.onRetry,
  });

  final bool isReady;
  final bool hasError;
  final VoidCallback onStart;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (hasError) {
      // 옆에 찜·GPX 칸이 붙어 폭이 좁으므로 문구를 줄인다.
      return OutlinedButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('불러오기 실패 · 다시 시도', maxLines: 1),
      );
    }

    if (!isReady) {
      return FilledButton(
        onPressed: null,
        child: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }

    return FilledButton.icon(
      onPressed: onStart,
      icon: const Icon(Icons.directions_run_rounded),
      label: const Text('이 코스로 달리기'),
    );
  }
}

/// 시작 버튼 옆의 작은 칸(찜·GPX). 아이콘 아래 짧은 이름을 단다 — 아이콘만으로는
/// GPX 받기가 무엇인지 알기 어렵다. 높이는 시작 버튼(테마 최소 54)과 맞춘다.
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
    this.iconColor,
    this.isBusy = false,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onTap;
  final Color? iconColor;

  /// 처리 중이면 아이콘 자리에 진행 표시를 두고 다시 눌리지 않게 한다.
  final bool isBusy;

  static const double _width = 58;
  static const double _height = 54;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: isBusy ? null : onTap,
          child: SizedBox(
            width: _width,
            height: _height,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox.square(
                  dimension: 22,
                  child: isBusy
                      ? const Padding(
                          padding: EdgeInsets.all(3),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          icon,
                          size: 22,
                          color: iconColor ?? AppColors.iconSubtle,
                        ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSubtle,
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;

  /// 명단에 값이 없는 코스가 있어서 비어 있을 수 있다.
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: AppColors.textSubtle),
          const SizedBox(width: 10),
          SizedBox(
            width: 48,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textSubtle,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value?.isNotEmpty == true ? value! : '정보 없음',
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: value?.isNotEmpty == true
                    ? AppColors.textBody
                    : AppColors.textFaint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
