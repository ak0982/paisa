import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/category_info.dart';
import '../providers/finance_store.dart';
import '../theme/paisa_colors.dart';
import '../theme/paisa_theme.dart';
import '../utils/formatters.dart';
import '../widgets/paisa_coin.dart';
import '../widgets/paisa_nav_chevron.dart';
import 'category_transactions_screen.dart';
import 'day_strip_screen.dart';
import 'reports_screen.dart';

/// Paisa Ledger Coin — the whole spending history struck as one coin.
///
/// Same family as the day Paisa Coin: milled rim, a split gauge where SPENT is
/// white and IN is lime, a recessed field carrying the exact spend total, and
/// legends struck along the rim. Below the hero, one job per section — three
/// coin legends (daily average, peak day, net), then category and merchant
/// rows each stamped with their own miniature coin token.
class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<FinanceStore>(
      builder: (context, store, _) {
        final spending = store.insightsCategorySpending;
        final sorted = spending.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final spent = store.insightsSpent;
        final income = store.insightsIncome;
        final foodDelta = store.insightsFoodDelta();
        final merchants = store.insightsTopMerchants;
        final hasTransactions = store.transactions.isNotEmpty;
        final showEmpty = !store.isLoading && (!hasTransactions || spent <= 0);

        return RefreshIndicator(
          color: PaisaColors.primary,
          onRefresh: store.syncFromSms,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const PaisaCoinWordmark(suffix: 'STATS'),
                    const Spacer(),
                    _ReportsButton(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ReportsScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
                if (store.isViewingHistoricalMonth) ...[
                  const SizedBox(height: 14),
                  _StruckNote(
                    accent: PaisaColors.primary,
                    child: Text(
                      'Dashboard shows ${store.currentMonthLabel}. Insights below cover ${store.insightsPeriodLabel.toLowerCase()}.',
                      style: PaisaTheme.manrope(
                        size: 12,
                        weight: FontWeight.w600,
                        color: PaisaColors.mutedCaption,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                _LedgerCoinHero(
                  periodLabel: store.insightsPeriodLabel,
                  spent: spent,
                  income: income,
                  moves: store.insightsSpendCount,
                ),
                const SizedBox(height: 22),
                _CoinLegendRail(
                  dailyAverage: store.insightsDailyAverage,
                  peakDaySpend: store.insightsHighestDaySpend,
                  peakDay: store.insightsHighestDay,
                  net: store.insightsNet,
                ),
                if (store.isLoading) ...[
                  const SizedBox(height: 28),
                  const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: PaisaColors.primary,
                    ),
                  ),
                ] else if (showEmpty) ...[
                  const SizedBox(height: 8),
                  _InsightsEmptyHint(store: store),
                ],
                if (sorted.isNotEmpty) ...[
                  const SizedBox(height: 26),
                  _SectionHeading(
                    label: 'BY CATEGORY',
                    trailing: sorted.length == 1
                        ? '1 CATEGORY'
                        : '${sorted.length} CATEGORIES',
                  ),
                  for (var i = 0; i < sorted.length; i++)
                    _LedgerRow(
                      index: i,
                      isLast: i == sorted.length - 1,
                      token: _categoryToken(
                        sorted[i].key,
                        spent > 0 ? sorted[i].value / spent : 0,
                      ),
                      title: CategoryInfo.forCategory(sorted[i].key).label,
                      subtitle: _shareCaption(
                        spent > 0 ? sorted[i].value / spent : 0,
                      ),
                      amount: sorted[i].value,
                      topStamp: i == 0 && sorted.length > 1,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => CategoryTransactionsScreen(
                            category: sorted[i].key,
                          ),
                        ),
                      ),
                    ),
                ],
                if (foodDelta != null && foodDelta != 0) ...[
                  const SizedBox(height: 20),
                  _StruckNote(
                    accent: foodDelta > 0
                        ? PaisaColors.warning
                        : PaisaColors.primary,
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
                if (merchants.isNotEmpty) ...[
                  const SizedBox(height: 26),
                  const _SectionHeading(label: 'TOP MERCHANTS'),
                  for (var i = 0; i < merchants.length; i++)
                    _LedgerRow(
                      index: i,
                      isLast: i == merchants.length - 1,
                      token: PaisaCoinToken(
                        color: i == 0
                            ? PaisaColors.primary
                            : PaisaColors.mutedCaption,
                        fill: merchants.first.$3 > 0
                            ? (merchants[i].$3 / merchants.first.$3)
                                .clamp(0.06, 1.0)
                            : 0,
                        glyph: '${i + 1}',
                        glyphSize: 12,
                      ),
                      title: merchants[i].$1,
                      subtitle: merchants[i].$2,
                      amount: merchants[i].$3,
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  static PaisaCoinToken _categoryToken(SpendCategory category, double share) {
    final info = CategoryInfo.forCategory(category);
    return PaisaCoinToken(
      color: info.iconColor,
      fill: share.clamp(0.06, 1.0),
      glyph: info.emoji,
      glyphSize: 14,
    );
  }

  static String _shareCaption(double share) {
    final pct = formatSharePercent(share);
    return pct.isEmpty ? 'of the ledger' : '$pct of the ledger';
  }
}

// ── Hero: the ledger coin ───────────────────────────────────────────────────

class _LedgerCoinHero extends StatelessWidget {
  const _LedgerCoinHero({
    required this.periodLabel,
    required this.spent,
    required this.income,
    required this.moves,
  });

  final String periodLabel;
  final double spent;
  final double income;
  final int moves;

  @override
  Widget build(BuildContext context) {
    return PaisaCoinRise(
      child: Column(
        children: [
          Text(
            'LEDGER',
            style: PaisaTheme.label(
              size: 10,
              color: PaisaColors.muted,
              letterSpacing: 2.6,
            ),
          ),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              periodLabel.toUpperCase(),
              style: PaisaTheme.sora(
                size: 19,
                weight: FontWeight.w800,
                color: PaisaColors.ink,
                letterSpacing: 3.4,
              ),
            ),
          ),
          const SizedBox(height: 16),
          PaisaCoinFace(
            outShare: paisaCoinOutShare(spent, income),
            hasFlow: spent + income > 0,
            topLegend: moves > 0 ? '$moves TRANSACTIONS' : '',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'SPENT',
                  style: PaisaTheme.label(
                    size: 10,
                    color: PaisaColors.mutedCaption,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    formatInr(spent),
                    style: PaisaTheme.sora(
                      size: 28,
                      weight: FontWeight.w800,
                      color: PaisaColors.ink,
                      letterSpacing: -0.8,
                      height: 1.0,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: 34,
                  height: 1.5,
                  color: PaisaColors.muted.withOpacity(0.55),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'IN',
                      style: PaisaTheme.label(
                        size: 10,
                        color: PaisaColors.primary,
                        letterSpacing: 2.4,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          formatInr(income),
                          style: PaisaTheme.sora(
                            size: 14,
                            weight: FontWeight.w800,
                            color: PaisaColors.primary,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Coin legends ────────────────────────────────────────────────────────────

/// Three legends struck under the coin, hairline-ruled — not floating chips.
class _CoinLegendRail extends StatelessWidget {
  const _CoinLegendRail({
    required this.dailyAverage,
    required this.peakDaySpend,
    required this.peakDay,
    required this.net,
  });

  final double dailyAverage;
  final double peakDaySpend;
  final DateTime? peakDay;
  final double net;

  @override
  Widget build(BuildContext context) {
    return PaisaCoinRise(
      duration: const Duration(milliseconds: 520),
      offsetY: 10,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: PaisaColors.border),
            bottom: BorderSide(color: PaisaColors.border),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: _CoinLegend(
                label: 'DAILY AVG',
                value: formatInr(dailyAverage),
                caption: 'per day',
              ),
            ),
            const _LegendRule(),
            Expanded(
              child: _CoinLegend(
                label: 'PEAK DAY',
                value: formatInr(peakDaySpend),
                caption: peakDay == null
                    ? 'no spend yet'
                    : formatDayStripHeader(peakDay!),
                onTap: peakDay == null
                    ? null
                    : () => DayStripScreen.open(context, day: peakDay),
              ),
            ),
            const _LegendRule(),
            Expanded(
              child: _CoinLegend(
                label: 'NET',
                value: formatAmount(net, isCredit: net >= 0),
                valueColor: net >= 0 ? PaisaColors.primary : PaisaColors.ink,
                caption: 'in − out',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendRule extends StatelessWidget {
  const _LegendRule();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 46,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: PaisaColors.border,
    );
  }
}

class _CoinLegend extends StatelessWidget {
  const _CoinLegend({
    required this.label,
    required this.value,
    required this.caption,
    this.valueColor,
    this.onTap,
  });

  final String label;
  final String value;
  final String caption;
  final Color? valueColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tappable = onTap != null;
    final column = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          style: PaisaTheme.label(
            size: 9,
            color: PaisaColors.muted,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 5),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: PaisaTheme.sora(
              size: 15.5,
              weight: FontWeight.w800,
              color: valueColor ?? PaisaColors.ink,
              letterSpacing: -0.3,
            ),
          ),
        ),
        const SizedBox(height: 3),
        if (!tappable)
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PaisaTheme.manrope(
              size: 10,
              weight: FontWeight.w600,
              color: PaisaColors.muted,
            ),
          )
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PaisaTheme.manrope(
                    size: 10,
                    weight: FontWeight.w600,
                    color: PaisaColors.primary.withOpacity(0.85),
                  ),
                ),
              ),
              const PaisaNavChevron(
                size: 14,
                color: PaisaColors.primary,
              ),
            ],
          ),
      ],
    );

    if (!tappable) return column;
    return Semantics(
      button: true,
      label: '$label, $caption',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: column,
      ),
    );
  }
}

// ── Stamped ledger rows ─────────────────────────────────────────────────────

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.label, this.trailing});

  final String label;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            label,
            style: PaisaTheme.label(
              size: 10,
              color: PaisaColors.mutedCaption,
              letterSpacing: 2.4,
            ),
          ),
          const Spacer(),
          if (trailing != null)
            Text(
              trailing!,
              style: PaisaTheme.manrope(
                size: 9.5,
                weight: FontWeight.w700,
                color: PaisaColors.muted,
                letterSpacing: 1,
              ),
            ),
        ],
      ),
    );
  }
}

