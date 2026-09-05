import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/transaction.dart';
import '../models/transaction_sort.dart';
import '../providers/app_settings.dart';
import '../providers/finance_store.dart';
import '../theme/paisa_colors.dart';
import '../theme/paisa_theme.dart';
import '../utils/formatters.dart';
import '../widgets/mint_transaction_sheet.dart';
import '../widgets/neo_surface.dart';
import '../widgets/paisa_coin.dart';
import '../widgets/paisa_nav_chevron.dart';
import '../widgets/pulse_calendar_sheet.dart';
import '../widgets/sms_coin_slab.dart';
import '../widgets/transaction_sort_control.dart';

/// OUT arc share of the Paisa Coin gauge ring (`out / (out + income)`).
/// Returns `0` when there is no flow so the ring stays idle.
@visibleForTesting
double dayStripOutShare(double out, double income) =>
    paisaCoinOutShare(out, income);

enum _StripFlowFilter { all, out, inn }

/// Paisa Coin — the day (or range) minted as a single circular ledger.
///
/// The hero is a struck coin: milled rim, a split gauge ring where OUT is
/// white and IN is lime, a recessed field carrying the exact OUT amount, and
/// embossed legends (day numeral on top, PAISA wordmark below). Transactions
/// below are stamped rows, each with its own miniature coin token whose ring
/// fills with the transaction's share of the day. Internal moves get a dashed
/// token + MOVE badge and stay out of OUT/IN KPIs.
class DayStripScreen extends StatefulWidget {
  const DayStripScreen({
    super.key,
    this.initialDay,
    this.initialEnd,
    this.openCalendarOnLaunch = false,
  });

  final DateTime? initialDay;
  final DateTime? initialEnd;
  final bool openCalendarOnLaunch;

  static Future<void> open(
    BuildContext context, {
    DateTime? day,
    DateTime? end,
    bool openCalendar = false,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DayStripScreen(
          initialDay: day,
          initialEnd: end,
          openCalendarOnLaunch: openCalendar,
        ),
      ),
    );
  }

  @override
  State<DayStripScreen> createState() => _DayStripScreenState();
}

class _DayStripScreenState extends State<DayStripScreen> {
  late DateTime _start;
  DateTime? _end;
  TransactionSort _sort = TransactionSort.dateAsc;
  _StripFlowFilter _flow = _StripFlowFilter.all;

