import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 화면 안 섹션 제목. 화면마다 제각각이던 크기를 두 단계로 맞춘다.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.small = false});

  final String text;

  /// 시트·카드 안처럼 좁은 자리에 쓰는 작은 제목.
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: small ? 14 : 18,
        fontWeight: small ? FontWeight.w700 : FontWeight.w800,
        letterSpacing: small ? 0 : -0.4,
        color: AppColors.ink,
        height: small ? 1.5 : null,
      ),
    );
  }
}
