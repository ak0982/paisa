import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/paisa_colors.dart';
import '../theme/paisa_theme.dart';
import '../utils/bank_assets.dart';

/// Rounded bank mark for account rows and drilldown headers.
///
/// Shows a bundled official logo when [BankAssets] has one for [bank];
/// otherwise a letter on [fallbackColor]. Marks that are not already on a
/// solid plate sit on a light square so dark artwork reads on Neo-Vault.
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

  static const _lightPlate = Color(0xFFF4F5F7);

  /// Slice SFB wordmark PNG is already on this magenta; match letterboxing.
  static const _slicePlate = Color(0xFFC506C2);

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

    final fullBleed = BankAssets.isFullBleed(bank);
    final slug = BankAssets.resolveSlug(bank);
    final plate = slug == 'slice' ? _slicePlate : _lightPlate;
    final pad = fullBleed ? size * 0.04 : size * 0.12;
    final inner = size - pad * 2;
    final isPng = asset.toLowerCase().endsWith('.png');

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: plate,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: PaisaColors.border, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: Padding(
        padding: EdgeInsets.all(pad),
        child: isPng
            ? Image.asset(
                asset,
                width: inner,
                height: inner,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
                semanticLabel: '$bank logo',
              )
            : SvgPicture.asset(
                asset,
                width: inner,
                height: inner,
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