  bool get _isRange {
    if (_end == null) return false;
    return !_sameDay(_start, _end!);
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  void initState() {
    super.initState();
    final seed = widget.initialDay ?? DateTime.now();
    _start = DateTime(seed.year, seed.month, seed.day);
    if (widget.initialEnd != null) {
      final e = widget.initialEnd!;
      _end = DateTime(e.year, e.month, e.day);
      if (_end!.isBefore(_start)) {
        final tmp = _start;
        _start = _end!;
        _end = tmp;
      }
    }
    if (widget.openCalendarOnLaunch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openCalendar();
      });
    }
  }

  void _shiftDay(int delta) {
    if (_isRange) return;
    HapticFeedback.selectionClick();
    setState(() {
      _start = _start.add(Duration(days: delta));
    });
  }

  Future<void> _openCalendar() async {
    final result = await showPulseCalendarSheet(
      context,
      initialStart: _start,
      initialEnd: _end ?? _start,
      initialMode:
          _isRange ? PulseCalendarMode.range : PulseCalendarMode.day,
    );
    if (!mounted || result == null) return;
    setState(() {
      _start = result.startDay;
      _end = result.isRange ? result.endDay : null;
    });
  }

  List<Transaction> _applyFlow(List<Transaction> items) {
    return switch (_flow) {
      _StripFlowFilter.all => items,
      _StripFlowFilter.out => items.where((t) => !t.isCredit).toList(),
      _StripFlowFilter.inn => items.where((t) => t.isCredit).toList(),
    };
  }

  void _showTxnSheet(BuildContext context, Transaction t, bool isMove) {
    showTransactionCoinSlab(context, t, isMove: isMove);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<FinanceStore>(
      builder: (context, store, _) {
        final endInclusive = _end ?? _start;
        final raw = _isRange
            ? store.transactionsForDateRange(_start, endInclusive)
            : store.transactionsForDay(_start);
        final out = _isRange
            ? store.rangeSpend(_start, endInclusive)
            : store.daySpend(_start);
        final income = _isRange
            ? store.rangeIncome(_start, endInclusive)
            : store.dayIncome(_start);
        final net = _isRange
            ? store.rangeNet(_start, endInclusive)
            : store.dayNet(_start);
        final moveIds = _isRange
            ? store.rangeSelfTransferLegIds(_start, endInclusive)
            : store.daySelfTransferLegIds(_start);

        final filtered = _applyFlow(raw);
        final items = sortTransactions(filtered, _sort);
        final maxAmt = items.isEmpty
            ? 1.0
            : items
                .map((t) => t.amount)
                .reduce(math.max)
                .clamp(1.0, double.infinity);

        return Scaffold(
          backgroundColor: PaisaColors.surface,
          body: SafeArea(
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _CoinChrome(
                      isRange: _isRange,
                      onBack: () => Navigator.of(context).maybePop(),
                      onCalendar: _openCalendar,
                      onPrev: () => _shiftDay(-1),
                      onNext: () => _shiftDay(1),
                    ),
                    Expanded(
                      child: CustomScrollView(
                        physics: const BouncingScrollPhysics(),
                        slivers: [
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
                              child: _PaisaCoinHero(
                                start: _start,
                                end: endInclusive,
                                isRange: _isRange,
                                out: out,
                                income: income,
                                onDateTap: _openCalendar,
                                onSwipeDay: _isRange ? null : _shiftDay,
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
                              child: _CoinFilters(
                                flow: _flow,
                                sort: _sort,
                                onFlow: (f) => setState(() => _flow = f),
                                onSort: (s) => setState(() => _sort = s),
                              ),
                            ),
                          ),
                          if (items.isEmpty)
                            SliverToBoxAdapter(
                              child: _EmptyDay(
                                day: _start,
                                canMint: !_isRange,
                              ),
                            )
                          else
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(18, 4, 18, 88),
                              sliver: SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (context, i) {
                                    final t = items[i];
                                    final isMove = t.isCreditCardBillPayment ||
                                        t.isCreditCardPaymentReceived ||
                                        moveIds.contains(t.id);
                                    return _CoinRow(
                                      key: ValueKey(t.id),
                                      transaction: t,
                                      isMove: isMove,
                                      intensity: (t.amount / maxAmt)
                                          .clamp(0.08, 1.0),
                                      showDate: _isRange,
                                      index: i,
                                      isLast: i == items.length - 1,
                                      onTap: () =>
                                          _showTxnSheet(context, t, isMove),
                                    );
                                  },
                                  childCount: items.length,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _NetCaption(net: net),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

String dayStripMerchantLabel(String merchant, bool mask) =>
    maskedMerchantLabel(merchant, mask);

/// Uppercase coin legend date, e.g. `FRI 15 AUG`.
String formatDayStripHeader(DateTime day) {
  const weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
  const months = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];
  return '${weekdays[day.weekday - 1]} ${day.day} ${months[day.month - 1]}';
}

/// Inclusive range header, e.g. `12–15 AUG` or `28 JUL – 2 AUG`.
String formatDayStripRangeHeader(DateTime start, DateTime end) {
  const months = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];
  var a = DateTime(start.year, start.month, start.day);
  var b = DateTime(end.year, end.month, end.day);
  if (b.isBefore(a)) {
    final tmp = a;
    a = b;
    b = tmp;
  }
  if (a.year == b.year && a.month == b.month) {
    return '${a.day}–${b.day} ${months[a.month - 1]}';
  }
  if (a.year == b.year) {
    return '${a.day} ${months[a.month - 1]} – ${b.day} ${months[b.month - 1]}';
  }
  return '${a.day} ${months[a.month - 1]} ${a.year} – ${b.day} ${months[b.month - 1]} ${b.year}';
}

String _monthShort(DateTime day) {
  const months = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];
  return months[day.month - 1];
}

// ── Chrome ──────────────────────────────────────────────────────────────────

class _CoinChrome extends StatelessWidget {
  const _CoinChrome({
    required this.isRange,
    required this.onBack,
    required this.onCalendar,
    required this.onPrev,
    required this.onNext,
  });

  final bool isRange;
  final VoidCallback onBack;
  final VoidCallback onCalendar;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 10, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: PaisaColors.ink,
            ),
          ),
          const PaisaCoinWordmark(suffix: 'COIN'),
          const Spacer(),
          PaisaChromeIconButton(
            tooltip: 'Pulse Calendar',
            onTap: onCalendar,
            icon: Icons.calendar_month_rounded,
            accent: true,
          ),
          if (!isRange) ...[
            const SizedBox(width: 6),
            PaisaChromeIconButton(
              onTap: onPrev,
              icon: Icons.chevron_left_rounded,
            ),
            const SizedBox(width: 4),
            PaisaChromeIconButton(
              onTap: onNext,
              icon: Icons.chevron_right_rounded,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Hero: the coin ──────────────────────────────────────────────────────────

class _PaisaCoinHero extends StatelessWidget {
  const _PaisaCoinHero({
    required this.start,
    required this.end,
    required this.isRange,
    required this.out,
    required this.income,
    required this.onDateTap,
    this.onSwipeDay,
  });

  final DateTime start;
  final DateTime end;
  final bool isRange;
  final double out;
  final double income;
  final VoidCallback onDateTap;
  final void Function(int delta)? onSwipeDay;

  @override
  Widget build(BuildContext context) {
    final dateLine = isRange
        ? formatDayStripRangeHeader(start, end)
        : formatDayStripHeader(start);
    final emboss = isRange
        ? '${end.difference(start).inDays + 1}D'
        : '${start.day}';

    return PaisaCoinRise(
      child: GestureDetector(
        onTap: onDateTap,
        onHorizontalDragEnd: onSwipeDay == null
            ? null
            : (details) {
                final v = details.primaryVelocity ?? 0;
                if (v < -200) {
                  onSwipeDay!(1);
                } else if (v > 200) {
                  onSwipeDay!(-1);
                }
              },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              isRange ? 'RANGE' : 'DAY',
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
                dateLine,
                style: PaisaTheme.sora(
                  size: 19,
                  weight: FontWeight.w800,
                  color: PaisaColors.ink,
                  letterSpacing: 3.4,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _CoinFace(out: out, income: income, emboss: emboss),
          ],
        ),
      ),
    );
  }
}

/// The struck disc: milled rim, split OUT/IN gauge, recessed field.
class _CoinFace extends StatelessWidget {
  const _CoinFace({
    required this.out,
    required this.income,
    required this.emboss,
  });

  final double out;
  final double income;
  final String emboss;

  @override
  Widget build(BuildContext context) {
    return PaisaCoinFace(
      outShare: dayStripOutShare(out, income),
      hasFlow: out + income > 0,
      topLegend: emboss,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'OUT',
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
              formatInr(out),
              style: PaisaTheme.sora(
                size: 30,
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
    );
  }
}

// ── Filters ─────────────────────────────────────────────────────────────────

class _CoinFilters extends StatelessWidget {
  const _CoinFilters({
    required this.flow,
    required this.sort,
    required this.onFlow,
    required this.onSort,
  });

  final _StripFlowFilter flow;
  final TransactionSort sort;
  final ValueChanged<_StripFlowFilter> onFlow;
  final ValueChanged<TransactionSort> onSort;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StripFilterChip(
          label: 'All',
          active: flow == _StripFlowFilter.all,
          onTap: () => onFlow(_StripFlowFilter.all),
        ),
        const SizedBox(width: 6),
        _StripFilterChip(
          label: 'Out',
          active: flow == _StripFlowFilter.out,
          onTap: () => onFlow(_StripFlowFilter.out),
        ),
        const SizedBox(width: 6),
        _StripFilterChip(
          label: 'In',
          active: flow == _StripFlowFilter.inn,
          onTap: () => onFlow(_StripFlowFilter.inn),
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
                onChanged: onSort,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StripFilterChip extends StatelessWidget {
  const _StripFilterChip({
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
          boxShadow: active
              ? PaisaColors.hardShadow(offset: 2)
              : null,
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

// ── Coin-stamped transaction rows ───────────────────────────────────────────

class _CoinRow extends StatelessWidget {
  const _CoinRow({
    super.key,
    required this.transaction,
    required this.isMove,
    required this.intensity,
    required this.onTap,
    required this.index,
    required this.isLast,
    this.showDate = false,
  });

  final Transaction transaction;
  final bool isMove;
  final double intensity;
  final VoidCallback onTap;
  final int index;
  final bool isLast;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final maskMerchants =
        context.watch<AppSettings?>()?.maskMerchantNames ?? false;
    final merchant = dayStripMerchantLabel(transaction.merchant, maskMerchants);
    final isOut = !transaction.isCredit;
    final amountColor = isMove
        ? PaisaColors.mutedCaption
        : (isOut ? PaisaColors.debit : PaisaColors.credit);
    final tokenColor = isMove
        ? PaisaColors.mutedLight
        : (isOut ? PaisaColors.ink : PaisaColors.primary);
    final timeLabel = showDate
        ? '${transaction.timestamp.day} ${_monthShort(transaction.timestamp)} ${formatTxnTime(transaction.timestamp)}'
        : formatTxnTime(transaction.timestamp);

    // Staggered stamp-in (capped) — the second of three hero motions.
    final delayMs = math.min(index * 32, 192);

    return PaisaCoinRise(
      duration: Duration(milliseconds: 340 + delayMs),
      offsetY: 8,
      child: Semantics(
        button: true,
        label: '$merchant, ${formatAmount(transaction.amount, isCredit: transaction.isCredit)}',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.fromLTRB(2, 11, 2, 11),
              decoration: BoxDecoration(
                border: isLast
                    ? null
                    : const Border(
                        bottom: BorderSide(
                          color: PaisaColors.border,
                          width: 1,
                        ),
                      ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  PaisaCoinToken(
                    color: tokenColor,
                    fill: intensity,
                    dashed: isMove,
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (isMove) ...[
                              const _MoveBadge(),
                              const SizedBox(width: 7),
                            ],
                            Expanded(
                              child: Text(
                                merchant,
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
                              formatAmount(
                                transaction.amount,
                                isCredit: transaction.isCredit,
                              ),
                              style: PaisaTheme.sora(
                                size: 14,
                                weight: FontWeight.w800,
                                color: amountColor,
                              ),
                            ),
                            const SizedBox(width: 2),
                            const PaisaNavChevron(),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Text(
                              transaction.categoryInfo.label,
                              style: PaisaTheme.manrope(
                                size: 11,
                                weight: FontWeight.w700,
                                color: PaisaColors.mutedCaption,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              timeLabel,
                              style: PaisaTheme.manrope(
                                size: 11,
                                weight: FontWeight.w600,
                                color: PaisaColors.muted,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                transaction.accountLine,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                                style: PaisaTheme.manrope(
                                  size: 11,
                                  weight: FontWeight.w500,
                                  color: PaisaColors.muted,
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
            ),
          ),
        ),
      ),
    );
  }
}

class _MoveBadge extends StatelessWidget {
  const _MoveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: PaisaColors.cardElevated,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: PaisaColors.muted.withOpacity(0.55),
          width: 1,
        ),
      ),
      child: Text(
        'MOVE',
        style: PaisaTheme.sora(
          size: 8,
          weight: FontWeight.w800,
          color: PaisaColors.mutedCaption,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}

// ── Empty + net ─────────────────────────────────────────────────────────────

class _EmptyDay extends StatelessWidget {
  const _EmptyDay({required this.day, required this.canMint});

  final DateTime day;
  final bool canMint;

  Future<void> _mint(BuildContext context) async {
    final id = await showMintTransactionSheet(context, initialDay: day);
    if (id == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Minted · Manually added',
          style: PaisaTheme.manrope(
            size: 13,
            color: PaisaColors.inkOnAccent,
          ),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: PaisaColors.primary,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 34, 32, 60),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 2,
            color: PaisaColors.border,
          ),
          const SizedBox(height: 20),
          Text(
            'No money moved',
            style: PaisaTheme.sora(
              size: 17,
              weight: FontWeight.w800,
              color: PaisaColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'The coin stays unstruck for this date.',
            textAlign: TextAlign.center,
            style: PaisaTheme.manrope(
              size: 13,
              weight: FontWeight.w600,
              color: PaisaColors.mutedCaption,
            ),
          ),
          if (canMint) ...[
            const SizedBox(height: 18),
            GestureDetector(
              onTap: () => _mint(context),
              child: NeoSurface(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                radius: 14,
                borderWidth: 2,
                borderColor: PaisaColors.inkOnAccent,
                color: PaisaColors.primary,
                shadow: true,
                shadowOffset: 4,
                child: Text(
                  'MINT A TRANSACTION',
                  textAlign: TextAlign.center,
                  style: PaisaTheme.label(
                    size: 12,
                    color: PaisaColors.inkOnAccent,
                    letterSpacing: 1.3,
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

/// Floating hard-shadow net caption — not a bland full-width footer bar.
class _NetCaption extends StatelessWidget {
  const _NetCaption({required this.net});

  final double net;

  @override
  Widget build(BuildContext context) {
    final label = net >= 0
        ? 'net +${formatInr(net)}'
        : 'net −${formatInr(net.abs())}';
    final color = net >= 0 ? PaisaColors.primary : PaisaColors.ink;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        child: Center(
          child: PaisaCoinRise(
            duration: const Duration(milliseconds: 420),
            offsetY: 8,
            child: NeoSurface(
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              radius: 14,
              borderWidth: 2,
              borderColor: PaisaColors.inkOnAccent,
              color: PaisaColors.cardElevated,
              shadow: true,
              shadowOffset: 4,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: PaisaTheme.sora(
                  size: 14,
                  weight: FontWeight.w800,
                  color: color,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
