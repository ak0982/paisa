import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'paisa_colors.dart';

abstract final class PaisaTheme {
  // Display: Space Grotesk. Body: Manrope. Both bundled as local assets.
  static const String displayFamily = 'SpaceGrotesk';
  static const String _manropeFamily = 'Manrope';

  /// Display type (amounts, titles, section labels). Formerly Sora.
  static TextStyle sora({
    double size = 14,
    FontWeight weight = FontWeight.w700,
    Color? color,
    double? letterSpacing,
    double? height,
  }) =>
      TextStyle(
        fontFamily: displayFamily,
        fontSize: size,
        fontWeight: weight,
        color: color ?? PaisaColors.ink,
        letterSpacing: letterSpacing,
        height: height,
      );

  static TextStyle display({
    double size = 14,
    FontWeight weight = FontWeight.w700,
    Color? color,
    double? letterSpacing,
    double? height,
  }) =>
      sora(
        size: size,
        weight: weight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
      );

  static TextStyle manrope({
    double size = 14,
    FontWeight weight = FontWeight.w500,
    Color? color,
    double? letterSpacing,
    double? height,
  }) =>
      TextStyle(
        fontFamily: _manropeFamily,
        fontSize: size,
        fontWeight: weight,
        color: color ?? PaisaColors.ink,
        letterSpacing: letterSpacing,
        height: height,
      );

  /// Uppercase tracked section / chip labels (Neo-Vault).
  static TextStyle label({
    double size = 10.5,
    FontWeight weight = FontWeight.w700,
    Color? color,
    double letterSpacing = 1.5,
  }) =>
      sora(
        size: size,
        weight: weight,
        color: color ?? PaisaColors.muted,
        letterSpacing: letterSpacing,
      );

  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: PaisaColors.surface,
      colorScheme: const ColorScheme.dark(
        primary: PaisaColors.primary,
        onPrimary: PaisaColors.inkOnAccent,
        surface: PaisaColors.surface,
        onSurface: PaisaColors.ink,
        secondary: PaisaColors.primaryDeep,
        onSecondary: PaisaColors.inkOnAccent,
        error: PaisaColors.overBudget,
        onError: PaisaColors.ink,
        outline: PaisaColors.border,
      ),
      dividerColor: PaisaColors.divider,
      textTheme: TextTheme(
        bodyMedium: manrope(),
        titleLarge: sora(size: 22, weight: FontWeight.w800),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: PaisaColors.surface,
        foregroundColor: PaisaColors.ink,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: sora(size: 20, weight: FontWeight.w800),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: PaisaColors.cardElevated,
        contentTextStyle: manrope(size: 13, color: PaisaColors.ink),
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: PaisaColors.primary,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return PaisaColors.inkOnAccent;
          }
          return PaisaColors.mutedCaption;
        }),
        trackColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return PaisaColors.primary;
          }
          return PaisaColors.border;
        }),
      ),
    );
  }

  /// Kept for call-sites that still ask for light(); Neo-Vault is dark-only.
  static ThemeData light() => dark();
}
