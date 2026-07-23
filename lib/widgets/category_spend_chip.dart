import 'package:flutter/material.dart';
import '../models/category_info.dart';
import '../theme/paisa_colors.dart';
import '../theme/paisa_theme.dart';
import '../utils/formatters.dart';

class CategorySpendChip extends StatelessWidget {
  const CategorySpendChip({
    super.key,
    required this.info,
    required this.amount,
    this.rotate = false,
    this.angle = -0.035,
  });

  final CategoryInfo info;
  final double amount;
  final bool rotate;
  final double angle;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: PaisaColors.cardElevated,
        border: Border.all(color: info.iconColor, width: 2),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(info.emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                info.label.toUpperCase(),
                style: PaisaTheme.manrope(
                  size: 9,
                  weight: FontWeight.w700,
                  color: PaisaColors.mutedCaption,
                  letterSpacing: 1,
                ),
              ),
              Text(
                formatInr(amount),
                style: PaisaTheme.sora(
                  size: 12.5,
                  weight: FontWeight.w800,
                  color: PaisaColors.ink,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (!rotate) return chip;
    return Transform.rotate(angle: angle, child: chip);
  }
}
