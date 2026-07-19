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
  });

  final CategoryInfo info;
  final double amount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: PaisaColors.card,
        border: Border.all(color: PaisaColors.navBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: info.tintBg,
              borderRadius: BorderRadius.circular(9),
            ),
            alignment: Alignment.center,
            child: Text(info.emoji, style: const TextStyle(fontSize: 15)),
          ),
          const SizedBox(width: 9),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                info.label,
                style: PaisaTheme.manrope(
                  size: 11,
                  weight: FontWeight.w600,
                  color: PaisaColors.mutedCaption,
                ),
              ),
              Text(
                formatInr(amount),
                style: PaisaTheme.sora(size: 13, weight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
