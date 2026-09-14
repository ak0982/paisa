import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/category_info.dart';
import '../providers/finance_store.dart';
import '../theme/paisa_colors.dart';
import '../theme/paisa_theme.dart';
import '../utils/formatters.dart';
import '../widgets/paisa_coin.dart';
import '../widgets/paisa_nav_chevron.dart';
import '../widgets/pulse_calendar_sheet.dart';
import '../widgets/pulse_ribbon_chart.dart';
import 'category_transactions_screen.dart';
import 'day_strip_screen.dart';
import 'reports_screen.dart';

/// Stats = period overview. One filter drives graph, coin, share, and merchants.
///
/// Layout: period chips → Pulse Ribbon → period Ledger Coin → category share →
/// top merchants → See All Moves (Reports Ledger, same range).
class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  StatsSpiralPeriod _spiralPeriod = StatsSpiralPeriod.oneMonth;
  DateTimeRange? _customRange;

  static final _dayFmt = DateFormat('d MMM yyyy');

  static const _chips = <(StatsSpiralPeriod, String, Key)>[
    (StatsSpiralPeriod.oneMonth, '1M', Key('spiral_filter_1m')),
    (StatsSpiralPeriod.sixMonths, '6M', Key('spiral_filter_6m')),
    (StatsSpiralPeriod.oneYear, '1Y', Key('spiral_filter_1y')),
    (StatsSpiralPeriod.allTime, 'ALL', Key('spiral_filter_all')),
    (StatsSpiralPeriod.custom, 'CUSTOM', Key('spiral_filter_custom')),
  ];

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final seed = _customRange ??
        DateTimeRange(
          start: DateTime(now.year, now.month - 1, now.day),
          end: DateTime(now.year, now.month, now.day),
        );
    final picked = await showPulseCalendarSheet(
      context,
      initialStart: seed.start,
      initialEnd: seed.end,
      initialMode: PulseCalendarMode.range,
    );
    if (!mounted || picked == null) return;
    setState(() {
      _customRange = DateTimeRange(
        start: picked.startDay,
        end: picked.endDay,
      );
      _spiralPeriod = StatsSpiralPeriod.custom;
    });
  }

  void _selectPeriod(StatsSpiralPeriod period) {
    if (period == StatsSpiralPeriod.custom) {
      _pickCustomRange();
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _spiralPeriod = period);
  }

  void _openReports(DateTimeRange range) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReportsScreen(initialRange: range),
      ),
    );
  }

  String _periodCoinLabel(DateTimeRange range) {
    switch (_spiralPeriod) {
      case StatsSpiralPeriod.oneMonth:
        return '1 Month';
      case StatsSpiralPeriod.sixMonths:
        return '6 Months';
      case StatsSpiralPeriod.oneYear:
        return '1 Year';
      case StatsSpiralPeriod.allTime:
        return 'All time';
      case StatsSpiralPeriod.custom:
        final start =
            DateTime(range.start.year, range.start.month, range.start.day);
        final end = DateTime(range.end.year, range.end.month, range.end.day);
        return '${_dayFmt.format(start)} – ${_dayFmt.format(end)}';
    }
  }

  String _rangeCaption(DateTimeRange range) {
    final start =
        DateTime(range.start.year, range.start.month, range.start.day);
    final end = DateTime(range.end.year, range.end.month, range.end.day);
    return '${_dayFmt.format(start)} – ${_dayFmt.format(end)}';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<FinanceStore>(
      builder: (context, store, _) {
        final spiralRange = store.statsSpiralRange(
          _spiralPeriod,
          custom: _customRange,
        );
        final spiralSeries = store.spendSeriesInRange(
          spiralRange.start,
          spiralRange.end,
        );
        final report = store.buildReport(spiralRange.start, spiralRange.end);

        final spending = report.categorySpending;
        final sorted = spending.entries.toList();
        final spent = report.spent;
        final income = report.income;
        final merchants = report.topMerchants.take(5).toList();
        final hasTransactions = store.transactions.isNotEmpty;
        final showEmpty = !store.isLoading && !hasTransactions;
        final periodLabel = _periodCoinLabel(spiralRange);

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
                      onTap: () => _openReports(spiralRange),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  key: const Key('spiral_filters'),
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final chip in _chips)
                      _PeriodFilterChip(
                        key: chip.$3,
                        label: chip.$2,
                        selected: _spiralPeriod == chip.$1,
                        onTap: () => _selectPeriod(chip.$1),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _rangeCaption(spiralRange),
                  style: PaisaTheme.manrope(
                    size: 11,
                    weight: FontWeight.w600,
                    color: PaisaColors.muted,
                  ),
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
                  const SizedBox(height: 16),
                  _LedgerCoinHero(
                    periodLabel: periodLabel,
                    spent: 0,
                    income: 0,
                    moves: 0,
                  ),
                  const SizedBox(height: 8),
                  _InsightsEmptyHint(store: store),
                ] else ...[
                  const SizedBox(height: 18),
                  _SpendChartSection(
                    range: spiralRange,
                    series: spiralSeries,
                  ),
                  const SizedBox(height: 22),
                  _LedgerCoinHero(
                    periodLabel: periodLabel,
                    spent: spent,
                    income: income,
                    moves: report.spendCount,
                  ),
                  const SizedBox(height: 22),
                  _CoinLegendRail(
                    dailyAverage: report.dailyAverage,
                    peakDaySpend: report.highestDaySpend,
                    peakDay: report.highestDay,
                    net: report.net,
                  ),
                  if (sorted.isNotEmpty && spent > 0) ...[
                    const SizedBox(height: 22),
                    _CategoryCompositionBar(
                      entries: sorted,
                      totalSpent: spent,
                      range: spiralRange,
                      periodLabel: periodLabel,
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
                    const SizedBox(height: 14),
                    _SeeAllMovesLink(
                      onTap: () => _openReports(spiralRange),
                    ),
                  ],
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Pulse Ribbon (X = time, Y = spend) ──────────────────────────────────────

class _SpendChartSection extends StatelessWidget {
  const _SpendChartSection({
    required this.range,
    required this.series,
  });

  final DateTimeRange range;
  final List<(DateTime, double)> series;

  /// Infer bucket span from consecutive series starts (daily / weekly / monthly).
  DateTime? _bucketEnd(DateTime start) {
    if (series.length < 2) {
      return DateTime(start.year, start.month, start.day);
    }
    final i = series.indexWhere((e) => e.$1 == start);
    if (i < 0) return DateTime(start.year, start.month, start.day);
    if (i < series.length - 1) {
      final next = series[i + 1].$1;
      return DateTime(next.year, next.month, next.day)
          .subtract(const Duration(days: 1));
    }
    final prevGap = series[i].$1.difference(series[i - 1].$1).inDays;
    final end = start.add(Duration(days: math.max(prevGap, 1) - 1));
    final rangeEnd = DateTime(range.end.year, range.end.month, range.end.day);
    return end.isAfter(rangeEnd) ? rangeEnd : end;
  }

  void _openBucket(BuildContext context, DateTime bucketStart, double spend) {
    if (spend <= 0) return;
    final day = DateTime(bucketStart.year, bucketStart.month, bucketStart.day);
    final end = _bucketEnd(day);
    if (end == null ||
        (end.year == day.year && end.month == day.month && end.day == day.day)) {
      DayStripScreen.open(context, day: day);
    } else {
      DayStripScreen.open(context, day: day, end: end);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PaisaCoinRise(
      duration: const Duration(milliseconds: 560),
      offsetY: 10,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionHeading(
            label: 'SPEND',
            trailing: 'PULSE RIBBON',
          ),
          const SizedBox(height: 4),
          Text(
            'X = time · Y = spend · ribbon thickness pulses with the range above',
            style: PaisaTheme.manrope(
              size: 11.5,
              weight: FontWeight.w600,
              color: PaisaColors.mutedCaption,
            ),
          ),
          const SizedBox(height: 16),
          PulseRibbonChart(
            series: series,
            onBucketTap: (start, spend) => _openBucket(context, start, spend),
          ),
        ],
      ),
    );
  }
}

class _PeriodFilterChip extends StatelessWidget {
  const _PeriodFilterChip({
    super.key,
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
      label: 'Period filter $label',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? PaisaColors.primary : PaisaColors.cardElevated,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? PaisaColors.inkOnAccent
                  : PaisaColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            style: PaisaTheme.label(
              size: 11,
              color: selected ? PaisaColors.inkOnAccent : PaisaColors.mutedCaption,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ),
    );
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

// ── Category share composition bar ──────────────────────────────────────────

/// Compact horizontal share strip under the coin — replaces the long category
/// ledger so Stats stays one composition, not a second Reports list.
class _CategoryCompositionBar extends StatelessWidget {
  const _CategoryCompositionBar({
    required this.entries,
    required this.totalSpent,
    required this.range,
    required this.periodLabel,
  });

  final List<MapEntry<SpendCategory, double>> entries;
  final double totalSpent;
  final DateTimeRange range;
  final String periodLabel;

  void _openCategory(BuildContext context, SpendCategory category) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CategoryTransactionsScreen(
          category: category,
          range: range,
          periodLabel: periodLabel,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final top = entries.take(6).toList();
    return PaisaCoinRise(
      duration: const Duration(milliseconds: 480),
      offsetY: 8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionHeading(label: 'SHARE'),
          const SizedBox(height: 8),
          Semantics(
            label: 'Category share of ledger spend',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 12,
                child: Row(
                  children: [
                    for (var i = 0; i < top.length; i++) ...[
                      if (i > 0) const SizedBox(width: 2),
                      Expanded(
                        flex: math.max(1, (top[i].value / totalSpent * 1000).round()),
                        child: GestureDetector(
                          onTap: () => _openCategory(context, top[i].key),
                          child: ColoredBox(
                            color: CategoryInfo.forCategory(top[i].key).iconColor,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              for (final e in top.take(4))
                GestureDetector(
                  onTap: () => _openCategory(context, e.key),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: CategoryInfo.forCategory(e.key).iconColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        CategoryInfo.forCategory(e.key).label,
                        style: PaisaTheme.manrope(
                          size: 11,
                          weight: FontWeight.w700,
                          color: PaisaColors.ink,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        formatSharePercent(e.value / totalSpent),
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
        ],
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
class _LedgerRow extends StatelessWidget {
  const _LedgerRow({
    required this.token,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.index,
    required this.isLast,
    this.onTap,
  });

  final Widget token;
  final String title;
  final String subtitle;
  final double amount;
  final int index;
  final bool isLast;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
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

/// Under Top Merchants — opens Period Folio Ledger for the selected Stats range.
class _SeeAllMovesLink extends StatelessWidget {
  const _SeeAllMovesLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'See all moves',
      child: InkWell(
        key: const Key('stats_see_all_moves'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'SEE ALL MOVES',
                style: PaisaTheme.label(
                  size: 11,
                  color: PaisaColors.primary,
                  letterSpacing: 1.8,
                ),
              ),
              const PaisaNavChevron(
                size: 18,
                color: PaisaColors.primary,
              ),
            ],
          ),
        ),
      ),
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
