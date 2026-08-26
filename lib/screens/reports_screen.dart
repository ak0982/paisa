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
import '../widgets/category_spend_chip.dart';
import '../widgets/grouped_transaction_list.dart';
import '../widgets/paisa_nav_chevron.dart';
import '../widgets/pulse_calendar_sheet.dart';
import '../widgets/transaction_sort_control.dart';
import 'category_transactions_screen.dart';
import 'filtered_transactions_screen.dart';

enum _RangePreset {
  thisMonth,
  lastMonth,
  last3Months,
  thisYear,
  lastYear,
  allTime,
  custom,
}

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  _RangePreset _preset = _RangePreset.thisMonth;
  DateTimeRange? _customRange;
  TransactionSort _txnSort = TransactionSort.defaultSort;

  static final _dayFmt = DateFormat('d MMM yyyy');

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
      case _RangePreset.thisYear:
        return DateTimeRange(
          start: DateTime(now.year, 1, 1),
          end: _endOfDay(now),
        );
      case _RangePreset.lastYear:
        return DateTimeRange(
          start: DateTime(now.year - 1, 1, 1),
          end: _endOfDay(DateTime(now.year - 1, 12, 31)),
        );
      case _RangePreset.allTime:
        final earliest = context.read<FinanceStore>().earliestTransactionDate;
        return DateTimeRange(
          start: earliest != null
              ? DateTime(earliest.year, earliest.month, earliest.day)
              : DateTime(now.year, now.month, 1),
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
      // Store local calendar days; [_resolveRange] expands end to inclusive EOD.
      _customRange = DateTimeRange(
        start: picked.startDay,
        end: picked.endDay,
      );
      _preset = _RangePreset.custom;
    });
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

            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _header()),
                SliverToBoxAdapter(child: _presetChips()),
                SliverToBoxAdapter(child: _rangeLabel(range)),
                if (report.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyReport(),
                  )
                else ...[
                  ..._reportSummarySlivers(report, range),
                  ..._transactionsSlivers(
                    store.transactionsInRange(range.start, range.end),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _reportSummarySlivers(RangeReport report, DateTimeRange range) {
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 0),
        sliver: SliverList(
          delegate: SliverChildListDelegate([
            _summaryHero(report),
            const SizedBox(height: 12),
            _secondaryStats(report),
            const SizedBox(height: 18),
            _insightBanner(report),
            _categorySection(report, range),
            _incomeSection(report, range),
            _merchantSection(report, range),
          ]),
        ),
      ),
    ];
  }

  String _periodLabelForRange(DateTimeRange range) {
    const labels = {
      _RangePreset.thisMonth: 'This month',
      _RangePreset.lastMonth: 'Last month',
      _RangePreset.last3Months: 'Last 3 months',
      _RangePreset.thisYear: 'This year',
      _RangePreset.lastYear: 'Last year',
      _RangePreset.allTime: 'All time',
    };
    if (_preset == _RangePreset.custom) {
      return '${_dayFmt.format(range.start)}  –  ${_dayFmt.format(range.end)}';
    }
    return labels[_preset] ??
        '${_dayFmt.format(range.start)}  –  ${_dayFmt.format(range.end)}';
  }

  List<Widget> _transactionsSlivers(List<Transaction> items) {
    final sections = buildTransactionSections(items, _txnSort);

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
          child: Row(
            children: [
              Text(
                'Transactions',
                style: PaisaTheme.sora(size: 14, weight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                items.length == 1 ? '1 item' : '${items.length} items',
                style: PaisaTheme.manrope(
                  size: 12,
                  weight: FontWeight.w600,
                  color: PaisaColors.mutedLight,
                ),
              ),
              const SizedBox(width: 10),
              TransactionSortControl(
                sort: _txnSort,
                showLabel: false,
                onChanged: (value) => setState(() => _txnSort = value),
              ),
            ],
          ),
        ),
      ),
      if (sections.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
            child: Text(
              'No transactions in this range.',
              style: PaisaTheme.manrope(
                size: 12.5,
                color: PaisaColors.mutedLight,
              ),
            ),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) =>
                  TransactionSectionCard(section: sections[index]),
              childCount: sections.length,
            ),
          ),
        ),
    ];
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
            'Reports',
            style: PaisaTheme.sora(
              size: 22,
              weight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _presetChips() {
    const labels = {
      _RangePreset.thisMonth: 'This month',
      _RangePreset.lastMonth: 'Last month',
      _RangePreset.last3Months: 'Last 3 months',
      _RangePreset.thisYear: 'This year',
      _RangePreset.lastYear: 'Last year',
      _RangePreset.allTime: 'All time',
      _RangePreset.custom: 'Custom',
    };

    return SizedBox(
      height: 42,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(
          children: labels.entries.map((e) {
            final active = _preset == e.key;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onTap: () {
                  if (e.key == _RangePreset.custom) {
                    _pickCustomRange();
                  } else {
                    setState(() => _preset = e.key);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: active ? PaisaColors.primary : PaisaColors.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: active ? PaisaColors.primary : PaisaColors.dividerAlt,
                    ),
                  ),
                  child: Row(
                    children: [
                      if (e.key == _RangePreset.custom) ...[
                        Icon(
                          Icons.calendar_today_rounded,
                          size: 13,
                          color: active
                              ? PaisaColors.inkOnAccent
                              : PaisaColors.mutedLight,
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        e.value,
                        style: PaisaTheme.manrope(
                          size: 12.5,
                          weight: FontWeight.w700,
                          color: active
                              ? PaisaColors.inkOnAccent
                              : PaisaColors.mutedLight,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _rangeLabel(DateTimeRange range) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 8),
      child: Row(
        children: [
          const Icon(Icons.event_rounded, size: 15, color: PaisaColors.mutedLight),
          const SizedBox(width: 6),
          Text(
            '${_dayFmt.format(range.start)}  –  ${_dayFmt.format(range.end)}',
            style: PaisaTheme.manrope(
              size: 12.5,
              weight: FontWeight.w600,
              color: PaisaColors.mutedLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryHero(RangeReport report) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: PaisaColors.primary,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: PaisaColors.inkOnAccent, width: 2.5),
        boxShadow: PaisaColors.hardShadow(offset: 5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'NET FOR THIS RANGE',
            style: PaisaTheme.manrope(
              size: 10.5,
              weight: FontWeight.w700,
              color: PaisaColors.inkOnAccent,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            report.net >= 0
                ? '+${formatInr(report.net)}'
                : '−${formatInr(report.net.abs())}',
            style: PaisaTheme.sora(
              size: 34,
              weight: FontWeight.w800,
              color: PaisaColors.inkOnAccent,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _heroStat('Spent', report.spent),
              Container(
                width: 1,
                height: 34,
                color: PaisaColors.inkOnAccent.withOpacity(0.22),
              ),
              _heroStat('Earned', report.income),
              Container(
                width: 1,
                height: 34,
                color: PaisaColors.inkOnAccent.withOpacity(0.22),
              ),
              _heroStat('Saved', report.saved),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroStat(String label, double value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text(
              label.toUpperCase(),
              style: PaisaTheme.manrope(
                size: 10,
                weight: FontWeight.w700,
                color: PaisaColors.inkOnAccent.withOpacity(0.75),
                letterSpacing: 0.8,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text(
              formatInr(value),
              style: PaisaTheme.sora(
                size: 16,
                weight: FontWeight.w800,
                color: PaisaColors.inkOnAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _secondaryStats(RangeReport report) {
    return Row(
      children: [
        _StatCard(
          label: 'Transactions',
          value: '${report.transactionCount}',
        ),
        const SizedBox(width: 11),
        _StatCard(
          label: 'Daily average',
          value: formatInr(report.dailyAverage),
        ),
        const SizedBox(width: 11),
        _StatCard(
          label: 'Savings rate',
          value: '${(report.savingsRate * 100).round()}%',
        ),
      ],
    );
  }

  Widget _insightBanner(RangeReport report) {
    final topCat = report.topCategory;
    if (topCat == null) return const SizedBox.shrink();
    final info = CategoryInfo.forCategory(topCat);
    final topAmount = report.categorySpending[topCat] ?? 0;
    final share = report.spent > 0 ? (topAmount / report.spent) : 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: PaisaColors.cardElevated,
          border: Border.all(color: PaisaColors.border),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: info.tintBg,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(info.emoji, style: const TextStyle(fontSize: 16)),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: PaisaTheme.manrope(
                    size: 12.5,
                    color: PaisaColors.ink,
                  ),
                  children: [
                    const TextSpan(text: 'Most of your spending went to '),
                    TextSpan(
                      text: info.label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: PaisaColors.primary,
                      ),
                    ),
                    TextSpan(
                      text:
                          ' — ${formatInr(topAmount)} (${(share * 100).round()}% of spend).',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categorySection(RangeReport report, DateTimeRange range) {
    final entries = report.categorySpending.entries.toList();
    if (entries.isEmpty) return const SizedBox.shrink();
    final periodLabel = _periodLabelForRange(range);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        Text(
          'Where money went',
          style: PaisaTheme.sora(size: 14, weight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        CategorySpendStickerGrid(
          tiles: [
            for (var i = 0; i < entries.length; i++)
              CategorySpendTile(
                category: entries[i].key,
                amount: entries[i].value,
                share: report.spent > 0
                    ? (entries[i].value / report.spent).clamp(0.0, 1.0)
                    : 0,
                emphasize: i == 0,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CategoryTransactionsScreen(
                      category: entries[i].key,
                      range: range,
                      periodLabel: periodLabel,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _incomeSection(RangeReport report, DateTimeRange range) {
    if (report.incomeSources.isEmpty) return const SizedBox.shrink();
    final periodLabel = _periodLabelForRange(range);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        Text(
          'Where money came from',
          style: PaisaTheme.sora(size: 14, weight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: PaisaColors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: PaisaColors.dividerAlt),
          ),
          child: Column(
            children: [
              for (var i = 0; i < report.incomeSources.length; i++) ...[
                Semantics(
                  button: true,
                  label:
                      '${report.incomeSources[i].$1}, ${formatInr(report.incomeSources[i].$2)}',
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              FilteredTransactionsScreen.incomeSource(
                            source: report.incomeSources[i].$1,
                            range: range,
                            periodLabel: periodLabel,
                          ),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: PaisaColors.cardElevated,
                                borderRadius: BorderRadius.circular(9),
                              ),
                              alignment: Alignment.center,
                              child: const Text(
                                '💰',
                                style: TextStyle(fontSize: 14),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                report.incomeSources[i].$1,
                                style: PaisaTheme.manrope(
                                  size: 13.5,
                                  weight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '+${formatInr(report.incomeSources[i].$2)}',
                              style: PaisaTheme.sora(
                                size: 14,
                                weight: FontWeight.w700,
                                color: PaisaColors.credit,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const PaisaNavChevron(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (i < report.incomeSources.length - 1)
                  const Divider(height: 1, color: PaisaColors.divider),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _merchantSection(RangeReport report, DateTimeRange range) {
    if (report.topMerchants.isEmpty) return const SizedBox.shrink();
    final periodLabel = _periodLabelForRange(range);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        Text(
          'Top merchants',
          style: PaisaTheme.sora(size: 14, weight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: PaisaColors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: PaisaColors.dividerAlt),
          ),
          child: Column(
            children: [
              for (var i = 0; i < report.topMerchants.length; i++) ...[
                Semantics(
                  button: true,
                  label:
                      '${report.topMerchants[i].$1}, ${formatInr(report.topMerchants[i].$3)}',
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => FilteredTransactionsScreen.merchant(
                            merchant: report.topMerchants[i].$1,
                            range: range,
                            periodLabel: periodLabel,
                          ),
                        ),
                      ),
                      child: _MerchantRow(
                        rank: i + 1,
                        name: report.topMerchants[i].$1,
                        sub: report.topMerchants[i].$2,
                        amount: report.topMerchants[i].$3,
                      ),
                    ),
                  ),
                ),
                if (i < report.topMerchants.length - 1)
                  const Divider(height: 1, color: PaisaColors.divider),
              ],
            ],
          ),
        ),
      ],
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
        padding: const EdgeInsets.fromLTRB(13, 13, 13, 13),
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
                size: 10.5,
                color: PaisaColors.mutedCaption,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: PaisaTheme.sora(size: 16, weight: FontWeight.w800),
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
                  style: PaisaTheme.manrope(size: 13.5, weight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
          const SizedBox(width: 4),
          const PaisaNavChevron(),
        ],
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
              'Try a different month, year, or custom date range.',
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
