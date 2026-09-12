import 'package:flutter/material.dart';

/// 러닝 앱 전반의 색상/타이포 토큰. 값은 Figma 시안(러닝앱 UI 개선)과 맞춘다.
class AppColors {
  const AppColors._();

  /// 포인트 컬러(그린). 선택된 탭, 배너 아이라벨, 러닝 아이콘처럼 눈에 띄어야
  /// 하는 요소에만 쓴다.
  static const Color accent = Color(0xFFA0C974);
  static const Color ink = Color(0xFF0D0D0D);
  static const Color inkSoft = Color(0xFF1C1E23);

  /// 보조 텍스트·비선택 아이콘.
  static const Color muted = Color(0xFF9A9A9A);

  /// 본문 회색 단계. 진한 순.
  static const Color textBody = Color(0xFF3D4552);
  static const Color iconSubtle = Color(0xFF5B6472);
  static const Color textSubtle = Color(0xFF7A8593);
  static const Color textFaint = Color(0xFFA3ABB6);

  /// 옅은 구분선·비활성 면.
  static const Color lineFaint = Color(0xFFEDEFF2);
  static const Color surfaceMuted = Color(0xFFE8EBEF);

  /// 구분선. [line]은 섹션 사이, [lineSoft]는 리스트 항목 사이.
  static const Color line = Color(0xFFD8D8D8);
  static const Color lineSoft = Color(0xFFF0F0F0);

  /// 흰 배경 위에서 살짝 가라앉히는 회색 면(플레이스홀더, 칩 등).
  static const Color paper = Color(0xFFF6F7F9);
  static const Color danger = Color(0xFFE5484D);
  static const Color success = Color(0xFF2FB170);

  /// 난이도 뱃지. 초급은 포인트 그린, 중급은 앰버, 고급은 레드.
  static const Color levelEasy = accent;
  static const Color levelNormal = Color(0xFFF59E0B);
  static const Color levelHard = danger;

  /// 제휴처 아이콘 틴트.
  static const Color tintAmber = Color(0xFFF59E0B);
  static const Color tintBlue = Color(0xFF3B82F6);
  static const Color tintGreen = accent;
}

class AppTheme {
  const AppTheme._();

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.ink,
      primary: AppColors.ink,
      secondary: AppColors.accent,
      surface: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.white,
      dividerTheme: const DividerThemeData(
        color: AppColors.lineSoft,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.ink,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.ink,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.lineSoft),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.ink,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          minimumSize: const Size.fromHeight(54),
          side: const BorderSide(color: AppColors.line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: AppColors.accent.withValues(alpha: 0.45),
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      chipTheme: const ChipThemeData(
        side: BorderSide(color: AppColors.lineSoft),
        backgroundColor: Colors.white,
      ),
    );
  }
}
