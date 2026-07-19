import 'package:flutter/material.dart';
import 'paisa_colors.dart';

abstract final class PaisaTheme {
  // Fonts are bundled as local assets (see pubspec.yaml). Sora & Manrope are
  // variable fonts, so Flutter resolves the FontWeight onto the wght axis.
  static const String _soraFamily = 'Sora';
  static const String _manropeFamily = 'Manrope';

  static TextStyle sora({
    double size = 14,
    FontWeight weight = FontWeight.w700,
    Color? color,
    double? letterSpacing,
  }) =>
      TextStyle(
        fontFamily: _soraFamily,
        fontSize: size,
        fontWeight: weight,
        color: color ?? PaisaColors.ink,
        letterSpacing: letterSpacing,
      );

  static TextStyle manrope({
    double size = 14,
    FontWeight weight = FontWeight.w500,
    Color? color,
  }) =>
      TextStyle(
        fontFamily: _manropeFamily,
        fontSize: size,
        fontWeight: weight,
        color: color ?? PaisaColors.ink,
      );

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: PaisaColors.surface,
      colorScheme: ColorScheme.fromSeed(
        seedColor: PaisaColors.primary,
        primary: PaisaColors.primary,
        surface: PaisaColors.surface,
      ),
      textTheme: TextTheme(
        bodyMedium: manrope(),
        titleLarge: sora(size: 22, weight: FontWeight.w800),
      ),
    );
  }
}
