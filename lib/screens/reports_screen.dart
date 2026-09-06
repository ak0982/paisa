import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/category_info.dart';
import '../models/range_report.dart';
import '../models/transaction.dart';
import '../models/transaction_sort.dart';
import '../providers/finance_store.dart';
import '../theme/paisa_colors.dart';
import '../theme/paisa_theme.dart';
import '../utils/formatters.dart';
import '../widgets/grouped_transaction_list.dart';
import '../widgets/paisa_coin.dart';
import '../widgets/paisa_nav_chevron.dart';
import '../widgets/paisa_progress_bar.dart';
import '../widgets/pulse_calendar_sheet.dart';
import '../widgets/transaction_sort_control.dart';
import 'category_transactions_screen.dart';
import 'day_strip_screen.dart';
import 'filtered_transactions_screen.dart';

enum _RangePreset {
  thisMonth,
  lastMonth,
  last3Months,
  custom,
}

enum _FolioTab { summary, breakdown, ledger }

/// Ledger list direction filter — same All / Out / In voice as Day Strip.
enum _LedgerFlowFilter { all, out, inn }

/// Period Folio — range chips + sticky Summary / Breakdown / Ledger tabs.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, this.initialRange});

  /// When set, opens Reports on that inclusive calendar range (Custom preset)
  /// and defaults to the Ledger tab.
  final DateTimeRange? initialRange;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late _RangePreset _preset;
  late _FolioTab _tab;
  DateTimeRange? _customRange;
  TransactionSort _txnSort = TransactionSort.defaultSort;
  _LedgerFlowFilter _txnFlow = _LedgerFlowFilter.all;

  static final _dayFmt = DateFormat('d MMM yyyy');

  @override
  void initState() {
    super.initState();
    final seed = widget.initialRange;
    if (seed != null) {
      _customRange = DateTimeRange(
        start: DateTime(seed.start.year, seed.start.month, seed.start.day),
        end: DateTime(seed.end.year, seed.end.month, seed.end.day),
      );
      _preset = _RangePreset.custom;
      _tab = _FolioTab.ledger;
    } else {
      _preset = _RangePreset.thisMonth;
      _tab = _FolioTab.summary;
    }
  }

  DateTimeRange _resolveRange() {
    final now = DateTime.now();
    switch (_preset) {
      case _RangePreset.thisMonth:
        return DateTimeRange(
          start: DateTime(now.year, now.month, 1),
          end: _endOfDay(now),
        );
      case _RangePreset.lastMonth:
        final firstOfThis = DateTime(now.year, now.month, 1);
        final lastMonthEnd = firstOfThis.subtract(const Duration(days: 1));
        return DateTimeRange(
          start: DateTime(lastMonthEnd.year, lastMonthEnd.month, 1),
          end: _endOfDay(lastMonthEnd),
        );
      case _RangePreset.last3Months:
        return DateTimeRange(
          start: DateTime(now.year, now.month - 2, 1),
          end: _endOfDay(now),
        );
      case _RangePreset.custom:
        final range = _customRange ??
            DateTimeRange(
              start: DateTime(now.year, now.month, 1),
              end: _endOfDay(now),
            );
        return DateTimeRange(
          start: DateTime(range.start.year, range.start.month, range.start.day),
          end: _endOfDay(range.end),
        );
    }
  }

  static DateTime _endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final seed = _customRange ??
        DateTimeRange(
          start: DateTime(now.year, now.month, 1),
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
      _preset = _RangePreset.custom;
    });
  }

  String _periodLabelForRange(DateTimeRange range) {
    const labels = {
      _RangePreset.thisMonth: 'This month',
      _RangePreset.lastMonth: 'Last month',
      _RangePreset.last3Months: 'Last 3 months',
    };
    if (_preset == _RangePreset.custom) {
      return '${_dayFmt.format(range.start)}  –  ${_dayFmt.format(range.end)}';
    }
    return labels[_preset] ??
        '${_dayFmt.format(range.start)}  –  ${_dayFmt.format(range.end)}';
  }

  String? _insightLine(RangeReport report, FinanceStore store) {
    if (report.isEmpty || report.spent <= 0) return null;
    if (_preset != _RangePreset.thisMonth) return null;

    final now = DateTime.now();
    final firstOfThis = DateTime(now.year, now.month, 1);
    final lastMonthEnd = firstOfThis.subtract(const Duration(days: 1));
    final prev = store.buildReport(
      DateTime(lastMonthEnd.year, lastMonthEnd.month, 1),
      _endOfDay(lastMonthEnd),
    );
    if (prev.spent <= 0) return null;

    final deltaPct =
        (((report.spent - prev.spent) / prev.spent) * 100).round();
    final top = report.topCategory;
    final lead = top == null ? null : CategoryInfo.forCategory(top).label;

    if (deltaPct < 0) {
      final base = 'Spending ${deltaPct.abs()}% below last month';
      return lead == null ? '$base.' : '$base — $lead still leads.';
    }
    if (deltaPct > 0) {
      final base = 'Spending $deltaPct% above last month';
      return lead == null ? '$base.' : '$base — $lead leads.';
    }
    return lead == null
        ? 'Spend flat vs last month.'
        : 'Spend flat vs last month — $lead leads.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PaisaColors.surface,
      body: SafeArea(
        child: Consumer<FinanceStore>(
          builder: (context, store, _) {
            final range = _resolveRange();
            final report = store.buildReport(range.start, range.end);
            final txns = store.transactionsInRange(range.start, range.end);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(),
                _presetChips(),
                _rangeCaption(range),
                _folioTabs(),
                Expanded(
                  child: report.isEmpty && _tab != _FolioTab.ledger
                      ? _EmptyReport()
                      : switch (_tab) {
                          _FolioTab.summary => _SummaryTab(
                              report: report,
                              periodLabel: _periodLabelForRange(range),
                              insight: _insightLine(report, store),
                            ),
                          _FolioTab.breakdown => _BreakdownTab(
                              report: report,
                              range: range,
                              periodLabel: _periodLabelForRange(range),
                            ),
                          _FolioTab.ledger => _LedgerTab(
                              transactions: txns,
                              sort: _txnSort,
                              flow: _txnFlow,
                              onSortChanged: (v) =>
                                  setState(() => _txnSort = v),
                              onFlowChanged: (v) =>
                                  setState(() => _txnFlow = v),
                            ),
                        },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 22, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded, color: PaisaColors.ink),
          ),
          Text(
            'REPORTS',
            style: PaisaTheme.label(
              size: 16,
              color: PaisaColors.ink,
              letterSpacing: 2.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _presetChips() {
    const items = <(_RangePreset, String)>[
      (_RangePreset.thisMonth, 'This month'),
      (_RangePreset.lastMonth, 'Last month'),
      (_RangePreset.last3Months, '3M'),
      (_RangePreset.custom, 'Custom'),
    ];

    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (preset, label) = items[index];
          final active = _preset == preset;
          return Semantics(
            button: true,
            selected: active,
            label: 'Range $label',
            child: GestureDetector(
              onTap: () {
                if (preset == _RangePreset.custom) {
                  _pickCustomRange();
                } else {
                  setState(() => _preset = preset);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active ? PaisaColors.primary : PaisaColors.cardElevated,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: active
                        ? PaisaColors.inkOnAccent
                        : PaisaColors.border,
                    width: active ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (preset == _RangePreset.custom) ...[
                      Icon(
                        Icons.calendar_today_rounded,
                        size: 12,
                        color: active
                            ? PaisaColors.inkOnAccent
                            : PaisaColors.mutedCaption,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      label,
                      style: PaisaTheme.label(
                        size: 11,
                        color: active
                            ? PaisaColors.inkOnAccent
                            : PaisaColors.mutedCaption,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _rangeCaption(DateTimeRange range) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
      child: Text(
        '${_dayFmt.format(range.start)}  –  ${_dayFmt.format(range.end)}',
        style: PaisaTheme.manrope(
          size: 12,
          weight: FontWeight.w600,
          color: PaisaColors.mutedLight,
        ),
      ),
    );
  }

  Widget _folioTabs() {
    const tabs = <(_FolioTab, String)>[
      (_FolioTab.summary, 'SUMMARY'),
      (_FolioTab.breakdown, 'BREAKDOWN'),
      (_FolioTab.ledger, 'LEDGER'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: PaisaColors.border),
          ),
        ),
        child: Row(
          children: [
            for (final (tab, label) in tabs)
              Expanded(
                child: InkWell(
                  key: ValueKey<String>('folio-tab-$label'),
                  onTap: () => setState(() => _tab = tab),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      children: [
                        Text(
                          label,
                          textAlign: TextAlign.center,
                          style: PaisaTheme.label(
                            size: 11,
                            color: _tab == tab
                                ? PaisaColors.primary
                                : PaisaColors.mutedCaption,
                            letterSpacing: 1.6,
                          ),
                        ),
                        const SizedBox(height: 8),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          height: 2,
                          width: _tab == tab ? 56 : 0,
                          color: PaisaColors.primary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Summary: Ledger Coin + ruled legend ─────────────────────────────────────

class _SummaryTab extends StatelessWidget {
  const _SummaryTab({
    required this.report,
    required this.periodLabel,
    this.insight,
  });

  final RangeReport report;
  final String periodLabel;
  final String? insight;

  @override
  Widget build(BuildContext context) {
    if (report.isEmpty) return _EmptyReport();

    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 28),
      children: [
        _LedgerCoinHero(
          periodLabel: periodLabel,
          spent: report.spent,
          income: report.income,
          moves: report.transactionCount,
        ),
        const SizedBox(height: 22),
        _CoinLegendRail(
          dailyAverage: report.dailyAverage,
          peakDaySpend: report.highestDaySpend,
          peakDay: report.highestDay,
          net: report.net,
          saved: report.saved,
        ),
        if (insight != null && insight!.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            insight!,
            style: PaisaTheme.manrope(
              size: 12.5,
              weight: FontWeight.w600,
              color: PaisaColors.mutedLight,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}

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

/// Ruled legend under the coin — daily / peak / net / saved.
class _CoinLegendRail extends StatelessWidget {
  const _CoinLegendRail({
    required this.dailyAverage,
    required this.peakDaySpend,
    required this.peakDay,
    required this.net,
    required this.saved,
  });

  final double dailyAverage;
  final double peakDaySpend;
  final DateTime? peakDay;
  final double net;
  final double saved;

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
        child: Column(
          children: [
            Row(
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
              ],
            ),
            const SizedBox(height: 12),
            Container(height: 1, color: PaisaColors.border),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _CoinLegend(
                    label: 'NET',
                    value: formatAmount(net, isCredit: net >= 0),
                    valueColor:
                        net >= 0 ? PaisaColors.primary : PaisaColors.ink,
                    caption: 'in − out',
                  ),
                ),
                const _LegendRule(),
                Expanded(
                  child: _CoinLegend(
                    label: 'SAVED',
                    value: formatInr(saved),
                    caption: 'income − spent',
                  ),
                ),
              ],
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
        Text(
          caption,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: PaisaTheme.manrope(
            size: 10.5,
            weight: FontWeight.w600,
            color: PaisaColors.mutedCaption,
          ),
        ),
      ],
    );

    if (onTap == null) return column;
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

// ── Breakdown: ruled categories / income / merchants ────────────────────────

class _BreakdownTab extends StatelessWidget {
  const _BreakdownTab({
    required this.report,
    required this.range,
    required this.periodLabel,
  });

  final RangeReport report;
  final DateTimeRange range;
  final String periodLabel;

  @override
  Widget build(BuildContext context) {
    if (report.isEmpty) return _EmptyReport();

    final categories = report.categorySpending.entries.toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 28),
      children: [
        if (categories.isNotEmpty) ...[
          const _SectionHeading(label: 'CATEGORIES'),
          const SizedBox(height: 4),
          for (var i = 0; i < categories.length; i++)
            _CategorySpendRow(
              category: categories[i].key,
              amount: categories[i].value,
              share: report.spent > 0
                  ? (categories[i].value / report.spent).clamp(0.0, 1.0)
                  : 0,
              isLast: i == categories.length - 1,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CategoryTransactionsScreen(
                    category: categories[i].key,
                    range: range,
                    periodLabel: periodLabel,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 22),
        ],
        if (report.incomeSources.isNotEmpty) ...[
          const _SectionHeading(label: 'INCOME SOURCES'),
          const SizedBox(height: 4),
          for (var i = 0; i < report.incomeSources.length; i++)
            _RuledNavRow(
              leading: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: i == 0
                      ? PaisaColors.primary
                      : PaisaColors.credit.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              title: report.incomeSources[i].$1,
              trailing: '+${formatInr(report.incomeSources[i].$2)}',
              trailingColor: PaisaColors.credit,
              isLast: i == report.incomeSources.length - 1,
              semanticLabel:
                  '${report.incomeSources[i].$1}, ${formatInr(report.incomeSources[i].$2)}',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => FilteredTransactionsScreen.incomeSource(
                    source: report.incomeSources[i].$1,
                    range: range,
                    periodLabel: periodLabel,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 22),
        ],
        if (report.topMerchants.isNotEmpty) ...[
          const _SectionHeading(label: 'MERCHANTS'),
          const SizedBox(height: 4),
          for (var i = 0; i < report.topMerchants.length; i++)
            _RuledNavRow(
              leading: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: PaisaColors.cardElevated,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: PaisaColors.border),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${i + 1}',
                  style: PaisaTheme.sora(
                    size: 11,
                    weight: FontWeight.w700,
                    color: PaisaColors.mutedCaption,
                  ),
                ),
              ),
              title: report.topMerchants[i].$1,
              subtitle: report.topMerchants[i].$2,
              trailing: formatInr(report.topMerchants[i].$3),
              isLast: i == report.topMerchants.length - 1,
              semanticLabel:
                  '${report.topMerchants[i].$1}, ${formatInr(report.topMerchants[i].$3)}',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => FilteredTransactionsScreen.merchant(
                    merchant: report.topMerchants[i].$1,
                    range: range,
                    periodLabel: periodLabel,
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _CategorySpendRow extends StatelessWidget {
  const _CategorySpendRow({
    required this.category,
    required this.amount,
    required this.share,
    required this.isLast,
    required this.onTap,
  });

  final SpendCategory category;
  final double amount;
  final double share;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final info = CategoryInfo.forCategory(category);
    final pct = formatSharePercent(share);

    return Semantics(
      button: true,
      label: '${info.label}, $pct, ${formatInr(amount)}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: isLast
                    ? BorderSide.none
                    : const BorderSide(color: PaisaColors.border),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: info.iconColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              info.label,
                              style: PaisaTheme.manrope(
                                size: 13.5,
                                weight: FontWeight.w700,
                                color: PaisaColors.ink,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (pct.isNotEmpty)
                            Text(
                              pct,
                              style: PaisaTheme.manrope(
                                size: 11.5,
                                weight: FontWeight.w700,
                                color: PaisaColors.mutedCaption,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      PaisaProgressBar(
                        progress: share,
                        color: PaisaColors.primary,
                        height: 5,
                        trackColor: PaisaColors.cardElevated,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  formatInr(amount),
                  style: PaisaTheme.sora(
                    size: 13.5,
                    weight: FontWeight.w700,
                    color: PaisaColors.ink,
                  ),
                ),
                const SizedBox(width: 2),
                const PaisaNavChevron(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RuledNavRow extends StatelessWidget {
  const _RuledNavRow({
    required this.leading,
    required this.title,
    required this.trailing,
    required this.isLast,
    required this.onTap,
    required this.semanticLabel,
    this.subtitle,
    this.trailingColor,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final String trailing;
  final Color? trailingColor;
  final bool isLast;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: isLast
                    ? BorderSide.none
                    : const BorderSide(color: PaisaColors.border),
              ),
            ),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: PaisaTheme.manrope(
                          size: 13.5,
                          weight: FontWeight.w600,
                          color: PaisaColors.ink,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: PaisaTheme.manrope(
                            size: 11,
                            color: PaisaColors.mutedCaption,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  trailing,
                  style: PaisaTheme.sora(
                    size: 14,
                    weight: FontWeight.w700,
                    color: trailingColor ?? PaisaColors.ink,
                  ),
                ),
                const SizedBox(width: 2),
                const PaisaNavChevron(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: PaisaTheme.label(
        size: 10,
        color: PaisaColors.muted,
        letterSpacing: 2.2,
      ),
    );
  }
}

// ── Ledger: full sorted / day-grouped list ──────────────────────────────────

class _LedgerTab extends StatelessWidget {
  const _LedgerTab({
    required this.transactions,
    required this.sort,
    required this.flow,
    required this.onSortChanged,
    required this.onFlowChanged,
  });

  final List<Transaction> transactions;
  final TransactionSort sort;
  final _LedgerFlowFilter flow;
  final ValueChanged<TransactionSort> onSortChanged;
  final ValueChanged<_LedgerFlowFilter> onFlowChanged;

  List<Transaction> get _filtered {
    return switch (flow) {
      _LedgerFlowFilter.all => transactions,
      _LedgerFlowFilter.out =>
        transactions.where((t) => !t.isCredit).toList(),
      _LedgerFlowFilter.inn =>
        transactions.where((t) => t.isCredit).toList(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 4),
          child: Row(
            children: [
              Text(
                filtered.length == 1
                    ? '1 item'
                    : '${filtered.length} items',
                style: PaisaTheme.manrope(
                  size: 12,
                  weight: FontWeight.w600,
                  color: PaisaColors.mutedLight,
                ),
              ),
              const Spacer(),
              _LedgerFlowChip(
                label: 'All',
                active: flow == _LedgerFlowFilter.all,
                onTap: () => onFlowChanged(_LedgerFlowFilter.all),
              ),
              const SizedBox(width: 6),
              _LedgerFlowChip(
                label: 'Out',
                active: flow == _LedgerFlowFilter.out,
                onTap: () => onFlowChanged(_LedgerFlowFilter.out),
              ),
              const SizedBox(width: 6),
              _LedgerFlowChip(
                label: 'In',
                active: flow == _LedgerFlowFilter.inn,
                onTap: () => onFlowChanged(_LedgerFlowFilter.inn),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: TransactionSortControl(
                      sort: sort,
                      onChanged: onSortChanged,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: GroupedTransactionList(
            transactions: filtered,
            sort: sort,
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
            emptyTitle: flow == _LedgerFlowFilter.all
                ? 'No transactions in this range'
                : flow == _LedgerFlowFilter.out
                    ? 'No outgoing transactions'
                    : 'No incoming transactions',
            emptySubtitle: flow == _LedgerFlowFilter.all
                ? 'Try a different month or custom date range.'
                : 'Try All, or pick another period.',
          ),
        ),
      ],
    );
  }
}

class _LedgerFlowChip extends StatelessWidget {
  const _LedgerFlowChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: ValueKey<String>('ledger-flow-$label'),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? PaisaColors.primary : PaisaColors.cardElevated,
          border: Border.all(
            color: active ? PaisaColors.primary : PaisaColors.border,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(10),
          boxShadow: active ? PaisaColors.hardShadow(offset: 2) : null,
        ),
        child: Text(
          label.toUpperCase(),
          style: PaisaTheme.manrope(
            size: 11,
            weight: FontWeight.w700,
            color: active ? PaisaColors.inkOnAccent : PaisaColors.mutedCaption,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

class _EmptyReport extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: PaisaColors.dividerAlt,
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.insights_rounded,
                size: 30,
                color: PaisaColors.mutedLight,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No transactions in this range',
              style: PaisaTheme.sora(size: 15, weight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Try a different month or custom date range.',
              textAlign: TextAlign.center,
              style: PaisaTheme.manrope(
                size: 12.5,
                color: PaisaColors.mutedLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
