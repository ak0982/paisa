import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/finance_store.dart';
import '../theme/paisa_colors.dart';
import '../theme/paisa_theme.dart';
import '../utils/formatters.dart';
import '../widgets/category_spend_chip.dart';
import 'category_transactions_screen.dart';
import 'reports_screen.dart';

class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<FinanceStore>(
      builder: (context, store, _) {
        final spending = store.insightsCategorySpending;
        final sorted = spending.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final foodDelta = store.insightsFoodDelta();
        final hasTransactions = store.transactions.isNotEmpty;
        final showEmpty = !store.isLoading &&
            (!hasTransactions || store.insightsSpent <= 0);

        return RefreshIndicator(
          color: PaisaColors.primary,
          onRefresh: store.syncFromSms,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Insights',
                      style: PaisaTheme.sora(
                        size: 22,
                        weight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ReportsScreen(),
                        ),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: PaisaColors.primary,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: PaisaColors.inkOnAccent,
                            width: 2,
                          ),
                        ),
                        child: Text(
                          'REPORTS',
                          style: PaisaTheme.sora(
                            size: 11,
                            weight: FontWeight.w800,
                            color: PaisaColors.inkOnAccent,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (store.isViewingHistoricalMonth) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: PaisaColors.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: PaisaColors.primary.withOpacity(0.2),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.calendar_month_outlined,
                          size: 18,
                          color: PaisaColors.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Dashboard shows ${store.currentMonthLabel}. Insights below cover ${store.insightsPeriodLabel.toLowerCase()}.',
                            style: PaisaTheme.manrope(
                              size: 12,
                              weight: FontWeight.w600,
                              color: PaisaColors.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: PaisaColors.primary,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: PaisaColors.inkOnAccent,
                      width: 2.5,
                    ),
                    boxShadow: PaisaColors.hardShadow(offset: 5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TOTAL SPENT · ${store.insightsPeriodLabel}'
                            .toUpperCase(),
                        style: PaisaTheme.manrope(
                          size: 10.5,
                          weight: FontWeight.w700,
                          color: PaisaColors.inkOnAccent,
                          letterSpacing: 1.2,
                        ),
                      ),
                      Text(
                        formatInr(store.insightsSpent),
                        style: PaisaTheme.sora(
                          size: 34,
                          weight: FontWeight.w800,
                          color: PaisaColors.inkOnAccent,
                          letterSpacing: -0.5,
                        ),
                      ),
                      if (sorted.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: PaisaColors.inkOnAccent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${sorted.length} categories · ${store.insightsTransactions.where((t) => !t.isCredit).length} purchases',
                            style: PaisaTheme.manrope(
                              size: 11.5,
                              weight: FontWeight.w700,
                              color: PaisaColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _StatCard(
                      label: 'Daily average',
                      value: formatInr(store.insightsDailyAverage),
                    ),
                    const SizedBox(width: 11),
                    _StatCard(
                      label: 'Highest day',
                      value: formatInr(store.insightsHighestDaySpend),
                    ),
                  ],
                ),
                if (store.isLoading) ...[
                  const SizedBox(height: 24),
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: PaisaColors.primary,
                      ),
                    ),
                  ),
                ] else if (showEmpty) ...[
                  const SizedBox(height: 18),
                  _InsightsEmptyHint(store: store),
                ],
                if (sorted.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    'Spending by category',
                    style: PaisaTheme.sora(size: 14, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  CategorySpendStickerGrid(
                    tiles: [
                      for (var i = 0; i < sorted.length; i++)
                        CategorySpendTile(
                          category: sorted[i].key,
                          amount: sorted[i].value,
                          share: store.insightsSpent > 0
                              ? (sorted[i].value / store.insightsSpent)
                                  .clamp(0.0, 1.0)
                              : 0,
                          emphasize: i == 0,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => CategoryTransactionsScreen(
                                category: sorted[i].key,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                if (foodDelta != null && foodDelta != 0) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: PaisaColors.cardElevated,
                      border: Border.all(
                        color: PaisaColors.warning,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: PaisaColors.warning,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: PaisaColors.inkOnAccent,
                              width: 2,
                            ),
                          ),
                          alignment: Alignment.center,
                          child:
                              const Text('🍔', style: TextStyle(fontSize: 16)),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              style: PaisaTheme.manrope(
                                size: 12.5,
                                color: PaisaColors.mutedCaption,
                              ),
                              children: [
                                TextSpan(
                                  text: foodDelta > 0
                                      ? 'You spent ${formatInr(foodDelta)} more'
                                      : 'You spent ${formatInr(foodDelta.abs())} less',
                                  style: const TextStyle(
                                    color: PaisaColors.ink,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                TextSpan(
                                  text:
                                      ' on Food in the last 90 days vs the prior 90 days.',
                                  style: TextStyle(
                                    color: foodDelta > 0
                                        ? PaisaColors.warning
                                        : PaisaColors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (store.insightsTopMerchants.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    'Top merchants',
                    style: PaisaTheme.sora(size: 14, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: PaisaColors.card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: PaisaColors.dividerAlt),
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < store.insightsTopMerchants.length; i++) ...[
                          _MerchantRow(
                            rank: i + 1,
                            name: store.insightsTopMerchants[i].$1,
                            sub: store.insightsTopMerchants[i].$2,
                            amount: store.insightsTopMerchants[i].$3,
                          ),
                          if (i < store.insightsTopMerchants.length - 1)
                            const Divider(
                              height: 1,
                              color: PaisaColors.divider,
                            ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InsightsEmptyHint extends StatelessWidget {
  const _InsightsEmptyHint({required this.store});

  final FinanceStore store;

  @override
  Widget build(BuildContext context) {
    final hasTransactions = store.transactions.isNotEmpty;
    final headline = hasTransactions
        ? 'No spending insights yet'
        : 'No transactions yet';
    final subtitle = hasTransactions
        ? 'Pull down to refresh, or go to Profile → Rescan SMS.'
        : 'Scan your SMS inbox to build spending insights from bank alerts.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: PaisaColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: PaisaColors.dividerAlt),
      ),
      child: Column(
        children: [
          Text(hasTransactions ? '📊' : '📭',
              style: const TextStyle(fontSize: 32)),
          const SizedBox(height: 8),
          Text(
            headline,
            textAlign: TextAlign.center,
            style: PaisaTheme.manrope(
              size: 13,
              weight: FontWeight.w600,
              color: PaisaColors.muted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: PaisaTheme.manrope(
              size: 12,
              color: PaisaColors.mutedCaption,
            ),
          ),
          if (!hasTransactions) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => store.syncFromSms(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: PaisaColors.primary,
                  foregroundColor: PaisaColors.inkOnAccent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'Scan SMS now',
                  style: PaisaTheme.sora(
                    size: 14,
                    weight: FontWeight.w800,
                    color: PaisaColors.inkOnAccent,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        decoration: BoxDecoration(
          color: PaisaColors.card,
          border: Border.all(color: PaisaColors.dividerAlt),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: PaisaTheme.manrope(
                size: 11,
                color: PaisaColors.mutedCaption,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: PaisaTheme.sora(size: 18, weight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _MerchantRow extends StatelessWidget {
  const _MerchantRow({
    required this.rank,
    required this.name,
    required this.sub,
    required this.amount,
  });

  final int rank;
  final String name;
  final String sub;
  final double amount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: PaisaColors.dividerAlt,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              '$rank',
              style: PaisaTheme.sora(
                size: 12,
                weight: FontWeight.w700,
                color: PaisaColors.mutedCaption,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: PaisaTheme.manrope(
                    size: 13.5,
                    weight: FontWeight.w600,
                  ),
                ),
                Text(
                  sub,
                  style: PaisaTheme.manrope(
                    size: 11,
                    color: PaisaColors.mutedCaption,
                  ),
                ),
              ],
            ),
          ),
          Text(
            formatInr(amount),
            style: PaisaTheme.sora(size: 14, weight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
