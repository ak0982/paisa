import 'package:flutter/material.dart';

import '../theme/paisa_colors.dart';

/// Neo-Vault card: hard border + optional flat offset shadow.
class NeoSurface extends StatelessWidget {
  const NeoSurface({
    super.key,
    required this.child,
    this.padding,
    this.color = PaisaColors.card,
    this.borderColor = PaisaColors.border,
    this.borderWidth = 1.5,
    this.radius = 16,
    this.shadow = false,
    this.shadowColor = const Color(0xFF000000),
    this.shadowOffset = 5,
    this.width,
    this.height,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color color;
  final Color borderColor;
  final double borderWidth;
  final double radius;
  final bool shadow;
  final Color shadowColor;
  final double shadowOffset;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: shadow
            ? PaisaColors.hardShadow(
                color: shadowColor,
                offset: shadowOffset,
              )
            : null,
      ),
      child: child,
    );
  }
}

/// Rotated sticker tile used for avatars / category chips in the handoff.
class NeoSticker extends StatelessWidget {
  const NeoSticker({
    super.key,
    required this.child,
    this.size = 44,
    this.color = PaisaColors.primary,
    this.borderColor = const Color(0xFF000000),
    this.radius = 12,
    this.angle = -0.05,
  });

  final Widget child;
  final double size;
  final Color color;
  final Color borderColor;
  final double radius;
  final double angle;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: borderColor, width: 2),
        ),
        child: child,
      ),
    );
  }
}
