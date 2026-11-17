import 'package:flutter/material.dart';

/// لوحة الألوان المعتمدة (كريمي + وردي فاتح + بني عنابي).
class AppColors {
  AppColors._();

  // الوضع الفاتح
  static const Color background = Color(0xFFFBF7EE); // خلفية كريمية
  static const Color surface = Color(0xFFFFFFFF); // البطاقات
  static const Color outline = Color(0xFFEDE6D6); // حدود البطاقات الرفيعة
  static const Color navBackground = Color(0xFFFDFCF7);
  static const Color primary = Color(0xFF844E5C); // موف: أيقونات وأزرار
  static const Color primaryContainer = Color(0xFFFED9E1); // وردي: الشرائح والمؤشرات
  static const Color onPrimaryContainer = Color(0xFF593E43); // نص فوق الوردي
  static const Color text = Color(0xFF1A1A18);
  static const Color textMuted = Color(0xFF6E6462);

  // دلالات مالية
  static const Color success = Color(0xFF3F7D58); // مدفوع
  static const Color danger = Color(0xFF9B383B); // متأخر
  static const Color warning = Color(0xFFB8741F); // قريب الاستحقاق

  // الوضع الداكن (مشتق من نفس الهوية)
  static const Color darkBackground = Color(0xFF1B1718);
  static const Color darkSurface = Color(0xFF262021);
  static const Color darkOutline = Color(0xFF3A3234);
  static const Color darkPrimary = Color(0xFFF2B8C6);
  static const Color darkPrimaryContainer = Color(0xFF5D3E44);
  static const Color darkOnPrimaryContainer = Color(0xFFFED9E1);
  static const Color darkText = Color(0xFFF3E9EA);
  static const Color darkTextMuted = Color(0xFFB9ABAD);
}

/// الثيم الفاتح والداكن. الخط Cairo مسجّل في pubspec.
class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final bg = dark ? AppColors.darkBackground : AppColors.background;
    final surface = dark ? AppColors.darkSurface : AppColors.surface;
    final outline = dark ? AppColors.darkOutline : AppColors.outline;
    final primary = dark ? AppColors.darkPrimary : AppColors.primary;
    final container =
        dark ? AppColors.darkPrimaryContainer : AppColors.primaryContainer;
    final onContainer =
        dark ? AppColors.darkOnPrimaryContainer : AppColors.onPrimaryContainer;
    final text = dark ? AppColors.darkText : AppColors.text;

    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
    ).copyWith(
      primary: primary,
      onPrimary: dark ? AppColors.darkBackground : Colors.white,
      primaryContainer: container,
      onPrimaryContainer: onContainer,
      secondary: primary,
      surface: surface,
      onSurface: text,
      outline: outline,
      outlineVariant: outline,
      error: dark ? const Color(0xFFFFB4AB) : AppColors.danger,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: 'Cairo',
      scaffoldBackgroundColor: bg,
      // شريط علوي مسطح على لون الخلفية وعنوان كبير غامق.
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 26,
          fontWeight: FontWeight.w700,
          color: text,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: primary, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: container,
          foregroundColor: onContainer,
          minimumSize: const Size.fromHeight(52),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
              fontFamily: 'Cairo', fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: container,
        labelStyle: TextStyle(color: onContainer, fontFamily: 'Cairo'),
        shape: const StadiumBorder(),
        side: BorderSide.none,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: dark ? AppColors.darkSurface : AppColors.navBackground,
        surfaceTintColor: Colors.transparent,
        indicatorColor: container,
        indicatorShape: const StadiumBorder(),
        height: 76,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: text),
        ),
        iconTheme: WidgetStatePropertyAll(IconThemeData(color: onContainer)),
      ),
      dividerColor: outline,
    );
  }
}
