import 'package:flutter/material.dart';

/// Neo-Vault design tokens (dark-first redesign handoff).
abstract final class PaisaColors {
  /// Neon lime — primary actions, active states, hero fills.
  static const primary = Color(0xFFC8FF4D);
  static const primaryBright = Color(0xFFC8FF4D);
  static const primaryDeep = Color(0xFF9FD936);

  /// Semantic status.
  static const safe = Color(0xFF2FBF71);
  static const warning = Color(0xFFFFC94C);
  static const overBudget = Color(0xFFFF3B5C);
  static const overBudgetSoft = Color(0xFFFF6B85);

  /// Surfaces (dark).
  static const surface = Color(0xFF0A0A0B);
  static const card = Color(0xFF131315);
  static const cardElevated = Color(0xFF17181A);
  static const border = Color(0xFF232427);
  static const divider = Color(0xFF232427);
  static const dividerAlt = Color(0xFF232427);

  /// Text.
  /// [ink] is the primary readable text on dark surfaces (white).
  static const ink = Color(0xFFFFFFFF);
  /// Text on lime / light filled surfaces.
  static const inkOnAccent = Color(0xFF111114);
  static const muted = Color(0xFF6B6B63);
  static const mutedLight = Color(0xFF7A7A72);
  static const mutedCaption = Color(0xFF9A9A90);

  /// Credits / positive amounts on dark.
  static const credit = Color(0xFFC8FF4D);
  static const debit = Color(0xFFFFFFFF);

  static const navInactive = Color(0xFF6B6B63);
  static const navBorder = Color(0xFFC8FF4D);
  static const positiveHighlight = Color(0xFFC8FF4D);
  static const onGradientSecondary = Color(0xFF1A1A1A);

  /// Legacy gradient names remapped to flat Neo-Vault lime fills.
  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, primaryDeep],
  );

  static const welcomeGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [surface, Color(0xFF111114), surface],
    stops: [0.0, 0.55, 1.0],
  );

  static const fabGradient = LinearGradient(
    colors: [primary, primaryDeep],
  );

  static const bankHdfc = Color(0xFF004C8F);
  static const bankIcici = Color(0xFFB02A30);
  static const bankAxis = Color(0xFF97144D);
  static const bankSbi = Color(0xFF22409A);
  static const bankKotak = Color(0xFFED232A);

  /// Category solids (flat, saturated).
  static const catFood = Color(0xFFFF7A45);
  static const catTravel = Color(0xFF4C8DFF);
  static const catShopping = Color(0xFFC879FF);
  static const catBills = Color(0xFFFFC94C);
  static const catEmi = Color(0xFF2FBF71);
  static const catEntertainment = Color(0xFF7C6CFF);
  static const catHealth = Color(0xFFFF5C8A);
  static const catTransfer = Color(0xFF2FD1C6);
  static const catIncome = Color(0xFFC8FF4D);
  static const catAtm = Color(0xFF8A94A6);
  static const catOther = Color(0xFFB8BCC4);

  /// Hard Neo-Vault offset shadow (no blur).
  static List<BoxShadow> hardShadow({
    Color color = const Color(0xFF000000),
    double offset = 5,
  }) =>
      [
        BoxShadow(
          color: color,
          offset: Offset(offset, offset),
          blurRadius: 0,
        ),
      ];

  static BorderSide thickBorder({
    Color color = border,
    double width = 2,
  }) =>
      BorderSide(color: color, width: width);
}
