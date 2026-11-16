import 'package:flutter/material.dart';

/// Couleurs de la charte graphique MboaRide (docs/design).
class MboaColors {
  static const Color green = Color(0xFF0B6E4F);
  static const Color sun = Color(0xFFF2B705);
  static const Color night = Color(0xFF12261F);
  static const Color sand = Color(0xFFF6F4EE);
  static const Color red = Color(0xFFC0392B);
  static const Color mutedText = Color(0xFF4A5751);
  static const Color border = Color(0xFFB8C2BC);
}

ThemeData buildMboaTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: MboaColors.green).copyWith(
    primary: MboaColors.green,
    onPrimary: Colors.white,
    secondary: MboaColors.sun,
    onSecondary: MboaColors.night,
    error: MboaColors.red,
    surface: MboaColors.sand,
    onSurface: MboaColors.night,
  );
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: MboaColors.border, width: 1.5),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: MboaColors.sand,
    appBarTheme: const AppBarTheme(
      backgroundColor: MboaColors.green,
      foregroundColor: Colors.white,
      titleTextStyle: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: MboaColors.green, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
  );
}
