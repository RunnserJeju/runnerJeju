import 'package:flutter/material.dart';

import '../../models/geo_point.dart';
import '../../models/running_course.dart';
import '../../services/service_locator.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin_only.dart';
import '../../widgets/course_map_view.dart';
import '../../widgets/sheet_handle.dart';
import '../course/gpx_upload_screen.dart';
import '../run/run_screen.dart';
import 'course_preview_sheet.dart';

/// '러닝' 탭: 지도에서 코스를 고르거나, 고르지 않고 바로 자유 러닝을 시작한다.
///
/// 코스를 고르는 일과 달리는 일이 원래 화면 두 개(코스 목록 → 코스 상세 →
/// 러닝)로 나뉘어 있었다. 지도 하나에 모으면 "어디를 달릴까"와 "지금 달리자"가
/// 같은 화면에서 끝난다. 러닝 화면([RunScreen])과 기록 로직은 그대로 두고,
/// 거기까지 가는 길만 이 화면이 대신한다.
class RunningScreen extends StatefulWidget {
  const RunningScreen({super.key});

  @override
  State<RunningScreen> createState() => _RunningScreenState();
}

class _RunningScreenState extends State<RunningScreen> {
  final CourseMapController _mapController = CourseMapController();
  final TextEditingController _searchController = TextEditingController();

  List<RunningCourse> _courses = const [];
  bool _isLoadingCourses = true;
  Object? _coursesError;

  String _query = '';

  /// 지도에서 고른 코스. 목록에서 온 값이라 경로([RunningCourse.path])가 없다.
  RunningCourse? _selected;

  /// [_selected]의 상세. 경로가 들어 있어야 지도에 선을 그리고 러닝을 시작할 수 있다.
  RunningCourse? _selectedDetail;
  Object? _detailError;

  /// 상세 요청의 순번. 코스를 빠르게 옮겨 누르면 먼저 보낸 요청이 나중에 도착할
  /// 수 있어서, 마지막으로 보낸 것 말고는 버린다.
  int _detailRequestId = 0;

  GeoPoint? _myPosition;

  @override
  void initState() {
    super.initState();
    _loadCourses();
    _locateQuietly();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 데이터
  // ---------------------------------------------------------------------------

  Future<void> _loadCourses() async {
    setState(() {
      _isLoadingCourses = true;
      _coursesError = null;
    });

    try {
      final courses = await Services.instance.course.loadCourses();
      if (!mounted) return;
      setState(() {
        _courses = courses;
        _isLoadingCourses = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _coursesError = error;
        _isLoadingCourses = false;
      });
    }
  }

  /// 검색어로 거른 코스. 서버를 다시 부르지 않는다 — 코스는 전부 받아 두었고,
  /// 지도에서는 글자를 지울 때마다 라벨이 사라졌다 나타나면 눈에 거슬린다.
  List<RunningCourse> get _visibleCourses {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _courses;

    return _courses.where((course) {
      final haystack = [
        course.name,
        course.address,
        course.tags ?? '',
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  Future<void> _selectCourse(RunningCourse course) async {
    setState(() {
      _selected = course;
      _selectedDetail = null;
      _detailError = null;
    });

    final start = course.startPoint;
    if (start != null) _mapController.moveTo(start);

    final requestId = ++_detailRequestId;
    try {
      final detail = await Services.instance.course.loadCourse(course.id);
      if (!mounted || requestId != _detailRequestId) return;
      setState(() => _selectedDetail = detail);
    } catch (error) {
      if (!mounted || requestId != _detailRequestId) return;
      setState(() => _detailError = error);
    }
  }

  void _clearSelection() {
    if (_selected == null) return;

    // 순번을 올려 두면 아직 오는 중인 상세 응답이 도착해도 무시된다.
    _detailRequestId++;
    setState(() {
      _selected = null;
      _selectedDetail = null;
      _detailError = null;
    });
  }

  /// 화면을 열자마자 내 위치를 한 번 찍어 둔다. 권한이 없으면 그냥 넘어간다 —
  /// 지도를 보기만 하는 데는 위치가 필요 없고, 권한 안내는 러닝을 시작할 때 나온다.
  Future<void> _locateQuietly() async {
    final availability = await Services.instance.location.ensurePermission();
    if (!availability.isReady || !mounted) return;

    try {
      final position = await Services.instance.location.currentPosition();
      if (!mounted) return;
      setState(() => _myPosition = position);
    } catch (_) {
      // 위치를 못 잡아도 지도는 제주 전체를 보여주면 된다.
    }
  }

  // ---------------------------------------------------------------------------
  // 동작
  // ---------------------------------------------------------------------------

  Future<void> _moveToMyLocation() async {
    final availability = await Services.instance.location.ensurePermission();
    if (!mounted) return;

    if (!availability.isReady) {
      _showMessage(availability.message);
      return;
    }

    try {
      final position = await Services.instance.location.currentPosition();
      if (!mounted) return;
      setState(() => _myPosition = position);
      _mapController.moveTo(position, zoomLevel: 15);
    } catch (_) {
      if (mounted) _showMessage('현재 위치를 확인하지 못했어요.');
    }
  }

  Future<void> _startRun({RunningCourse? course}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RunScreen(course: course)),
    );
    if (!mounted) return;

    // 완주 스탬프를 받았으면 목록의 완주자 수와 완주 여부가 달라진다.
    await _loadCourses();
  }

  /// 코스 등록(관리자 전용)으로 가는 길. 예전에는 '코스' 탭 상단에 있었는데,
  /// 그 탭을 이 지도가 대신하면서 여기 말고는 들어갈 곳이 없어졌다.
  Future<void> _openGpxUpload() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const GpxUploadScreen()),
    );
    if (!mounted) return;

    await _loadCourses();
  }

