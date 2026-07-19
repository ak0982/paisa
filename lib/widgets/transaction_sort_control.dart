import 'package:flutter/material.dart';

import '../models/transaction_sort.dart';
import '../theme/paisa_colors.dart';
import '../theme/paisa_theme.dart';

/// Compact, reusable sort control shared by every transaction list.
///
/// Renders as a filter-chip-styled button that opens a menu of sort options.
/// Styling mirrors the existing filter chips so it drops into any header row.
class TransactionSortControl extends StatelessWidget {
  const TransactionSortControl({
    super.key,
    required this.sort,
    required this.onChanged,
    this.options = TransactionSort.values,
    this.showLabel = true,
  });

  final TransactionSort sort;
  final ValueChanged<TransactionSort> onChanged;

  /// Which sort options to offer. Defaults to all (date + amount).
  final List<TransactionSort> options;

  /// Whether to show the short label next to the icon on the collapsed chip.
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<TransactionSort>(
      tooltip: 'Sort transactions',
      initialValue: sort,
      onSelected: onChanged,
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      color: PaisaColors.card,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: PaisaColors.dividerAlt),
      ),
      itemBuilder: (context) => [
        for (final option in options)
          PopupMenuItem<TransactionSort>(
            value: option,
            height: 44,
            child: Row(
              children: [
                Icon(
                  option.icon,
                  size: 16,
                  color: option == sort
                      ? PaisaColors.primary
                      : PaisaColors.mutedLight,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    option.label,
                    style: PaisaTheme.manrope(
                      size: 13,
                      weight: option == sort
                          ? FontWeight.w700
                          : FontWeight.w600,
                      color: option == sort
                          ? PaisaColors.primary
                          : const Color(0xFF42524A),
                    ),
                  ),
                ),
                if (option == sort)
                  const Icon(
                    Icons.check_rounded,
                    size: 16,
                    color: PaisaColors.primary,
                  ),
              ],
            ),
          ),
      ],
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: showLabel ? 12 : 9,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: PaisaColors.card,
          border: Border.all(color: PaisaColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.swap_vert_rounded,
              size: 16,
              color: PaisaColors.primary,
            ),
            if (showLabel) ...[
              const SizedBox(width: 6),
              Text(
                sort.shortLabel,
                style: PaisaTheme.manrope(
                  size: 12.5,
                  weight: FontWeight.w700,
                  color: const Color(0xFF42524A),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
