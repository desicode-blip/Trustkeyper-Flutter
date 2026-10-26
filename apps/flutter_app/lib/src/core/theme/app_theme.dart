import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppTheme {
  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
      primary: AppColors.primary,
      surface: AppColors.background,
      error: AppColors.error,
    );

    final baseTextTheme = ThemeData.light().textTheme;
    final textTheme = baseTextTheme.copyWith(
      displaySmall: const TextStyle(
        fontFamily: 'Roboto',
        fontWeight: FontWeight.w700,
        color: AppColors.heading,
        fontSize: 26,
        height: 32 / 26,
      ),
      headlineSmall: const TextStyle(
        fontFamily: 'Roboto',
        fontWeight: FontWeight.w600,
        color: AppColors.heading,
        fontSize: 24,
        height: 1.2,
      ),
      titleLarge: const TextStyle(
        fontFamily: 'Roboto',
        fontWeight: FontWeight.w600,
        color: AppColors.heading,
        fontSize: 20,
      ),
      titleMedium: const TextStyle(
        fontFamily: 'Roboto',
        fontWeight: FontWeight.w600,
        color: AppColors.heading,
        fontSize: 17,
        height: 22 / 17,
      ),
      bodyLarge: const TextStyle(
        fontFamily: 'Roboto',
        fontWeight: FontWeight.w400,
        color: AppColors.body,
        fontSize: 17,
        height: 24 / 17,
      ),
      bodyMedium: const TextStyle(
        fontFamily: 'Roboto',
        fontWeight: FontWeight.w400,
        color: AppColors.body,
        fontSize: 15,
        height: 20 / 15,
      ),
      labelLarge: const TextStyle(
        fontFamily: 'Roboto',
        fontWeight: FontWeight.w600,
        fontSize: 15,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Roboto',
      fontFamilyFallback: const ['GeneralSans'],
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      textTheme: textTheme.apply(fontFamilyFallback: const ['GeneralSans']),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.heading,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      // Material floating-label field: the name sits inside the box and
      // moves up when you tap or type. Used for every input in the app.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.background,
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        labelStyle: const TextStyle(fontSize: 17, color: AppColors.muted),
        floatingLabelStyle: const TextStyle(
          fontSize: 15,
          color: AppColors.primaryDark,
        ),
        hintStyle: const TextStyle(color: Color(0xFF98A2B3)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.background,
        indicatorColor: AppColors.primarySoft,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: 'Roboto',
            fontSize: 13,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.muted,
          ),
        ),
      ),
    );
  }
}
