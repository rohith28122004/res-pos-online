import 'package:flutter/material.dart';

/// Warm neutral surfaces with a single teal accent. Status is always shown
/// with text as well as colour.
abstract final class AppColors {
  static const accent = Color(0xFF0F6E66);
  static const surface = Color(0xFFFBF8F3);
  static const surfaceDim = Color(0xFFF1ECE4);
  static const ink = Color(0xFF2B2622);
  static const success = Color(0xFF2E7D32);
  static const warning = Color(0xFF9A6200);
  static const danger = Color(0xFFB3261E);
  static const info = Color(0xFF285A8C);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    primary: AppColors.accent,
    surface: AppColors.surface,
    error: AppColors.danger,
  ).copyWith(surfaceContainerLowest: Colors.white, onSurface: AppColors.ink);
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, visualDensity: VisualDensity.standard);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.surface,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 1,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE6DED3)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size(64, 48))),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(minimumSize: const Size(48, 48))),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      isDense: false,
      filled: true,
      fillColor: Colors.white,
    ),
    chipTheme: base.chipTheme.copyWith(labelStyle: const TextStyle(fontSize: 15)),
    navigationRailTheme: const NavigationRailThemeData(backgroundColor: AppColors.surfaceDim),
    dividerTheme: const DividerThemeData(color: Color(0xFFE6DED3)),
  );
}
