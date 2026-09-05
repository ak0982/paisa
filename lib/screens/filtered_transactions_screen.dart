import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/bank_account.dart';
import '../models/category_info.dart';
import '../models/transaction.dart';
import '../models/transaction_sort.dart';
import '../providers/finance_store.dart';
import '../theme/paisa_colors.dart';
import '../theme/paisa_theme.dart';
import '../utils/formatters.dart';
import '../widgets/bank_logo.dart';
import '../widgets/grouped_transaction_list.dart';
import '../widgets/transaction_sort_control.dart';

enum _AccountFlowFilter { all, incoming, outgoing }

/// Lists transactions matching a category, merchant, income source, or account.
///
/// Without [range], uses the Insights window (`store.insightsTransactions`).
/// With [range], filters to that inclusive report date range instead.
/// When [resolve] is set, it supplies the list directly (account drilldown).
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
    this.match,
    this.resolve,
    this.range,
    this.periodLabel,
    this.showSplitTotals = false,
    this.showFlowChips = false,
    this.headerBank,
    this.chipsAtBottom = false,
  }) : assert(match != null || resolve != null);

  /// Debit transactions in [category] (Insights or report range).
  ///
  /// When [alignWithSpendKpi] is true and [range] is set, uses the same spend
  /// filter as Budget envelopes (`_spendTxns` / `countsTowardSpend`).
  factory FilteredTransactionsScreen.category({
    Key? key,
    required SpendCategory category,
    DateTimeRange? range,
    String? periodLabel,
    bool alignWithSpendKpi = false,
  }) {
    final info = CategoryInfo.forCategory(category);
    if (alignWithSpendKpi && range != null) {
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
        resolve: (store) => store.budgetSpendTransactions(category, range),
      );
    }
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
      tintBg: PaisaColors.cardElevated,
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

  /// All-time transactions for a You-section [account].
  factory FilteredTransactionsScreen.account({
    Key? key,
    required BankAccount account,
  }) {
    final evidenceKey = account.evidenceKey;
    final mask = account.mask;
    return FilteredTransactionsScreen(
      key: key,
      title: account.name,
      emoji: account.badge,
      tintBg: account.color.withOpacity(0.18),
      totalLabel: 'Activity',
      countSingular: 'transaction',
      countPlural: 'transactions',
      emptyTitle: 'No transactions yet',
      emptySubtitleTemplate: 'Nothing on this account so far.',
      periodLabel: mask,
      showSplitTotals: true,
      showFlowChips: true,
      chipsAtBottom: true,
      headerBank: account.bank,
      resolve: (store) => store.transactionsForAccount(evidenceKey: evidenceKey),
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
  final bool Function(Transaction t)? match;

  /// When set, supplies transactions directly (skips [match] / [range]).
  final List<Transaction> Function(FinanceStore store)? resolve;

  /// Optional inclusive date range (Reports). When null, uses Insights period.
  final DateTimeRange? range;

  /// Subtitle under the title. Defaults to Insights period label.
  final String? periodLabel;

  /// Show received / sent instead of a single summed total.
  final bool showSplitTotals;

  /// All / Money in / Money out chips (account drilldown).
  final bool showFlowChips;

  /// When set, header shows [BankLogo] instead of emoji.
  final String? headerBank;

  /// Place flow chips above the bottom safe area (thumb reach).
  final bool chipsAtBottom;

  @override
  State<FilteredTransactionsScreen> createState() =>
      _FilteredTransactionsScreenState();
}

class _FilteredTransactionsScreenState
    extends State<FilteredTransactionsScreen> {
  TransactionSort _sort = TransactionSort.defaultSort;
  _AccountFlowFilter _flow = _AccountFlowFilter.all;

  /// Matching transactions (unsorted); [GroupedTransactionList] applies [_sort].
  List<Transaction> _transactions(FinanceStore store) {
    if (widget.resolve != null) {
      return widget.resolve!(store);
    }
    final source = widget.range != null
        ? store.transactionsInRange(widget.range!.start, widget.range!.end)
        : store.insightsTransactions;
    final match = widget.match!;
    return source.where(match).toList();
  }

  List<Transaction> _applyFlow(List<Transaction> items) {
    if (!widget.showFlowChips) return items;
    return switch (_flow) {
      _AccountFlowFilter.all => items,
      _AccountFlowFilter.incoming =>
        items.where((t) => t.isCredit).toList(growable: false),
      _AccountFlowFilter.outgoing =>
        items.where((t) => !t.isCredit).toList(growable: false),
    };
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
            final allItems = _transactions(store);
            final items = _applyFlow(allItems);
            final received = allItems
                .where((t) => t.isCredit)
                .fold(0.0, (sum, t) => sum + t.amount);
            final sent = allItems
                .where((t) => !t.isCredit)
                .fold(0.0, (sum, t) => sum + t.amount);
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
                      Semantics(
                        button: true,
                        label: 'Back',
                        child: IconButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(
                            Icons.arrow_back_rounded,
                            color: PaisaColors.ink,
                          ),
                        ),
                      ),
                      if (widget.headerBank != null)
                        BankLogo(
                          bank: widget.headerBank!,
                          fallbackLetter: widget.emoji,
                          fallbackColor: widget.tintBg,
                        )
                      else
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
                  padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    decoration: BoxDecoration(
                      color: PaisaColors.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: PaisaColors.dividerAlt),
                    ),
                    child: widget.showSplitTotals
                        ? _SplitTotalsHeader(
                            received: received,
                            sent: sent,
                            countLabel: allItems.length == 1
                                ? '1 ${widget.countSingular}'
                                : '${allItems.length} ${widget.countPlural}',
                          )
                        : Row(
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
                if (widget.showFlowChips && !widget.chipsAtBottom)
                  _FlowChipBar(
                    flow: _flow,
                    onChanged: (f) => setState(() => _flow = f),
                  ),
                Expanded(
                  child: GroupedTransactionList(
                    transactions: items,
                    sort: _sort,
                    padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
                    emptyTitle: widget.emptyTitle,
                    emptySubtitle: widget.emptySubtitleTemplate.replaceAll(
                      '{period}',
                      label.toLowerCase(),
                    ),
                  ),
                ),
                if (widget.showFlowChips && widget.chipsAtBottom)
                  SafeArea(
                    top: false,
                    child: _FlowChipBar(
                      flow: _flow,
                      onChanged: (f) => setState(() => _flow = f),
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

class _SplitTotalsHeader extends StatelessWidget {
  const _SplitTotalsHeader({
    required this.received,
    required this.sent,
    required this.countLabel,
  });

  final double received;
  final double sent;
  final String countLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Received',
                    style: PaisaTheme.manrope(
                      size: 11,
                      color: PaisaColors.mutedCaption,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatInr(received),
                    style: PaisaTheme.sora(
                      size: 18,
                      weight: FontWeight.w800,
                      color: PaisaColors.credit,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sent',
                    style: PaisaTheme.manrope(
                      size: 11,
                      color: PaisaColors.mutedCaption,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatInr(sent),
                    style: PaisaTheme.sora(
                      size: 18,
                      weight: FontWeight.w800,
                      color: PaisaColors.ink,
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
      ],
    );
  }
}

class _FlowChipBar extends StatelessWidget {
  const _FlowChipBar({required this.flow, required this.onChanged});

  final _AccountFlowFilter flow;
  final ValueChanged<_AccountFlowFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 12),
      child: Row(
        children: [
          for (final f in _AccountFlowFilter.values) ...[
            if (f != _AccountFlowFilter.values.first) const SizedBox(width: 8),
            Expanded(
              child: _FlowChip(
                label: switch (f) {
                  _AccountFlowFilter.all => 'All',
                  _AccountFlowFilter.incoming => 'Money in',
                  _AccountFlowFilter.outgoing => 'Money out',
                },
                selected: flow == f,
                onTap: () => onChanged(f),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FlowChip extends StatelessWidget {
  const _FlowChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? PaisaColors.ink : PaisaColors.card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? PaisaColors.ink : PaisaColors.dividerAlt,
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: PaisaTheme.manrope(
                size: 12.5,
                weight: FontWeight.w700,
                color: selected ? PaisaColors.surface : PaisaColors.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
