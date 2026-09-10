import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/geo_point.dart';
import '../../models/running_course.dart';
import '../../services/current_location.dart';
import '../../services/service_locator.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../utils/geo_utils.dart';
import '../../utils/transient_messenger.dart';
import '../../widgets/course_map_view.dart';
import '../run/run_screen.dart';
import 'course_list_sheet.dart';
import 'course_preview_sheet.dart';
import 'course_search_results.dart';

/// '러닝' 탭: 지도에서 코스를 골라 러닝을 시작한다.
///
/// 코스를 고르는 일과 달리는 일이 원래 화면 두 개(코스 목록 → 코스 상세 →
/// 러닝)로 나뉘어 있었다. 지도 하나에 모으면 "어디를 달릴까"와 "지금 달리자"가
/// 같은 화면에서 끝난다. 기본 상태에서는 지도 아래에 코스 탐색 시트가 살짝만
/// 올라와 있다 — 끌어올리거나 '코스 탐색'을 누르면 현위치에서 가까운 순으로
/// 코스 목록이 펼쳐지고, 지도에서 코스를 고르면 그 자리에 상세 시트가 온다.
/// 코스 없이 달리는 자유 러닝은 진입점을 뺐다([_startRun]은 아직 코스 없이도
/// 돌아간다). 러닝 화면([RunScreen])과 기록 로직은 그대로 두고,
/// 거기까지 가는 길만 이 화면이 대신한다.
class RunningScreen extends StatefulWidget {
  const RunningScreen({super.key});

  @override
  State<RunningScreen> createState() => _RunningScreenState();
}

class _RunningScreenState extends State<RunningScreen> {
  final CourseMapController _mapController = CourseMapController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  /// 짧은 안내는 겹쳐 쌓이지 않게 이쪽을 거친다. '준비 중' 버튼들은 연달아
  /// 눌리기 쉬워서, 그냥 띄우면 같은 문장이 누른 횟수만큼 줄을 선다.
  final TransientMessenger _messenger = TransientMessenger();

  List<RunningCourse> _courses = const [];
  bool _isLoadingCourses = true;
  Object? _coursesError;

  /// 코스 이름 검색. 결과 목록만 서버(ILIKE)를 따르고 지도 마커는 전부 남긴다 —
  /// 글자를 지울 때마다 라벨이 사라졌다 나타나면 눈에 거슬린다.
  String _query = '';
  List<RunningCourse> _searchResults = const [];
  bool _isSearching = false;
  Object? _searchError;
  bool _isSearchOpen = false;
  Timer? _searchDebounce;
  int _searchRequestId = 0;

  static const Duration _searchDelay = Duration(milliseconds: 300);
  static const int _searchLimit = 20;

  /// 지도에서 고른 코스. 목록에서 온 값이라 경로([RunningCourse.path])가 없다.
  RunningCourse? _selected;

  /// [_selected]의 상세. 경로가 들어 있어야 지도에 선을 그리고 러닝을 시작할 수 있다.
  RunningCourse? _selectedDetail;
  Object? _detailError;

  /// 고른 코스의 찜 여부. 프리뷰 시트의 하트가 이 값을 따른다.
  bool _selectedIsFavorite = false;

  /// 상세 요청의 순번. 코스를 빠르게 옮겨 누르면 먼저 보낸 요청이 나중에 도착할
  /// 수 있어서, 마지막으로 보낸 것 말고는 버린다.
  int _detailRequestId = 0;

  /// 코스 탐색 시트의 높이를 바깥에서 움직일 때 쓴다. 코스를 고르면 시트가
  /// 트리에서 빠져 컨트롤러가 떨어지므로, 움직이기 전에 [isAttached]를 본다.
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  /// 앱 전역의 최신 현위치. 이 화면은 조회하지 않고 읽기만 한다 — 내 위치
  /// 점, 내 위치 버튼, 시작점까지의 거리 판정이 전부 이 값을 쓴다.
  CurrentLocation get _currentLocation => Services.instance.currentLocation;

