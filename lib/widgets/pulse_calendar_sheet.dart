import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/finance_store.dart';
import '../theme/paisa_colors.dart';
import '../theme/paisa_theme.dart';
import 'neo_surface.dart';

/// Day vs multi-day selection returned by [showPulseCalendarSheet].
class PulseCalendarResult {
  const PulseCalendarResult({
    required this.start,
    required this.end,
    required this.isRange,
  });

  final DateTime start;
  final DateTime end;
  final bool isRange;

  DateTime get startDay => DateTime(start.year, start.month, start.day);
  DateTime get endDay => DateTime(end.year, end.month, end.day);
}

enum PulseCalendarMode { day, range }

/// Neo-Vault Pulse Calendar — month grid with spend-intensity cells.
///
/// Not a stock Material date picker. Dark surface, hard borders, lime
/// intensity fills (near-black → primary), Day | Range toggle.
Future<PulseCalendarResult?> showPulseCalendarSheet(
  BuildContext context, {
  DateTime? initialStart,
  DateTime? initialEnd,
  PulseCalendarMode initialMode = PulseCalendarMode.day,
}) {
  final now = DateTime.now();
  final seed = initialStart ?? now;
  return showModalBottomSheet<PulseCalendarResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.72),
    builder: (ctx) {
      return PulseCalendarSheet(
        initialStart: DateTime(seed.year, seed.month, seed.day),
        initialEnd: initialEnd == null
            ? null
            : DateTime(initialEnd.year, initialEnd.month, initialEnd.day),
        initialMode: initialMode,
      );
    },
  );
}

class PulseCalendarSheet extends StatefulWidget {
  const PulseCalendarSheet({
    super.key,
    required this.initialStart,
    this.initialEnd,
    this.initialMode = PulseCalendarMode.day,
  });

  final DateTime initialStart;
  final DateTime? initialEnd;
  final PulseCalendarMode initialMode;

  @override
  State<PulseCalendarSheet> createState() => _PulseCalendarSheetState();
}

class _PulseCalendarSheetState extends State<PulseCalendarSheet> {
  late PulseCalendarMode _mode;
  late DateTime _visibleMonth;
  late DateTime _start;
  DateTime? _end;
  /// Range mode: after first tap, next tap completes the range.
  bool _awaitingRangeEnd = false;