  void _showComingSoon(String label) => _showMessage('$label 기능은 준비 중이에요.');

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------------------------------------------------------------------------
  // 화면
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final selected = _selected;

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: Stack(
        children: [
          Positioned.fill(
            child: CourseMapView(
              controller: _mapController,
              courses: _visibleCourses,
              selectedCourseId: selected?.id,
              selectedPath: _selectedDetail?.path ?? const [],
              myPosition: _myPosition,
              onCourseTap: _selectCourse,
              onMapTap: _clearSelection,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SearchField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _statusPill()),
                      _SideActions(
                        onTapFavorite: () => _showComingSoon('찜'),
                        onTapExplore: () => _showComingSoon('경로 탐색'),
                        onTapPartner: () => _showComingSoon('협력업체'),
                        onTapMyLocation: _moveToMyLocation,
                        onTapUploadGpx: _openGpxUpload,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (selected == null)
            Align(
              alignment: Alignment.bottomCenter,
              child: _FreeRunPanel(onStart: () => _startRun()),
            )
          else
            CoursePreviewSheet(
              // 코스를 바꾸면 시트를 접힌 상태에서 다시 시작한다.
              key: ValueKey(selected.id),
              course: selected,
              detail: _selectedDetail,
              detailError: _detailError,
              onClose: _clearSelection,
              onRetryDetail: () => _selectCourse(selected),
              onStart: () => _startRun(course: _selectedDetail),
            ),
        ],
      ),
    );
  }

  /// 검색 결과나 로딩 상태를 지도 위에 얹어 알린다. 지도를 가리지 않으려고
  /// 화면 전체를 덮는 [AsyncView] 대신 작은 알약 하나만 띄운다.
  Widget _statusPill() {
    if (_coursesError != null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: _StatusPill(
          label: '코스를 불러오지 못했어요',
          icon: Icons.refresh_rounded,
          onTap: _loadCourses,
        ),
      );
    }

    if (_isLoadingCourses) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: _StatusPill(label: '코스를 불러오는 중', busy: true),
      );
    }

    if (_query.trim().isNotEmpty && _visibleCourses.isEmpty) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: _StatusPill(label: '검색 결과가 없어요', icon: Icons.search_off_rounded),
      );
    }

    return const SizedBox.shrink();
  }
}

/// 지역·코스 이름·태그를 한 칸에서 찾는 검색바.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 3,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(999),
      child: TextField(
        controller: controller,
        textInputAction: TextInputAction.search,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: '지역, 코스 이름으로 검색',
          prefixIcon: const Icon(Icons.search_rounded, size: 22),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                  ),
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}

/// 지도 오른쪽에 세로로 붙는 버튼들.
class _SideActions extends StatelessWidget {
  const _SideActions({
    required this.onTapFavorite,
    required this.onTapExplore,
    required this.onTapPartner,
    required this.onTapMyLocation,
    required this.onTapUploadGpx,
  });

  final VoidCallback onTapFavorite;
  final VoidCallback onTapExplore;
  final VoidCallback onTapPartner;
  final VoidCallback onTapMyLocation;
  final VoidCallback onTapUploadGpx;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        _SideButton(
          icon: Icons.favorite_border_rounded,
          label: '찜',
          onTap: onTapFavorite,
        ),
        const SizedBox(height: 8),
        _SideButton(
          icon: Icons.route_rounded,
          label: '경로 탐색',
          onTap: onTapExplore,
        ),
        const SizedBox(height: 8),
        _SideButton(
          icon: Icons.storefront_rounded,
          label: '협력업체',
          onTap: onTapPartner,
        ),
        const SizedBox(height: 14),
        _RoundIconButton(
          icon: Icons.my_location_rounded,
          tooltip: '내 위치',
          onTap: onTapMyLocation,
        ),
        AdminOnly(
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _RoundIconButton(
              icon: Icons.upload_file_rounded,
              tooltip: 'GPX로 코스 등록',
              onTap: onTapUploadGpx,
            ),
          ),
        ),
      ],
    );
  }
}

class _SideButton extends StatelessWidget {
  const _SideButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 2,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: AppColors.ink),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 2,
      shadowColor: Colors.black26,
      shape: const CircleBorder(),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, size: 21, color: AppColors.accent),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    this.icon,
    this.busy = false,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 2,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (icon != null)
                Icon(icon, size: 15, color: AppColors.ink),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 코스를 고르지 않았을 때 화면 아래에 붙는 기본 패널.
class _FreeRunPanel extends StatelessWidget {
  const _FreeRunPanel({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 16, offset: Offset(0, -2)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetHandle(),
              const SizedBox(height: 14),
              const Text(
                '코스를 선택하거나 자유 러닝을 시작하세요',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF5B6472),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.directions_run_rounded),
                label: const Text('자유 러닝 시작'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
