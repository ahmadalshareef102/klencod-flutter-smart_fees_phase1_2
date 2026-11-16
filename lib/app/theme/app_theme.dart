import 'package:flutter/material.dart';

/// ألوان الهوية البصرية.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF0D2B5E); // أزرق داكن
  static const Color accent = Color(0xFF2F80ED); // أزرق فاتح
  static const Color success = Color(0xFF1E9E5A); // مدفوعات
  static const Color danger = Color(0xFFD93025); // متأخرات
  static const Color warning = Color(0xFFF2994A); // قريب الاستحقاق
  static const Color lightBackground = Color(0xFFF5F7FA);
  static const Color darkBackground = Color(0xFF0B1220);
  static const Color darkSurface = Color(0xFF111A2E);
}

/// الثيم الفاتح والداكن. الخط Cairo يُسجَّل في pubspec (انظر التعليق هناك)،
/// وإن لم يُسجَّل يعود Flutter تلقائيًا للخط الافتراضي دون أخطاء.
class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
    ).copyWith(
      primary: isDark ? AppColors.accent : AppColors.primary,
      secondary: AppColors.accent,
      error: AppColors.danger,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: 'Cairo',
      scaffoldBackgroundColor:
          isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
        indicatorColor: AppColors.accent.withValues(alpha: 0.18),
      ),
    );
  }
}