  static const _months = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _start = widget.initialStart;
    _end = widget.initialEnd;
    if (_mode == PulseCalendarMode.range) {
      _end ??= _start;
      _awaitingRangeEnd = false;
    } else {
      _end = null;
    }
    _visibleMonth = DateTime(_start.year, _start.month);
  }

  void _shiftMonth(int delta) {
    HapticFeedback.selectionClick();
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
    });
  }

  void _setMode(PulseCalendarMode mode) {
    if (_mode == mode) return;
    HapticFeedback.selectionClick();
    setState(() {
      _mode = mode;
      if (mode == PulseCalendarMode.day) {
        _end = null;
        _awaitingRangeEnd = false;
      } else {
        _end ??= _start;
        _awaitingRangeEnd = false;
      }
    });
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isBeforeDay(DateTime a, DateTime b) {
    final aa = DateTime(a.year, a.month, a.day);
    final bb = DateTime(b.year, b.month, b.day);
    return aa.isBefore(bb);
  }

  void _onDayTap(DateTime day) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_mode == PulseCalendarMode.day) {
        _start = day;
        _end = null;
        return;
      }
      if (!_awaitingRangeEnd) {
        _start = day;
        _end = day;
        _awaitingRangeEnd = true;
        return;
      }
      if (_isBeforeDay(day, _start)) {
        _end = _start;
        _start = day;
      } else {
        _end = day;
      }
      _awaitingRangeEnd = false;
    });
  }

  bool _inSelectedRange(DateTime day) {
    if (_mode != PulseCalendarMode.range) return false;
    final end = _end ?? _start;
    final lo = _isBeforeDay(_start, end) ? _start : end;
    final hi = _isBeforeDay(_start, end) ? end : _start;
    final d = DateTime(day.year, day.month, day.day);
    final a = DateTime(lo.year, lo.month, lo.day);
    final b = DateTime(hi.year, hi.month, hi.day);
    return !d.isBefore(a) && !d.isAfter(b);
  }

  bool _isEndpoint(DateTime day) {
    if (_mode == PulseCalendarMode.day) return _sameDay(day, _start);
    final end = _end ?? _start;
    return _sameDay(day, _start) || _sameDay(day, end);
  }

  void _confirm() {
    final end = _mode == PulseCalendarMode.day ? _start : (_end ?? _start);
    var a = _start;
    var b = end;
    if (_isBeforeDay(b, a)) {
      final tmp = a;
      a = b;
      b = tmp;
    }
    Navigator.of(context).pop(
      PulseCalendarResult(
        start: a,
        end: b,
        isRange: _mode == PulseCalendarMode.range && !_sameDay(a, b),
      ),
    );
  }

  String get _selectionLabel {
    if (_mode == PulseCalendarMode.day ||
        _end == null ||
        _sameDay(_start, _end!)) {
      return '${_start.day} ${_months[_start.month - 1]} ${_start.year}';
    }
    var a = _start;
    var b = _end!;
    if (_isBeforeDay(b, a)) {
      final tmp = a;
      a = b;
      b = tmp;
    }
    if (a.year == b.year && a.month == b.month) {
      return '${a.day}–${b.day} ${_months[a.month - 1]}';
    }
    if (a.year == b.year) {
      return '${a.day} ${_months[a.month - 1]} – ${b.day} ${_months[b.month - 1]}';
    }
    return '${a.day} ${_months[a.month - 1]} ${a.year} – ${b.day} ${_months[b.month - 1]} ${b.year}';
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final spendMap = store.monthDaySpendMap(_visibleMonth);
    var peak = 0.0;
    for (final v in spendMap.values) {
      if (v > peak) peak = v;
    }
    final today = DateTime.now();
    final todayDay = DateTime(today.year, today.month, today.day);
    final firstOfMonth = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    // Monday-first grid (Neo-Vault week starts Mon).
    final leadEmpty = (firstOfMonth.weekday - DateTime.monday) % 7;
    final daysInMonth =
        DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
    final totalCells = leadEmpty + daysInMonth;
    final rows = (totalCells / 7).ceil();

    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      decoration: BoxDecoration(
        color: PaisaColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: PaisaColors.inkOnAccent, width: 2),
        boxShadow: PaisaColors.hardShadow(offset: 6),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 12 + bottomInset * 0.15),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: PaisaColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(
                    'PULSE',
                    style: PaisaTheme.label(
                      size: 11,
                      color: PaisaColors.primary,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'CALENDAR',
                    style: PaisaTheme.sora(
                      size: 16,
                      weight: FontWeight.w800,
                      color: PaisaColors.ink,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _selectionLabel,
                    style: PaisaTheme.manrope(
                      size: 12,
                      weight: FontWeight.w700,
                      color: PaisaColors.mutedCaption,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _ModeChip(
                    label: 'Day',
                    active: _mode == PulseCalendarMode.day,
                    onTap: () => _setMode(PulseCalendarMode.day),
                  ),
                  const SizedBox(width: 8),
                  _ModeChip(
                    label: 'Range',
                    active: _mode == PulseCalendarMode.range,
                    onTap: () => _setMode(PulseCalendarMode.range),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _MonthNav(
                    icon: Icons.chevron_left_rounded,
                    onTap: () => _shiftMonth(-1),
                  ),
                  Expanded(
                    child: Text(
                      '${_months[_visibleMonth.month - 1]} ${_visibleMonth.year}',
                      textAlign: TextAlign.center,
                      style: PaisaTheme.sora(
                        size: 15,
                        weight: FontWeight.w800,
                        color: PaisaColors.ink,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                  _MonthNav(
                    icon: Icons.chevron_right_rounded,
                    onTap: () => _shiftMonth(1),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Row(
                children: [
                  _WeekdayLabel('M'),
                  _WeekdayLabel('T'),
                  _WeekdayLabel('W'),
                  _WeekdayLabel('T'),
                  _WeekdayLabel('F'),
                  _WeekdayLabel('S'),
                  _WeekdayLabel('S'),
                ],
              ),
              const SizedBox(height: 6),
              for (var r = 0; r < rows; r++) ...[
                if (r > 0) const SizedBox(height: 4),
                Row(
                  children: [
                    for (var c = 0; c < 7; c++)
                      Expanded(
                        child: Builder(
                          builder: (_) {
                            final index = r * 7 + c;
                            final dayNum = index - leadEmpty + 1;
                            if (dayNum < 1 || dayNum > daysInMonth) {
                              return const SizedBox(height: 42);
                            }
                            final day = DateTime(
                              _visibleMonth.year,
                              _visibleMonth.month,
                              dayNum,
                            );
                            final spend = spendMap[dayNum] ?? 0.0;
                            final intensity = peak <= 0
                                ? 0.0
                                : (spend / peak).clamp(0.0, 1.0);
                            return _DayCell(
                              day: dayNum,
                              intensity: intensity,
                              isToday: _sameDay(day, todayDay),
                              inRange: _inSelectedRange(day),
                              isEndpoint: _isEndpoint(day),
                              onTap: () => _onDayTap(day),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).maybePop(),
                      child: NeoSurface(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        radius: 14,
                        borderWidth: 1.5,
                        child: Text(
                          'CANCEL',
                          textAlign: TextAlign.center,
                          style: PaisaTheme.label(
                            size: 12,
                            color: PaisaColors.mutedCaption,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: _confirm,
                      child: NeoSurface(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        radius: 14,
                        borderWidth: 2,
                        borderColor: PaisaColors.inkOnAccent,
                        color: PaisaColors.primary,
                        shadow: true,
                        shadowOffset: 4,
                        child: Text(
                          'JUMP',
                          textAlign: TextAlign.center,
                          style: PaisaTheme.label(
                            size: 13,
                            color: PaisaColors.inkOnAccent,
                            letterSpacing: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? PaisaColors.primary : PaisaColors.cardElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? PaisaColors.primary : PaisaColors.border,
            width: 1.5,
          ),
        ),
        child: Text(
          label.toUpperCase(),
          style: PaisaTheme.manrope(
            size: 12,
            weight: FontWeight.w700,
            color: active ? PaisaColors.inkOnAccent : PaisaColors.mutedCaption,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}

class _MonthNav extends StatelessWidget {
  const _MonthNav({required this.icon, required this.onTap});

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

class _WeekdayLabel extends StatelessWidget {
  const _WeekdayLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: PaisaTheme.label(
          size: 10,
          color: PaisaColors.muted,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.intensity,
    required this.isToday,
    required this.inRange,
    required this.isEndpoint,
    required this.onTap,
  });

  final int day;
  final double intensity;
  final bool isToday;
  final bool inRange;
  final bool isEndpoint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Near-black → lime intensity fill for days with activity.
    final fill = intensity <= 0
        ? PaisaColors.surface
        : Color.lerp(
            const Color(0xFF111114),
            PaisaColors.primary,
            math.pow(intensity, 0.85).toDouble().clamp(0.12, 1.0),
          )!;

    final rangePlate = inRange && !isEndpoint
        ? PaisaColors.primary.withOpacity(0.18)
        : null;

    return Padding(
      padding: const EdgeInsets.all(2),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 42,
          decoration: BoxDecoration(
            color: rangePlate ?? fill,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isEndpoint
                  ? PaisaColors.primary
                  : (inRange
                      ? PaisaColors.primary.withOpacity(0.35)
                      : PaisaColors.border),
              width: isEndpoint ? 2.2 : 1.2,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                '$day',
                style: PaisaTheme.sora(
                  size: 13,
                  weight: FontWeight.w700,
                  color: intensity > 0.55 && !inRange
                      ? PaisaColors.inkOnAccent
                      : PaisaColors.ink,
                ),
              ),
              if (isToday)
                Positioned(
                  bottom: 5,
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: const BoxDecoration(
                      color: PaisaColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
