import 'package:flutter/material.dart';

import '../../models/running_course.dart';
import '../../services/service_locator.dart';
import '../../widgets/async_view.dart';
import '../../widgets/course_card.dart';
import 'course_detail_screen.dart';

/// 코스 탐색: 서버에서 코스 목록을 받아 보여준다.
class CourseListScreen extends StatefulWidget {
  const CourseListScreen({super.key});

  @override
  State<CourseListScreen> createState() => _CourseListScreenState();
}

class _CourseListScreenState extends State<CourseListScreen> {
  final _searchController = TextEditingController();

  late Future<List<RunningCourse>> _future;
  String? _region;

  /// 지역 필터 후보. 값 자체는 서버 쿼리 파라미터로 그대로 전달된다.
  static const _regions = ['제주시', '서귀포시', '애월', '성산', '한림'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _load() {
    _future = Services.instance.course.loadCourses(
      region: _region,
      keyword: _searchController.text.trim(),
    );
  }

  void _reload() => setState(_load);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('코스')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _reload(),
              decoration: InputDecoration(
                hintText: '코스 이름으로 검색',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: Colors.white,
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                _RegionChip(
                  label: '전체',
                  selected: _region == null,
                  onSelected: () {
                    _region = null;
                    _reload();
                  },
                ),
                for (final region in _regions)
                  _RegionChip(
                    label: region,
                    selected: _region == region,
                    onSelected: () {
                      _region = region;
                      _reload();
                    },
                  ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<RunningCourse>>(
              future: _future,
              builder: (context, snapshot) => AsyncView<List<RunningCourse>>(
                snapshot: snapshot,
                onRetry: _reload,
                isEmpty: (courses) => courses.isEmpty,
                emptyTitle: '조건에 맞는 코스가 없어요',
                emptyMessage: '검색어나 지역을 바꿔보세요',
                emptyIcon: Icons.route_rounded,
                builder: (context, courses) => ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                  itemCount: courses.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) => CourseCard(
                    course: courses[index],
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            CourseDetailScreen(courseId: courses[index].id),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RegionChip extends StatelessWidget {
  const _RegionChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
        showCheckmark: false,
      ),
    );
  }
}
