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
    if (isWhite) {
      return SizedBox(
        width: double.infinity,
        height: 54,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: PaisaColors.card,
            foregroundColor: textColor ?? PaisaColors.primary,
            elevation: 8,
            shadowColor: Colors.black26,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: Text(
            label,
            style: PaisaTheme.manrope(
              size: 16,
              weight: FontWeight.w700,
              color: textColor ?? PaisaColors.primary,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: PaisaColors.fabGradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x6612B981),
              blurRadius: 28,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: Text(
            label,
            style: PaisaTheme.manrope(
              size: 16,
              weight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
