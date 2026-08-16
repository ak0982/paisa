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
import '../widgets/neo_surface.dart';
import '../widgets/pulse_calendar_sheet.dart';
import '../widgets/transaction_sort_control.dart';

enum _StripFlowFilter { all, out, inn }

/// Vertical money filmstrip for one local calendar day or an inclusive range.
///
/// OUT grows left (white), IN grows right (lime). Internal moves use a dashed
/// bar + MOVE badge and stay out of the OUT/IN KPIs.
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
    final maskMerchants =
        context.read<AppSettings?>()?.maskMerchantNames ?? false;
    final merchant = dayStripMerchantLabel(t.merchant, maskMerchants);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: PaisaColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: PaisaColors.border, width: 2),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: PaisaColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        merchant,
                        style: PaisaTheme.sora(
                          size: 18,
                          weight: FontWeight.w800,
                          color: PaisaColors.ink,
                        ),
                      ),
                    ),
                    if (isMove)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: PaisaColors.cardElevated,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: PaisaColors.muted,
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          'MOVE',
                          style: PaisaTheme.sora(
                            size: 10,
                            weight: FontWeight.w800,
                            color: PaisaColors.mutedCaption,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  formatAmount(t.amount, isCredit: t.isCredit),
                  style: PaisaTheme.sora(
                    size: 28,
                    weight: FontWeight.w800,
                    color: isMove
                        ? PaisaColors.mutedCaption
                        : (t.isCredit ? PaisaColors.credit : PaisaColors.debit),
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${formatTxnDate(t.timestamp)} · ${formatTxnTime(t.timestamp)}',
                  style: PaisaTheme.manrope(
                    size: 13,
                    weight: FontWeight.w600,
                    color: PaisaColors.mutedCaption,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${t.flowLabel} · ${t.metaLine}',
                  style: PaisaTheme.manrope(
                    size: 13,
                    color: PaisaColors.muted,
                  ),
                ),
                if (t.source == 'SMS') ...[
                  const SizedBox(height: 8),
                  Text(
                    '⚡ From SMS',
                    style: PaisaTheme.manrope(
                      size: 12,
                      weight: FontWeight.w600,
                      color: PaisaColors.muted,
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
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: PaisaColors.ink,
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: _openCalendar,
                          onHorizontalDragEnd: _isRange
                              ? null
                              : (details) {
                                  final v = details.primaryVelocity ?? 0;
                                  if (v < -200) {
                                    _shiftDay(1);
                                  } else if (v > 200) {
                                    _shiftDay(-1);
                                  }
                                },
                          child: Text(
                            _isRange
                                ? formatDayStripRangeHeader(_start, endInclusive)
                                : formatDayStripHeader(_start),
                            textAlign: TextAlign.center,
                            style: PaisaTheme.sora(
                              size: 16,
                              weight: FontWeight.w800,
                              color: PaisaColors.ink,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Pulse Calendar',
                        onPressed: _openCalendar,
                        icon: const Icon(
                          Icons.calendar_month_rounded,
                          color: PaisaColors.primary,
                        ),
                      ),
                      if (!_isRange) ...[
                        _DayNavButton(
                          icon: Icons.chevron_left_rounded,
                          onTap: () => _shiftDay(-1),
                        ),
                        const SizedBox(width: 4),
                        _DayNavButton(
                          icon: Icons.chevron_right_rounded,
                          onTap: () => _shiftDay(1),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      _StripFilterChip(
                        label: 'All',
                        active: _flow == _StripFlowFilter.all,
                        onTap: () =>
                            setState(() => _flow = _StripFlowFilter.all),
                      ),
                      const SizedBox(width: 6),
                      _StripFilterChip(
                        label: 'Out',
                        active: _flow == _StripFlowFilter.out,
                        onTap: () =>
                            setState(() => _flow = _StripFlowFilter.out),
                      ),
                      const SizedBox(width: 6),
                      _StripFilterChip(
                        label: 'In',
                        active: _flow == _StripFlowFilter.inn,
                        onTap: () =>
                            setState(() => _flow = _StripFlowFilter.inn),
                      ),
                      const Spacer(),
                      TransactionSortControl(
                        sort: _sort,
                        onChanged: (s) => setState(() => _sort = s),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _AxisHeader(out: out, income: income),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: items.isEmpty
                      ? const _EmptyDay()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                          itemCount: items.length,
                          itemBuilder: (context, i) {
                            final t = items[i];
                            final isMove = t.isCreditCardBillPayment ||
                                t.isCreditCardPaymentReceived ||
                                moveIds.contains(t.id);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _StripRow(
                                transaction: t,
                                isMove: isMove,
                                intensity:
                                    (t.amount / maxAmt).clamp(0.12, 1.0),
                                showDate: _isRange,
                                onTap: () =>
                                    _showTxnSheet(context, t, isMove),
                              ),
                            );
                          },
                        ),
                ),
                _NetFooter(net: net),
              ],
            ),
          ),
        );
      },
    );
  }
}

