import 'package:flutter/material.dart';
import '../theme/paisa_colors.dart';
import '../theme/paisa_theme.dart';

class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isWhite = false,
    this.textColor,
  });

  final String label;
  final VoidCallback onPressed;
  final bool isWhite;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final bg = isWhite ? PaisaColors.cardElevated : PaisaColors.primary;
    final fg = textColor ??
        (isWhite ? PaisaColors.primary : PaisaColors.inkOnAccent);
    final border = isWhite ? PaisaColors.primary : PaisaColors.primary;

    return SizedBox(
      width: double.infinity,
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border, width: 2.5),
          boxShadow: PaisaColors.hardShadow(
            color: isWhite ? PaisaColors.primary : const Color(0xFF000000),
            offset: 4,
          ),
        ),
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: fg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Text(
            label,
            style: PaisaTheme.sora(
              size: 15,
              weight: FontWeight.w800,
              color: fg,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }
}