/// A coin-stamped ledger row: miniature coin token, title + caption, amount.
/// Same row language as the Paisa Coin day list.
class _LedgerRow extends StatelessWidget {
  const _LedgerRow({
    required this.token,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.index,
    required this.isLast,
    this.topStamp = false,
    this.onTap,
  });

  final Widget token;
  final String title;
  final String subtitle;
  final double amount;
  final int index;
  final bool isLast;
  final bool topStamp;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Staggered stamp-in, capped so long lists never crawl.
    final delayMs = math.min(index * 32, 192);

    final row = Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(color: PaisaColors.border, width: 1),
              ),
      ),
      child: Row(
        children: [
          token,
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (topStamp) ...[
                      const _TopStamp(),
                      const SizedBox(width: 7),
                    ],
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PaisaTheme.sora(
                          size: 15,
                          weight: FontWeight.w800,
                          color: PaisaColors.ink,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      formatInr(amount),
                      style: PaisaTheme.sora(
                        size: 14,
                        weight: FontWeight.w800,
                        color: PaisaColors.ink,
                      ),
                    ),
                    if (onTap != null) ...[
                      const SizedBox(width: 2),
                      const PaisaNavChevron(),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PaisaTheme.manrope(
                    size: 11,
                    weight: FontWeight.w600,
                    color: PaisaColors.mutedCaption,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return PaisaCoinRise(
      duration: Duration(milliseconds: 340 + delayMs),
      offsetY: 8,
      child: onTap == null
          ? row
          : Semantics(
              button: true,
              label: '$title, ${formatInr(amount)}',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(12),
                  child: row,
                ),
              ),
            ),
    );
  }
}

