import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/finance_store.dart';
import '../screens/day_strip_screen.dart';
import '../theme/paisa_colors.dart';
import '../theme/paisa_theme.dart';
import '../utils/formatters.dart';
import 'neo_surface.dart';
import 'paisa_nav_chevron.dart';

/// Mini Day Strip entry under the Home month hero.
///
/// Shows selected/today OUT · IN plus optional intensity ticks for the last
/// five days. Tap opens [DayStripScreen].
class DayStripTeaser extends StatefulWidget {
  const DayStripTeaser({super.key, this.initialDay});

  final DateTime? initialDay;

  @override
  State<DayStripTeaser> createState() => _DayStripTeaserState();
}

class _DayStripTeaserState extends State<DayStripTeaser> {
  late DateTime _day;

  @override
  void initState() {
    super.initState();
    final seed = widget.initialDay ?? DateTime.now();
    _day = DateTime(seed.year, seed.month, seed.day);
  }

  void _shift(int delta) {
    final next = _day.add(Duration(days: delta));
    final today = DateTime.now();
    final todayDay = DateTime(today.year, today.month, today.day);
    // Don't wander far into the future from Home.
    if (next.isAfter(todayDay)) return;
    HapticFeedback.selectionClick();
    setState(() => _day = next);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<FinanceStore>(
      builder: (context, store, _) {
        final out = store.daySpend(_day);
        final income = store.dayIncome(_day);
        final series = store.recentDaySpendSeries(anchor: _day, count: 5);
        final peak = series.isEmpty
            ? 0.0
            : series.reduce((a, b) => a > b ? a : b);

        return NeoSurface(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          radius: 14,
          borderWidth: 1.5,
          shadow: true,
          shadowOffset: 3,
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  button: true,
                  label: 'Open day coin for ${formatDayStripHeader(_day)}',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => DayStripScreen.open(context, day: _day),
                    onHorizontalDragEnd: (details) {
                      final v = details.primaryVelocity ?? 0;
                      if (v < -240) {
                        _shift(1);
                      } else if (v > 240) {
                        _shift(-1);
                      }
                    },
                    child: Row(
                      children: [
                        Text(
                          'DAY',
                          style: PaisaTheme.label(
                            size: 10,
                            color: PaisaColors.primary,
                            letterSpacing: 1.6,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_day.day}',
                          style: PaisaTheme.sora(
                            size: 15,
                            weight: FontWeight.w800,
                            color: PaisaColors.ink,
                          ),
                        ),
                        const SizedBox(width: 10),
                        _IntensityTicks(series: series, peak: peak),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'out ${formatInr(out)}  in ${formatInr(income)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: PaisaTheme.manrope(
                              size: 12,
                              weight: FontWeight.w600,
                              color: PaisaColors.mutedCaption,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Pulse Calendar',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: () => DayStripScreen.open(
                  context,
                  day: _day,
                  openCalendar: true,
                ),
                icon: const Icon(
                  Icons.calendar_month_rounded,
                  size: 20,
                  color: PaisaColors.primary,
                ),
              ),
              const PaisaNavChevron(
                size: 20,
                color: PaisaColors.primary,
              ),
              const SizedBox(width: 4),
            ],
          ),
        );
      },
    );
  }
}

class _IntensityTicks extends StatelessWidget {
  const _IntensityTicks({required this.series, required this.peak});

  final List<double> series;
  final double peak;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < series.length; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          _Tick(
            fill: peak <= 0 ? 0.15 : (series[i] / peak).clamp(0.15, 1.0),
            active: i == series.length - 1,
          ),
        ],
      ],
    );
  }
}

class _Tick extends StatelessWidget {
  const _Tick({required this.fill, required this.active});

  final double fill;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 4,
      height: 14,
      decoration: BoxDecoration(
        color: Color.lerp(
          PaisaColors.border,
          active ? PaisaColors.primary : PaisaColors.ink.withOpacity(0.55),
          fill,
        ),
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}
