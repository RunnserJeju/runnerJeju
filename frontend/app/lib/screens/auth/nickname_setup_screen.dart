import 'package:flutter/material.dart';

import '../../services/service_locator.dart';
import '../app_shell.dart';

/// 최초 로그인 직후, 아직 닉네임이 없는 유저에게 딱 한 번 보여주는 화면.
///
/// 카카오/애플 등 provider가 주는 이름을 그대로 쓰지 않고 여기서 직접 받는다 —
/// provider마다 이름 제공 방식이 달라(auth_service.dart 참고) 앱 안에서 값을
/// 하나로 통일해두는 편이 낫다.
class NicknameSetupScreen extends StatefulWidget {
  const NicknameSetupScreen({super.key});

  @override
  State<NicknameSetupScreen> createState() => _NicknameSetupScreenState();
}

class _NicknameSetupScreenState extends State<NicknameSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nicknameController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _submitting = true);
    try {
      await Services.instance.auth.setNickname(_nicknameController.text.trim());
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AppShell()),
      );
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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '닉네임을 정해주세요',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  '러너스제주에서 사용할 이름이에요. 나중에 바꿀 수 있어요.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 28),
                TextFormField(
                  controller: _nicknameController,
                  autofocus: true,
                  maxLength: 20,
                  decoration: const InputDecoration(
                    labelText: '닉네임',
                    hintText: '예) 제주러너',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? '닉네임을 입력해 주세요' : null,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: Text(_submitting ? '저장 중...' : '시작하기'),
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
