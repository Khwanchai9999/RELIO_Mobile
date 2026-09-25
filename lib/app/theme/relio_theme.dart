import 'package:flutter/material.dart';

import 'relio_colors.dart';
import 'relio_typography.dart';

abstract final class RelioTheme {
  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: RelioColors.primary,
          brightness: brightness,
          surface: dark ? RelioColors.darkSurface : RelioColors.lightSurface,
        ).copyWith(
          primary: dark ? const Color(0xFF2DD4BF) : RelioColors.primary,
          error: dark ? const Color(0xFFF87171) : RelioColors.sos,
        );
    final textTheme = RelioTypography.textTheme(brightness);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark
          ? RelioColors.darkBackground
          : RelioColors.lightBackground,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: dark
            ? RelioColors.darkSurface
            : RelioColors.lightSurface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontSize: 18,
        ),
      ),
      cardTheme: CardThemeData(
        color: dark ? RelioColors.darkSurface : RelioColors.lightSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: dark ? RelioColors.darkBorder : RelioColors.border,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? RelioColors.darkSurface : RelioColors.lightSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: dark ? RelioColors.darkBorder : RelioColors.border,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: dark ? RelioColors.darkBorder : RelioColors.border,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: RelioColors.primary, width: 1.5),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: dark
            ? RelioColors.darkSurface
            : RelioColors.lightSurface,
        indicatorColor: dark
            ? RelioColors.primary.withValues(alpha: 0.18)
            : RelioColors.primary.withValues(alpha: 0.12),
        labelTextStyle: WidgetStatePropertyAll(
          textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      dividerColor: dark ? RelioColors.darkBorder : RelioColors.border,
      dialogTheme: DialogThemeData(
        backgroundColor: dark
            ? RelioColors.darkSurface
            : RelioColors.lightSurface,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: dark
            ? RelioColors.darkSurface
            : RelioColors.lightSurface,
        modalBackgroundColor: dark
            ? RelioColors.darkSurface
            : RelioColors.lightSurface,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
