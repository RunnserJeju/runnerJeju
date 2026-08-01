import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../services/service_locator.dart';
import 'course_detail_screen.dart';

/// GPX 파일을 골라 코스로 등록한다 (관리자용 수동 업로드).
///
/// [CourseUploadScreen]과 다른 화면이다 — 그쪽은 방금 달린 경로(좌표 목록)를
/// 코스로 등록하고, 여기는 미리 갖고 있는 GPX 파일을 올린다.
class GpxUploadScreen extends StatefulWidget {
  const GpxUploadScreen({super.key});

  @override
  State<GpxUploadScreen> createState() => _GpxUploadScreenState();
}

class _GpxUploadScreenState extends State<GpxUploadScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  PlatformFile? _pickedFile;
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
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
                hintText: '예) 사계해안도로',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.done,
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? '코스 이름을 입력해 주세요' : null,
            ),
            const SizedBox(height: 20),
            const Text(
              'GPX 파일',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: Icon(
                  file == null ? Icons.upload_file_rounded : Icons.route_rounded,
                ),
                title: Text(file?.name ?? '선택된 파일 없음'),
                subtitle: file == null
                    ? null
                    : Text('${(file.size / 1024).toStringAsFixed(0)} KB'),
                trailing: OutlinedButton(
                  onPressed: _submitting ? null : _pickFile,
                  child: Text(file == null ? '파일 선택' : '변경'),
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
