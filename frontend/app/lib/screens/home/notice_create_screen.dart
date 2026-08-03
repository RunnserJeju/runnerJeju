import 'package:flutter/material.dart';

import '../../services/service_locator.dart';

/// 공지사항 작성 화면.
///
/// 진입 버튼은 [AdminOnly]로 admin에게만 보이고, 제출은 서버가 `require_admin`으로
/// 막는다. 화면 자체에는 권한 검사를 두지 않는다 — 최종 판정은 서버 몫이다.
class NoticeCreateScreen extends StatefulWidget {
  const NoticeCreateScreen({super.key});

  @override
  State<NoticeCreateScreen> createState() => _NoticeCreateScreenState();
}

class _NoticeCreateScreenState extends State<NoticeCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _submitting = true);
    try {
      await Services.instance.notice.createNotice(
        title: _titleController.text.trim(),
        body: _bodyController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('공지사항 작성')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            TextFormField(
              controller: _titleController,
              autofocus: true,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: '제목',
                hintText: '예) 8월 정기 러닝 모임 안내',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? '제목을 입력해 주세요' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _bodyController,
              minLines: 6,
              maxLines: 12,
              decoration: const InputDecoration(
                labelText: '내용',
                hintText: '공지 내용을 입력하세요',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? '내용을 입력해 주세요' : null,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                child: Text(_submitting ? '등록 중...' : '등록하기'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
