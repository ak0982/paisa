import 'package:flutter/material.dart';

import '../models/transaction.dart';
import '../models/transaction_sort.dart';
import '../theme/paisa_colors.dart';
import '../theme/paisa_theme.dart';
import 'sms_coin_slab.dart';
import 'transaction_row.dart';

/// Day-grouped transaction list matching the Transactions screen pattern.
///
/// Ordering is controlled by [sort]. Date sorts keep the day-grouped layout;
/// amount sorts collapse into a single flat, date-labelled card.
class GroupedTransactionList extends StatelessWidget {
  const GroupedTransactionList({
    super.key,
    required this.transactions,
    this.sort = TransactionSort.defaultSort,
    this.padding = EdgeInsets.zero,
    this.emptyTitle = 'No transactions',
    this.emptySubtitle,
    this.shrinkWrap = false,
    this.physics,
    this.onTransactionTap,
  });

  final List<Transaction> transactions;
  final TransactionSort sort;
  final EdgeInsetsGeometry padding;
  final String emptyTitle;
  final String? emptySubtitle;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  /// Overrides the default Coin Flip / Mint Slab detail on row tap.
  final ValueChanged<Transaction>? onTransactionTap;

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) {
      return Padding(
        padding: padding,
        child: _EmptyState(title: emptyTitle, subtitle: emptySubtitle),
      );
    }

    final sections = buildTransactionSections(transactions, sort);

    return ListView.builder(
      padding: padding,
      shrinkWrap: shrinkWrap,
      physics: physics,
      itemCount: sections.length,
      itemBuilder: (context, index) => TransactionSectionCard(
        section: sections[index],
        onTransactionTap: onTransactionTap,
      ),
    );
  }
}

/// Renders a single [TransactionListSection]: an optional day header followed
/// by a card of transaction rows. Shared so grouped/flat layouts stay in sync.
///
/// Rows open the Coin Flip / Mint Slab detail on tap unless [onTransactionTap]
/// overrides it, so every list drills into the same transaction surface.
class TransactionSectionCard extends StatelessWidget {
  const TransactionSectionCard({
    super.key,
    required this.section,
    this.onTransactionTap,
  });

  final TransactionListSection section;
  final ValueChanged<Transaction>? onTransactionTap;

  @override
  Widget build(BuildContext context) {
    final showDate = section.header == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (section.header != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
            child: Text(
              section.header!,
              style: PaisaTheme.sora(
                size: 10.5,
                weight: FontWeight.w700,
                color: PaisaColors.muted,
                letterSpacing: 1.2,
              ),
            ),
          )
        else
          const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          decoration: BoxDecoration(
            color: PaisaColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: PaisaColors.border, width: 1.5),
          ),
          child: Column(
            children: [
              for (var i = 0; i < section.items.length; i++) ...[
                TransactionCoinTap(
                  transaction: section.items[i],
                  onTap: onTransactionTap,
                  child: TransactionRow(
                    transaction: section.items[i],
                    showCategoryChip: true,
                    showSmsLabel: false,
                    showTime: !showDate,
                    showDate: showDate,
                    compact: true,
                    showNavChevron: true,
                  ),
                ),
                if (i < section.items.length - 1)
                  const Divider(height: 1, color: PaisaColors.divider),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: PaisaColors.dividerAlt,
                borderRadius: BorderRadius.circular(18),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.receipt_long_rounded,
                size: 26,
                color: PaisaColors.mutedLight,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: PaisaTheme.sora(size: 15, weight: FontWeight.w700),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: PaisaTheme.manrope(
                  size: 12.5,
                  color: PaisaColors.mutedLight,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
