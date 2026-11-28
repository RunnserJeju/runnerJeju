import 'package:flutter/material.dart';

import 'confirm_popup.dart';

/// 결과 화면에서 완주하지 못한 코스를 이어 달릴지 묻는 팝업. "이어 달리기"면 true.
/// 바깥을 눌러 닫으면 "다음에"와 같다.
Future<bool> showContinueRunPrompt(BuildContext context) async {
  final result = await showConfirmPopup(
    context,
    title: '이어서 달릴까요?',
    message: '검증 결과 코스를 완주하지 못했어요.',
    cancelLabel: '다음에',
    confirmLabel: '이어 달리기',
  );
  return result ?? false;
}