class _TopStamp extends StatelessWidget {
  const _TopStamp();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: PaisaColors.primary,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'TOP',
        style: PaisaTheme.sora(
          size: 8,
          weight: FontWeight.w800,
          color: PaisaColors.inkOnAccent,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}

// ── Chrome + notes + empty ──────────────────────────────────────────────────

class _ReportsButton extends StatelessWidget {
  const _ReportsButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Reports',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(11, 7, 8, 7),
          decoration: BoxDecoration(
            color: PaisaColors.cardElevated,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: PaisaColors.primary.withOpacity(0.45),
              width: 1.5,
            ),
            boxShadow: PaisaColors.hardShadow(offset: 2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'REPORTS',
                style: PaisaTheme.label(
                  size: 10,
                  color: PaisaColors.primary,
                  letterSpacing: 1.6,
                ),
              ),
              const PaisaNavChevron(
                size: 17,
                color: PaisaColors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hairline note with a struck accent bar — no card, no chrome clutter.
class _StruckNote extends StatelessWidget {
  const _StruckNote({required this.accent, required this.child});

  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: accent, width: 2.5)),
      ),
      child: child,
    );
  }
}

class _InsightsEmptyHint extends StatelessWidget {
  const _InsightsEmptyHint({required this.store});

  final FinanceStore store;

  @override
  Widget build(BuildContext context) {
    final hasTransactions = store.transactions.isNotEmpty;
    final headline =
        hasTransactions ? 'No spending insights yet' : 'No transactions yet';
    final subtitle = hasTransactions
        ? 'Pull down to refresh, or go to Profile → Rescan SMS.'
        : 'Scan your SMS inbox to build spending insights from bank alerts.';

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 28, 8, 4),
      child: Column(
        children: [
          Container(width: 48, height: 2, color: PaisaColors.border),
          const SizedBox(height: 20),
          Text(
            headline,
            textAlign: TextAlign.center,
            style: PaisaTheme.sora(
              size: 17,
              weight: FontWeight.w800,
              color: PaisaColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: PaisaTheme.manrope(
              size: 12.5,
              weight: FontWeight.w600,
              color: PaisaColors.mutedCaption,
            ),
          ),
          if (!hasTransactions) ...[
            const SizedBox(height: 18),
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
