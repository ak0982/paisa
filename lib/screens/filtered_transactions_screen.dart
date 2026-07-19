import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/category_info.dart';
import '../models/transaction.dart';
import '../models/transaction_sort.dart';
import '../providers/finance_store.dart';
import '../theme/paisa_colors.dart';
import '../theme/paisa_theme.dart';
import '../utils/formatters.dart';
import '../widgets/grouped_transaction_list.dart';
import '../widgets/transaction_sort_control.dart';

/// Lists transactions matching a category, merchant, or income source.
///
/// Without [range], uses the Insights window (`store.insightsTransactions`).
/// With [range], filters to that inclusive report date range instead.
class FilteredTransactionsScreen extends StatefulWidget {
  const FilteredTransactionsScreen({
    super.key,
    required this.title,
    required this.emoji,
    required this.tintBg,
    required this.totalLabel,
    required this.countSingular,
    required this.countPlural,
    required this.emptyTitle,
    required this.emptySubtitleTemplate,
    required this.match,
    this.range,
    this.periodLabel,
  });

  /// Debit transactions in [category] (Insights or report range).
  factory FilteredTransactionsScreen.category({
    Key? key,
    required SpendCategory category,
    DateTimeRange? range,
    String? periodLabel,
  }) {
    final info = CategoryInfo.forCategory(category);
    return FilteredTransactionsScreen(
      key: key,
      title: info.label,
      emoji: info.emoji,
      tintBg: info.tintBg,
      totalLabel: 'Total spent',
      countSingular: 'purchase',
      countPlural: 'purchases',
      emptyTitle: 'No ${info.label.toLowerCase()} spending',
      emptySubtitleTemplate: 'Nothing in this category for {period}.',
      range: range,
      periodLabel: periodLabel,
      match: (t) => !t.isCredit && t.category == category,
    );
  }

  /// Debit transactions for [merchant] in [range] (case-insensitive exact).
  factory FilteredTransactionsScreen.merchant({
    Key? key,
    required String merchant,
    required DateTimeRange range,
    required String periodLabel,
  }) {
    final needle = merchant.toLowerCase();
    return FilteredTransactionsScreen(
      key: key,
      title: merchant,
      emoji: '🏪',
      tintBg: PaisaColors.dividerAlt,
      totalLabel: 'Total spent',
      countSingular: 'transaction',
      countPlural: 'transactions',
      emptyTitle: 'No spending at $merchant',
      emptySubtitleTemplate: 'Nothing for this merchant for {period}.',
      range: range,
      periodLabel: periodLabel,
      match: (t) => !t.isCredit && t.merchant.toLowerCase() == needle,
    );
  }

  /// Credit transactions from [source] in [range] (case-insensitive exact).
  factory FilteredTransactionsScreen.incomeSource({
    Key? key,
    required String source,
    required DateTimeRange range,
    required String periodLabel,
  }) {
    final needle = source.toLowerCase();
    return FilteredTransactionsScreen(
      key: key,
      title: source,
      emoji: '💰',
      tintBg: const Color(0xFFE3F0E7),
      totalLabel: 'Total received',
      countSingular: 'credit',
      countPlural: 'credits',
      emptyTitle: 'No income from $source',
      emptySubtitleTemplate: 'Nothing from this source for {period}.',
      range: range,
      periodLabel: periodLabel,
      match: (t) => t.isCredit && t.merchant.toLowerCase() == needle,
    );
  }

  final String title;
  final String emoji;
  final Color tintBg;
  final String totalLabel;
  final String countSingular;
  final String countPlural;
  final String emptyTitle;

  /// Use `{period}` as the placeholder for the period label (lowercased).
  final String emptySubtitleTemplate;
  final bool Function(Transaction t) match;

  /// Optional inclusive date range (Reports). When null, uses Insights period.
  final DateTimeRange? range;

  /// Subtitle under the title. Defaults to Insights period label.
  final String? periodLabel;

  @override
  State<FilteredTransactionsScreen> createState() =>
      _FilteredTransactionsScreenState();
}

class _FilteredTransactionsScreenState
    extends State<FilteredTransactionsScreen> {
  TransactionSort _sort = TransactionSort.defaultSort;

  /// Matching transactions (unsorted); [GroupedTransactionList] applies [_sort].
  List<Transaction> _transactions(FinanceStore store) {
    final source = widget.range != null
        ? store.transactionsInRange(widget.range!.start, widget.range!.end)
        : store.insightsTransactions;
    return source.where(widget.match).toList();
  }

  String _periodLabel(FinanceStore store) =>
      widget.periodLabel ?? store.insightsPeriodLabel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PaisaColors.surface,
      body: SafeArea(
        child: Consumer<FinanceStore>(
          builder: (context, store, _) {
            final items = _transactions(store);
            final total = items.fold(0.0, (sum, t) => sum + t.amount);
            final label = _periodLabel(store);
            final countLabel = items.length == 1
                ? '1 ${widget.countSingular}'
                : '${items.length} ${widget.countPlural}';

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 22, 6),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: PaisaColors.ink,
                        ),
                      ),
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: widget.tintBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          widget.emoji,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              style: PaisaTheme.sora(
                                size: 18,
                                weight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              label,
                              style: PaisaTheme.manrope(
                                size: 12,
                                weight: FontWeight.w600,
                                color: PaisaColors.mutedLight,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      TransactionSortControl(
                        sort: _sort,
                        showLabel: false,
                        onChanged: (value) => setState(() => _sort = value),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 4, 22, 0),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    decoration: BoxDecoration(
                      color: PaisaColors.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: PaisaColors.dividerAlt),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.totalLabel,
                                style: PaisaTheme.manrope(
                                  size: 11,
                                  color: PaisaColors.mutedCaption,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                formatInr(total),
                                style: PaisaTheme.sora(
                                  size: 20,
                                  weight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          countLabel,
                          style: PaisaTheme.manrope(
                            size: 12.5,
                            weight: FontWeight.w700,
                            color: PaisaColors.mutedLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: GroupedTransactionList(
                    transactions: items,
                    sort: _sort,
                    padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
                    emptyTitle: widget.emptyTitle,
                    emptySubtitle: widget.emptySubtitleTemplate.replaceAll(
                      '{period}',
                      label.toLowerCase(),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
