import 'package:flutter/material.dart';

/// 러닝 앱 전반의 색상/타이포 토큰.
class AppColors {
  const AppColors._();

  /// 강조가 필요한 곳에만 부분적으로 쓰는 포인트 컬러. 화이트/블랙 톤 위주 배색에서
  /// 러닝 아이콘, 완주 뱃지처럼 눈에 띄어야 하는 요소에만 쓴다.
  static const Color accent = Color(0xFFFF7A33);
  static const Color ink = Color(0xFF101114);
  static const Color inkSoft = Color(0xFF1C1E23);
  static const Color paper = Color(0xFFF6F7F9);
  static const Color danger = Color(0xFFE5484D);
  static const Color success = Color(0xFF2FB170);
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
      scaffoldBackgroundColor: AppColors.paper,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.ink,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          minimumSize: const Size.fromHeight(54),
          side: const BorderSide(color: Color(0xFFDCDFE4)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
        side: BorderSide(color: Color(0xFFE2E5EA)),
        backgroundColor: Colors.white,
      ),
    );
  }
}
