import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 결과 화면에서 완주하지 못한 코스를 이어 달릴지 묻는 팝업. "이어 달리기"면 true.
///
/// 제목·설명 가운데 정렬에 같은 너비 버튼 두 개(왼쪽 보조, 오른쪽 주 동작)로
/// 좌우가 대칭이 되게 둔다. 바깥을 눌러 닫으면 "다음에"와 같다.
Future<bool> showContinueRunPrompt(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => const _ContinueRunPrompt(),
  );
  return result ?? false;
}

class _ContinueRunPrompt extends StatelessWidget {
  const _ContinueRunPrompt();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '이어서 달릴까요?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '검증 결과 코스를 완주하지 못했어요.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.textSubtle),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _PromptButton(
                    label: '다음에',
                    background: AppColors.lineFaint,
                    foreground: AppColors.textSubtle,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PromptButton(
                    label: '이어 달리기',
                    background: AppColors.ink,
                    foreground: Colors.white,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 두 버튼이 색만 다르고 크기·모양이 같아야 대칭이 맞는다.
class _PromptButton extends StatelessWidget {
  const _PromptButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onPressed,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        minimumSize: const Size.fromHeight(48),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
      child: Text(label),
    );
  }
}
