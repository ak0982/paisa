import 'package:flutter/material.dart';

/// Design tokens from v1 handoff spec.
abstract final class PaisaColors {
  static const primary = Color(0xFF0B7A4B);
  static const primaryBright = Color(0xFF12B981);
  static const primaryDeep = Color(0xFF0F5C42);
  static const warning = Color(0xFFE8A317);
  static const overBudget = Color(0xFFE5533D);
  static const ink = Color(0xFF10201A);
  static const muted = Color(0xFF6B7A72);
  static const mutedLight = Color(0xFF7A8A82);
  static const mutedCaption = Color(0xFF8A9A92);
  static const surface = Color(0xFFF6F8F6);
  static const card = Color(0xFFFFFFFF);
  static const border = Color(0xFFE7ECE8);
  static const divider = Color(0xFFF1F4F2);
  static const dividerAlt = Color(0xFFEEF2EF);
  static const credit = Color(0xFF0FA968);
  static const navInactive = Color(0xFF9AACA2);
  static const navBorder = Color(0xFFEBF0EC);
  static const positiveHighlight = Color(0xFFB8FBD9);
  static const onGradientSecondary = Color(0xC6FFFFFF);

  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryDeep, primary, Color(0xFF12A768)],
    stops: [0.0, 0.6, 1.0],
  );

  static const welcomeGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0C4E38), primary, Color(0xFF0F9E63)],
    stops: [0.0, 0.55, 1.0],
  );

  static const fabGradient = LinearGradient(
    colors: [primaryBright, primary],
  );

  static const bankHdfc = Color(0xFF004C8F);
  static const bankIcici = Color(0xFFB02A30);
  static const bankAxis = Color(0xFF97144D);
  static const bankSbi = Color(0xFF22409A);
  static const bankKotak = Color(0xFFED232A);
}