String dayStripMerchantLabel(String merchant, bool mask) {
  if (!mask || merchant.length <= 2) return merchant;
  if (merchant.length <= 4) {
    return '${merchant[0]}••${merchant[merchant.length - 1]}';
  }
  return '${merchant.substring(0, 2)}••••${merchant.substring(merchant.length - 2)}';
}

/// Uppercase filmstrip date, e.g. `FRI 15 AUG`.
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? PaisaColors.primary : PaisaColors.cardElevated,
          border: Border.all(
            color: active ? PaisaColors.primary : PaisaColors.border,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label.toUpperCase(),
          style: PaisaTheme.manrope(
            size: 11,
            weight: FontWeight.w700,
            color: active ? PaisaColors.inkOnAccent : PaisaColors.mutedCaption,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}

class _DayNavButton extends StatelessWidget {
  const _DayNavButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: NeoSurface(
        width: 36,
        height: 36,
        radius: 10,
        borderWidth: 1.5,
        padding: EdgeInsets.zero,
        child: Icon(icon, size: 22, color: PaisaColors.ink),
      ),
    );
  }
}

class _AxisHeader extends StatelessWidget {
  const _AxisHeader({required this.out, required this.income});

  final double out;
  final double income;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Text(
              'OUT',
              style: PaisaTheme.label(
                size: 11,
                color: PaisaColors.ink,
                letterSpacing: 2,
              ),
            ),
            const Spacer(),
            Text(
              'IN',
              style: PaisaTheme.label(
                size: 11,
                color: PaisaColors.primary,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Container(
                height: 2,
                color: PaisaColors.ink.withOpacity(0.35),
              ),
            ),
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: PaisaColors.ink,
                shape: BoxShape.circle,
              ),
            ),
            Expanded(
              child: Container(
                height: 2,
                color: PaisaColors.primary.withOpacity(0.55),
              ),
            ),
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: PaisaColors.primary,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                formatInr(out),
                style: PaisaTheme.sora(
                  size: 22,
                  weight: FontWeight.w800,
                  color: PaisaColors.ink,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            Expanded(
              child: Text(
                formatInr(income),
                textAlign: TextAlign.right,
                style: PaisaTheme.sora(
                  size: 22,
                  weight: FontWeight.w800,
                  color: PaisaColors.primary,
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StripRow extends StatelessWidget {
  const _StripRow({
    required this.transaction,
    required this.isMove,
    required this.intensity,
    required this.onTap,
    this.showDate = false,
  });

  final Transaction transaction;
  final bool isMove;
  final double intensity;
  final VoidCallback onTap;
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
    final barColor = isMove
        ? PaisaColors.mutedLight
        : (isOut ? PaisaColors.ink : PaisaColors.primary);
    final timeLabel = showDate
        ? '${transaction.timestamp.day} ${_shortMonth(transaction.timestamp)} · ${formatTxnTime(transaction.timestamp)}'
        : formatTxnTime(transaction.timestamp);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: NeoSurface(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          radius: 14,
          borderWidth: 1.5,
          shadow: true,
          shadowOffset: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    timeLabel,
                    style: PaisaTheme.manrope(
                      size: 11,
                      weight: FontWeight.w700,
                      color: PaisaColors.muted,
                    ),
                  ),
                  const Spacer(),
                  if (isMove)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: PaisaColors.cardElevated,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: PaisaColors.muted.withOpacity(0.7),
                          width: 1.2,
                        ),
                      ),
                      child: Text(
                        'MOVE',
                        style: PaisaTheme.sora(
                          size: 9,
                          weight: FontWeight.w800,
                          color: PaisaColors.mutedCaption,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
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
                ],
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final maxW = constraints.maxWidth;
                  final barW =
                      (maxW * 0.48 * intensity).clamp(18.0, maxW * 0.48);
                  return SizedBox(
                    height: 10,
                    width: maxW,
                    child: Stack(
                      children: [
                        Positioned(
                          left: maxW / 2 - 1,
                          top: 0,
                          bottom: 0,
                          child: Container(
                            width: 2,
                            color: PaisaColors.border,
                          ),
                        ),
                        if (isOut)
                          Positioned(
                            right: maxW / 2,
                            top: 1,
                            child: _MoneyBar(
                              width: barW,
                              color: barColor,
                              dashed: isMove,
                              growLeft: true,
                            ),
                          )
                        else
                          Positioned(
                            left: maxW / 2,
                            top: 1,
                            child: _MoneyBar(
                              width: barW,
                              color: barColor,
                              dashed: isMove,
                              growLeft: false,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              Text(
                '$merchant · ${transaction.categoryInfo.label}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PaisaTheme.manrope(
                  size: 12.5,
                  weight: FontWeight.w600,
                  color: PaisaColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                transaction.accountLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PaisaTheme.manrope(
                  size: 11,
                  color: PaisaColors.mutedCaption,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _shortMonth(DateTime d) {
    const months = [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
    ];
    return months[d.month - 1];
  }
}

class _MoneyBar extends StatelessWidget {
  const _MoneyBar({
    required this.width,
    required this.color,
    required this.dashed,
    required this.growLeft,
  });

  final double width;
  final Color color;
  final bool dashed;
  final bool growLeft;

  @override
  Widget build(BuildContext context) {
    final bar = Container(
      width: width,
      height: 8,
      decoration: BoxDecoration(
        color: dashed ? Colors.transparent : color,
        borderRadius: BorderRadius.circular(2),
        boxShadow: dashed
            ? null
            : [
                BoxShadow(
                  color: Colors.black,
                  offset: Offset(growLeft ? -2 : 2, 2),
                  blurRadius: 0,
                ),
              ],
      ),
      child: dashed
          ? CustomPaint(
              painter: _DashedBarPainter(color: color),
            )
          : null,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: growLeft
          ? [
              bar,
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: PaisaColors.inkOnAccent, width: 1),
                ),
              ),
            ]
          : [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: PaisaColors.inkOnAccent, width: 1),
                ),
              ),
              bar,
            ],
    );
  }
}

class _DashedBarPainter extends CustomPainter {
  _DashedBarPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    const dash = 5.0;
    const gap = 3.5;
    var x = 0.0;
    final y = size.height / 2;
    while (x < size.width) {
      final end = math.min(x + dash, size.width);
      canvas.drawLine(Offset(x, y), Offset(end, y), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBarPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _EmptyDay extends StatelessWidget {
  const _EmptyDay();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'No money moved',
              style: PaisaTheme.sora(
                size: 16,
                weight: FontWeight.w800,
                color: PaisaColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${formatInr(0)} out · ${formatInr(0)} in',
              style: PaisaTheme.manrope(
                size: 13,
                weight: FontWeight.w600,
                color: PaisaColors.mutedCaption,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NetFooter extends StatelessWidget {
  const _NetFooter({required this.net});

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
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: NeoSurface(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          radius: 16,
          borderWidth: 2,
          borderColor: PaisaColors.inkOnAccent,
          color: PaisaColors.cardElevated,
          shadow: true,
          shadowOffset: 5,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: PaisaTheme.sora(
              size: 16,
              weight: FontWeight.w800,
              color: color,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
    );
  }
}
