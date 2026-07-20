import 'package:flutter/material.dart';

import '../../models/geo_point.dart';
import '../../models/running_course.dart';
import '../../services/service_locator.dart';
import '../../utils/formatters.dart';
import '../../utils/geo_utils.dart';
import '../../widgets/metric_tile.dart';
import '../../widgets/run_map_view.dart';
import 'course_detail_screen.dart';

/// 방금 달린 경로를 새 코스로 서버에 등록한다.
class CourseUploadScreen extends StatefulWidget {
  const CourseUploadScreen({super.key, required this.path});

  final List<GeoPoint> path;

  @override
  State<CourseUploadScreen> createState() => _CourseUploadScreenState();
}

class _CourseUploadScreenState extends State<CourseUploadScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _regionController = TextEditingController();

  CourseDifficulty _difficulty = CourseDifficulty.normal;
  bool _submitting = false;

  late final double _distanceMeters = GeoUtils.pathLength(widget.path);

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _regionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _submitting = true);

    try {
      final course = await Services.instance.course.uploadPath(
        path: widget.path,
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        region: _regionController.text.trim().isEmpty
            ? null
            : _regionController.text.trim(),
        difficulty: _difficulty,
      );

      if (!mounted) return;

      // 등록 화면은 히스토리에서 빼고 바로 등록된 코스 상세로 보낸다.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => CourseDetailScreen(courseId: course.id),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() => _submitting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('코스 등록')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Card(
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                height: 200,
                child: RunMapView(coursePath: widget.path),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: MetricTile(
                    label: '거리',
                    value: Formatters.distanceKm(_distanceMeters),
                    unit: 'km',
                  ),
                ),
                Expanded(
                  child: MetricTile(
                    label: '경로 지점',
                    value: '${widget.path.length}',
                    unit: '개',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '코스 이름',
                hintText: '예) 이호테우 해변 노을 코스',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? '코스 이름을 입력해 주세요' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _regionController,
              decoration: const InputDecoration(
                labelText: '지역 (선택)',
                hintText: '예) 애월',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: '코스 소개 (선택)',
                hintText: '어떤 점이 좋았는지 알려주세요',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '난이도',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 8),
            SegmentedButton<CourseDifficulty>(
              segments: [
                for (final difficulty in CourseDifficulty.values)
                  ButtonSegment(
                    value: difficulty,
                    label: Text(difficulty.label),
                  ),
              ],
              selected: {_difficulty},
              onSelectionChanged: (selection) =>
                  setState(() => _difficulty = selection.first),
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: Text(_submitting ? '등록 중...' : '코스 등록하기'),
            ),
          ],
        ),
      ),
    );
  }
}