  /// 러닝 화면이 위에 떠 있는 동안인지.
  ///
  /// 그동안에는 이 화면의 지도를 트리에서 뺀다. 라우트를 밀어 올려도 아래 화면은
  /// 살아 있어서, 가만히 두면 카카오맵 네이티브 뷰가 둘이 된다 — 하나는 달리는
  /// 사람이 보고 있고, 하나는 아무도 못 보는 채로 메모리만 쓴다. 위젯을 떼면
  /// 네이티브 쪽이 mapView.finish()까지 확실히 정리한다.
  bool _isRunningScreenOpen = false;

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(_onSearchFocusChanged);
    _loadCourses();
    _currentLocation.addListener(_onLocationChanged);
    // 권한을 아직 안 물어봤으면 여기서 묻는다 — 지도가 떠 있는 맥락이라
    // 왜 필요한지 자명하다. 거부해도 지도는 제주 전체를 보여주면 된다.
    unawaited(_currentLocation.ensureStarted());
  }

  @override
  void dispose() {
    _currentLocation.removeListener(_onLocationChanged);
    _searchDebounce?.cancel();
    _searchFocus.dispose();
    _searchController.dispose();
    _sheetController.dispose();
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

  // ---------------------------------------------------------------------------
  // 검색
  // ---------------------------------------------------------------------------

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final keyword = value.trim();

    if (keyword.isEmpty) {
      _searchRequestId++;
      setState(() {
        _query = value;
        _searchResults = const [];
        _isSearching = false;
        _searchError = null;
        _isSearchOpen = false;
      });
      return;
    }

    setState(() {
      _query = value;
      _isSearchOpen = true;
      _isSearching = true;
      _searchError = null;
    });
    _searchDebounce = Timer(_searchDelay, () => _runSearch(keyword));
  }

  Future<void> _runSearch(String keyword) async {
    final requestId = ++_searchRequestId;
    setState(() {
      _isSearching = true;
      _searchError = null;
    });

    try {
      final results = await Services.instance.course.loadCourses(
        keyword: keyword,
        limit: _searchLimit,
      );
      if (!mounted || requestId != _searchRequestId) return;
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (error) {
      if (!mounted || requestId != _searchRequestId) return;
      setState(() {
        _searchError = error;
        _isSearching = false;
      });
    }
  }

  /// 키보드의 검색 버튼. 디바운스를 기다리지 않고 바로 찾아 첫 결과로 간다.
  Future<void> _onSearchSubmitted(String value) async {
    final keyword = value.trim();
    if (keyword.isEmpty) return;

    if (_searchDebounce?.isActive ?? false) {
      _searchDebounce!.cancel();
      await _runSearch(keyword);
      if (!mounted) return;
    }

    if (_searchResults.isNotEmpty) _selectSearchResult(_searchResults.first);
  }

  void _selectSearchResult(RunningCourse course) {
    _searchFocus.unfocus();
    setState(() => _isSearchOpen = false);
    _selectCourse(course);
  }

  /// 검색창을 다시 누르면 남아 있던 결과를 다시 펼친다.
  void _onSearchFocusChanged() {
    if (_searchFocus.hasFocus && _query.trim().isNotEmpty && !_isSearchOpen) {
      setState(() => _isSearchOpen = true);
    }
  }

  void _closeSearch() {
    _searchFocus.unfocus();
    if (_isSearchOpen) setState(() => _isSearchOpen = false);
  }

  Future<void> _selectCourse(RunningCourse course) async {
    setState(() {
      _selected = course;
      _selectedDetail = null;
      _detailError = null;
      _selectedIsFavorite = false;
    });

    final start = course.startPoint;
    if (start != null) _mapController.moveTo(start);

    // 찜 여부는 로컬 저장이라 금방 온다. 다른 코스로 옮겨 눌렀으면 버린다.
    final requestId = ++_detailRequestId;
    Services.instance.favorite.isFavorite(course.id).then((isFavorite) {
      if (!mounted || requestId != _detailRequestId) return;
      setState(() => _selectedIsFavorite = isFavorite);
    });

    try {
      final detail = await Services.instance.course.loadCourse(course.id);
      if (!mounted || requestId != _detailRequestId) return;
      setState(() => _selectedDetail = detail);
    } catch (error) {
      if (!mounted || requestId != _detailRequestId) return;
      setState(() => _detailError = error);
    }
  }

  /// 고른 코스의 찜을 토글하고 상태를 갱신한다.
  Future<void> _toggleSelectedFavorite() async {
    final course = _selected;
    if (course == null) return;

    final nowFavorite = await Services.instance.favorite.toggle(course.id);
    if (!mounted || _selected?.id != course.id) return;
    setState(() => _selectedIsFavorite = nowFavorite);
    _showMessage(nowFavorite ? '찜한 코스에 담았어요.' : '찜을 해제했어요.');
  }

  /// 지도 바닥을 눌렀을 때. 코스 상세는 걷고, 탐색 시트는 접는다.
  void _clearSelection() {
    _closeSearch();
    if (_selected == null) {
      _moveSheet(CourseListSheet.peekHeight, isPixels: true);
      return;
    }

    // 순번을 올려 두면 아직 오는 중인 상세 응답이 도착해도 무시된다.
    _detailRequestId++;
    setState(() {
      _selected = null;
      _selectedDetail = null;
      _detailError = null;
    });
  }

  /// '코스 탐색' 버튼. 코스 상세가 떠 있었다면 걷고 탐색 시트를 펼친다.
  void _openExplore() {
    _detailRequestId++;
    setState(() {
      _selected = null;
      _selectedDetail = null;
      _detailError = null;
    });
    // 상세를 걷은 프레임에서 시트가 다시 트리에 붙는다. 붙은 뒤에 움직인다.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _moveSheet(CourseListSheet.halfSize),
    );
  }

  /// 탐색 시트를 [size]로 움직인다. 비율(0~1) 또는 [isPixels]면 픽셀.
  void _moveSheet(double size, {bool isPixels = false}) {
    if (!mounted || !_sheetController.isAttached) return;
    final target = isPixels ? _sheetController.pixelsToSize(size) : size;
    _sheetController.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  /// 최신 현위치가 바뀌었다. 지도의 내 위치 점만 다시 그린다.
  void _onLocationChanged() {
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------------------
  // 동작
  // ---------------------------------------------------------------------------

  /// 내 위치 버튼. 위치를 조회하는 버튼이 아니라 **최신 위치로 카메라를 옮기는**
  /// 버튼이다. 위치는 [CurrentLocation]이 스트림으로 계속 받고 있어서 누르는
  /// 즉시 한 번 움직이고 끝난다.
  Future<void> _moveToMyLocation() async {
    final position = _currentLocation.latest;
    if (position != null) {
      _mapController.moveTo(position, zoomLevel: 15);
      return;
    }

    // 아직 한 점도 없다. 권한 문제면 그 안내를, 아니면 잡는 중이라고 알린다.
    final availability = await _currentLocation.ensureStarted();
    if (!mounted) return;
    _showMessage(availability.isReady ? '위치를 잡는 중이에요.' : availability.message);
  }

  /// 코스 시작점에서 이만큼 넘게 떨어져 있으면 길찾기를 권한다. 코스 초입에
  /// 서 있을 때의 GPS 오차(도심에서 수십 m)에는 걸리지 않을 만큼 넉넉하다.
  static const double _routeGuideThreshold = 100;

  Future<void> _startRun({RunningCourse? course}) async {
    // 스트림이 계속 갱신하는 값이라 다시 잡지 않는다. 코스를 둘러보다 시작점에
    // 걸어서 도착했으면 이미 그 자리가 들어와 있다.
    final origin = _currentLocation.latest;

    final start = course?.startPoint;
    if (start != null) {
      // 위치가 아직 없으면 거리를 알 수 없다. 묻지 않고 그냥 시작한다 —
      // 위치 권한 안내는 러닝 화면이 따로 띄운다.
      final distance = origin == null
          ? null
          : GeoUtils.distanceBetween(origin, start);

      if (origin != null &&
          distance != null &&
          distance > _routeGuideThreshold) {
        final wantsRoute = await _confirmRouteGuide(course!, distance);
        if (!mounted) return;

        // 길찾기를 골랐으면 러닝은 시작하지 않는다. 시작점까지 이동한 뒤
        // 돌아와 다시 누르는 흐름이다. 바깥을 눌러 닫았을 때(null)도 마찬가지 —
        // 아무것도 고르지 않은 것을 '여기서 시작'으로 읽지 않는다.
        if (wantsRoute != false) {
          if (wantsRoute == true) {
            await _openRouteToStart(from: origin, to: start);
          }
          return;
        }
      }
    }

    setState(() => _isRunningScreenOpen = true);

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RunScreen(course: course, initialCenter: origin),
      ),
    );
    if (!mounted) return;

    // 지도는 여기서 새로 만들어진다. 고른 코스·검색어·내 위치는 이 State에
    // 있어서 그대로 살아 있고, 지도가 다시 잡아야 하는 건 카메라뿐이다.
    setState(() => _isRunningScreenOpen = false);

    // 완주 스탬프를 받았으면 목록의 완주자 수와 완주 여부가 달라진다.
    await _loadCourses();
  }

  /// 시작점이 멀 때 길찾기를 띄울지 묻는다. 바깥을 눌러 닫으면 null —
  /// 러닝도 길찾기도 시작하지 않는다.
  Future<bool?> _confirmRouteGuide(RunningCourse course, double meters) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('시작점까지 길찾기'),
        content: Text(
          '${course.name} 시작점이 ${Formatters.awayDistance(meters)} 떨어져 있어요.\n'
          '카카오맵으로 길찾기를 시작할까요?',
        ),
        actions: [
          // 버튼 공통 스타일이 가로를 꽉 채우므로(app_theme.dart의 minimumSize)
          // 그대로 두면 상하로 쌓인다. Row+Expanded로 좌우 반반 배치.
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('여기서 시작'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('길찾기'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openRouteToStart({
    required GeoPoint from,
    required GeoPoint to,
  }) async {
    final opened = await Services.instance.kakaoMapLauncher.openWalkingRoute(
      from: from,
      to: to,
    );
    if (!mounted || opened) return;
    _showMessage('길찾기를 열지 못했어요.');
  }

  void _showComingSoon(String label) => _showMessage('$label 기능은 준비 중이에요.');

  void _showMessage(String message) => _messenger.show(context, message);

  // ---------------------------------------------------------------------------
  // 화면
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final selected = _selected;

    return Scaffold(
      backgroundColor: AppColors.paper,
      // 검색창은 화면 상단에 있어 키보드에 가려지지 않는다. body를 키보드
      // 높이만큼 리사이즈하게 두면 그 안의 카카오맵 네이티브 뷰(PlatformView)가
      // 함께 리사이즈되면서 렌더링이 깨진다(입력을 시작하자마자 지도가 깨지는
      // 증상). 지도가 리사이즈될 일이 없도록 막아 둔다.
      resizeToAvoidBottomInset: false,
      body: Stack(
        // 자식 크기에 맞춰 줄어들지 않게 한다. 기본 상태에서 자유 높이인 자식이
        // 상단 검색 UI뿐이면 Stack이 그 높이로 줄고, Positioned.fill인 지도도
        // 함께 잘린다.
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: _isRunningScreenOpen
                ? const ColoredBox(color: AppColors.paper)
                : CourseMapView(
                    controller: _mapController,
                    courses: _courses,
                    selectedCourseId: selected?.id,
                    selectedPath: _selectedDetail?.path ?? const [],
                    // 선택된 코스의 시설만 마커로. 상세가 오기 전엔 목록 값(이미
                    // 좌표 포함)을 쓰고, 오면 상세 값으로 바뀐다.
                    selectedParkings: selected == null
                        ? const []
                        : (_selectedDetail ?? selected).parkings,
                    selectedRestrooms: selected == null
                        ? const []
                        : (_selectedDetail ?? selected).restrooms,
                    myPosition: _currentLocation.latest,
                    onCourseTap: _selectCourse,
                    onMapTap: _clearSelection,
                    // 러닝을 마치고 돌아오면 지도가 새로 태어난다. 보고 있던
                    // 코스가 있으면 그 자리에서 다시 시작한다.
                    initialCenter: selected?.startPoint,
                  ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: _SearchField(
                      controller: _searchController,
                      focusNode: _searchFocus,
                      onChanged: _onSearchChanged,
                      onSubmitted: _onSearchSubmitted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // 결과 목록이 열려 있는 동안은 그 자리를 목록이 쓴다.
                  if (_isSearchOpen)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: CourseSearchResults(
                        results: _searchResults,
                        isLoading: _isSearching,
                        hasError: _searchError != null,
                        onSelect: _selectSearchResult,
                        onRetry: () => _runSearch(_query.trim()),
                      ),
                    )
                  else ...[
                    _ActionChips(
                      onTapFavorite: () => _showComingSoon('찜'),
                      onTapExplore: _openExplore,
                      onTapPartner: () => _showComingSoon('협력업체'),
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _statusPill(),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // 내 위치 버튼은 우하단, 접힌 탐색 시트 바로 위. 코스 상세 시트가 떠
          // 있을 때는 시트가 그 자리를 덮으므로 숨긴다.
          if (selected == null)
            Positioned(
              right: 16,
              bottom: CourseListSheet.peekHeight + 12,
              child: _RoundIconButton(
                icon: Icons.my_location_rounded,
                tooltip: '내 위치',
                onTap: _moveToMyLocation,
              ),
            ),
          if (selected == null)
            CourseListSheet(
              controller: _sheetController,
              courses: _courses,
              myPosition: _currentLocation.latest,
              isLoading: _isLoadingCourses,
              hasError: _coursesError != null,
              onSelect: _selectCourse,
              onRetry: _loadCourses,
            )
          else
            CoursePreviewSheet(
              // 코스를 바꾸면 시트를 접힌 상태에서 다시 시작한다.
              key: ValueKey(selected.id),
              course: selected,
              detail: _selectedDetail,
              detailError: _detailError,
              isFavorite: _selectedIsFavorite,
              onToggleFavorite: _toggleSelectedFavorite,
              onClose: _clearSelection,
              onRetryDetail: () => _selectCourse(selected),
              onStart: () => _startRun(course: _selectedDetail),
            ),
        ],
      ),
    );
  }

  /// 코스 로딩 상태를 지도 위에 얹어 알린다. 지도를 가리지 않으려고
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

    return const SizedBox.shrink();
  }
}

/// 코스 이름 검색바.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 3,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(999),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        textInputAction: TextInputAction.search,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          hintText: '코스 이름으로 검색',
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

/// 검색창 아래 가로로 늘어서는 기능 칩들. 화면보다 길어지면 좌우로 스크롤한다.
class _ActionChips extends StatelessWidget {
  const _ActionChips({
    required this.onTapFavorite,
    required this.onTapExplore,
    required this.onTapPartner,
  });

  final VoidCallback onTapFavorite;
  final VoidCallback onTapExplore;
  final VoidCallback onTapPartner;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      _ActionChip(
        icon: Icons.favorite_border_rounded,
        label: '찜',
        onTap: onTapFavorite,
      ),
      _ActionChip(
        icon: Icons.route_rounded,
        label: '코스 탐색',
        onTap: onTapExplore,
      ),
      _ActionChip(
        icon: Icons.storefront_rounded,
        label: '협력업체',
        onTap: onTapPartner,
      ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      // 칩 그림자가 스크롤 영역 가장자리에서 잘리지 않게 한다.
      clipBehavior: Clip.none,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (final (index, chip) in chips.indexed) ...[
            if (index > 0) const SizedBox(width: 8),
            chip,
          ],
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
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
