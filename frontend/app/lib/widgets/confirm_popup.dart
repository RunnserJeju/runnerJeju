import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'fit_label.dart';

/// 확인 팝업. 주 버튼이면 true, 보조 버튼이면 false, 바깥을 눌러 닫으면 null.
///
/// [cancelLabel]이 없으면 주 버튼 하나만 둔다(알림). [danger]면 주 버튼이 빨갛다.
/// 입력창처럼 내용이 다른 팝업은 [PopupFrame]을 직접 쓴다.
Future<bool?> showConfirmPopup(
  BuildContext context, {
  required String title,
  String? message,
  required String confirmLabel,
  String? cancelLabel,
  bool danger = false,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => PopupFrame(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      danger: danger,
      onCancel: () => Navigator.of(context).pop(false),
      onConfirm: () => Navigator.of(context).pop(true),
    ),
  );
}

/// 앱 팝업의 공통 틀. 제목·설명은 가운데 정렬, 버튼은 같은 너비로 왼쪽 보조·오른쪽
/// 주 동작이다. [child]는 설명과 버튼 사이에 들어간다(입력창, 선택지 등).
/// [confirmLabel]이 없으면 버튼 줄을 두지 않는다.
class PopupFrame extends StatelessWidget {
  const PopupFrame({
    super.key,
    required this.title,
    this.message,
    this.child,
    this.confirmLabel,
    this.cancelLabel,
    this.onConfirm,
    this.onCancel,
    this.danger = false,
  });

  final String title;
  final String? message;
  final Widget? child;
  final String? confirmLabel;
  final String? cancelLabel;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final message = this.message;
    final child = this.child;
    final confirmLabel = this.confirmLabel;
    final cancelLabel = this.cancelLabel;

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: AppColors.textSubtle,
                ),
              ),
            ],
            if (child != null) ...[const SizedBox(height: 16), child],
            if (confirmLabel != null) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  if (cancelLabel != null) ...[
                    Expanded(
                      child: PopupButton(
                        label: cancelLabel,
                        onPressed: onCancel,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: PopupButton(
                      label: confirmLabel,
                      primary: true,
                      danger: danger,
                      onPressed: onConfirm,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 팝업 버튼. 주 동작([primary])은 검정(또는 [danger] 빨강) 바탕, 보조는 옅은 회색 바탕.
/// 색만 다르고 크기·모양이 같아야 나란히 놓았을 때 대칭이 맞는다.
class PopupButton extends StatelessWidget {
  const PopupButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final Color background;
    final Color foreground;
    if (primary) {
      background = danger ? AppColors.danger : AppColors.ink;
      foreground = Colors.white;
    } else {
      background = AppColors.lineFaint;
      foreground = danger ? AppColors.danger : AppColors.textSubtle;
    }

    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        minimumSize: const Size.fromHeight(48),
        // 기본 좌우 24는 반쪽 폭 버튼에서 긴 글자를 자른다.
        padding: const EdgeInsets.symmetric(horizontal: 8),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
      child: FitLabel(label),
    );
  }
}
