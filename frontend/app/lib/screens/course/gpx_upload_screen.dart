import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../models/running_course.dart';
import '../../services/service_locator.dart';
import 'course_detail_screen.dart';

/// GPX 파일을 골라 코스로 등록한다 (관리자용 수동 업로드).
///
/// GPX는 경로 좌표와 이름만 갖고 있다. 거리·난이도·주소는 코스 명단
/// (server/courses/courses.yaml)에 적는 값과 같은 것이라 여기서 직접 입력받는다.
class GpxUploadScreen extends StatefulWidget {
  const GpxUploadScreen({super.key});

  @override
  State<GpxUploadScreen> createState() => _GpxUploadScreenState();
}

class _GpxUploadScreenState extends State<GpxUploadScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _distanceController = TextEditingController();
  final _addressController = TextEditingController();
  final _tagsController = TextEditingController();
  final _parkingController = TextEditingController();
  final _restroomController = TextEditingController();
  final _descriptionController = TextEditingController();

  CourseDifficulty _difficulty = CourseDifficulty.normal;
  PlatformFile? _pickedFile;
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _distanceController.dispose();
    _addressController.dispose();
    _tagsController.dispose();
    _parkingController.dispose();
    _restroomController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gpx'],
    );
    if (result == null) return;

    setState(() => _pickedFile = result.files.single);
  }

  /// 비어 있으면 null. 선택 입력 필드를 서버에 보낼 값으로 바꾼다.
  String? _optional(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : text;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final file = _pickedFile;
    if (file == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('GPX 파일을 선택해 주세요.')));
      return;
    }

    setState(() => _submitting = true);

    try {
      final bytes = await file.readAsBytes();
      final course = await Services.instance.course.uploadGpxFile(
        bytes: bytes,
        filename: file.name,
        name: _nameController.text.trim(),
        distanceKm: int.parse(_distanceController.text.trim()),
        difficulty: _difficulty,
        address: _addressController.text.trim(),
        tags: _optional(_tagsController),
        parkingAddress: _optional(_parkingController),
        restroomAddress: _optional(_restroomController),
        description: _optional(_descriptionController),
      );

      if (!mounted) return;

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
    final file = _pickedFile;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: const Text('GPX로 코스 등록')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '코스 이름',
                hintText: '예) No10. 사계 해안도로',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? '코스 이름을 입력해 주세요' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _distanceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '거리 (왕복 기준)',
                hintText: '예) 6',
                suffixText: 'km',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
              validator: (value) {
                final parsed = int.tryParse(value?.trim() ?? '');
                if (parsed == null) return '거리를 km 단위 정수로 입력해 주세요';
                if (parsed < 1) return '거리는 1km 이상이어야 해요';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _addressController,
              decoration: const InputDecoration(
                labelText: '주소',
                hintText: '예) 송악산 주차장 서귀포시 대정읍 상모리 4165-123',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? '주소를 입력해 주세요' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _tagsController,
              decoration: const InputDecoration(
                labelText: '태그 (선택)',
                hintText: '쉼표로 구분 — 예) 해안도로,서쪽,서귀포',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _parkingController,
              decoration: const InputDecoration(
                labelText: '근처 주차장 주소 (선택)',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _restroomController,
              decoration: const InputDecoration(
                labelText: '근처 화장실 주소 (선택)',
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
            const SizedBox(height: 20),
            const Text(
              'GPX 파일',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(
                      file == null
                          ? Icons.upload_file_rounded
                          : Icons.route_rounded,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            file?.name ?? '선택된 파일 없음',
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (file != null)
                            Text(
                              '${(file.size / 1024).toStringAsFixed(0)} KB',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: _submitting ? null : _pickFile,
                      // 전역 OutlinedButton 테마의 minimumSize는 화면 폭 전체를
                      // 채우는 버튼(Size.fromHeight)을 기준으로 잡혀 있다. 이 버튼은
                      // Row 안에 Expanded 없이 놓이므로 그 값을 그대로 물려받으면
                      // 무한 너비를 요구해 레이아웃이 깨진다. 여기서만 좁게 되돌린다.
                      style: OutlinedButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      child: Text(file == null ? '파일 선택' : '변경'),
                    ),
                  ],
                ),
              ),
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
