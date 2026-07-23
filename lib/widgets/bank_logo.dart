import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/paisa_colors.dart';
import '../theme/paisa_theme.dart';
import '../utils/bank_assets.dart';

/// Circular / squircle bank mark for account rows.
///
/// Shows a bundled SVG when [BankAssets] has a logo for [bank]; otherwise a
/// letter on [fallbackColor]. Logos sit on a light plate so dark marks read on
/// Neo-Vault's dark UI.
class BankLogo extends StatelessWidget {
  const BankLogo({
    super.key,
    required this.bank,
    this.size = 40,
    this.radius = 12,
    this.fallbackLetter,
    this.fallbackColor,
  });

  /// Bank display name or account title (e.g. `SBI`, `SBI Savings`).
  final String bank;

  final double size;
  final double radius;

  /// Override letter when no asset (defaults via [BankAssets.fallbackLetter]).
  final String? fallbackLetter;

  /// Plate / letter background when falling back (defaults to primary).
  final Color? fallbackColor;

  @override
  Widget build(BuildContext context) {
    final asset = BankAssets.assetPathFor(bank);
    if (asset == null) {
      return _LetterAvatar(
        letter: fallbackLetter ?? BankAssets.fallbackLetter(bank),
        size: size,
        radius: radius,
        color: fallbackColor ?? PaisaColors.primary,
      );
    }

    final pad = size * 0.14;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFF4F5F7),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: PaisaColors.border, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: Padding(
        padding: EdgeInsets.all(pad),
        child: SvgPicture.asset(
          asset,
          width: size - pad * 2,
          height: size - pad * 2,
          fit: BoxFit.contain,
          semanticsLabel: '$bank logo',
        ),
      ),
    );
  }
}

class _LetterAvatar extends StatelessWidget {
  const _LetterAvatar({
    required this.letter,
    required this.size,
    required this.radius,
    required this.color,
  });

  final String letter;
  final double size;
  final double radius;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: PaisaTheme.sora(
          size: size * 0.375,
          weight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }
}
