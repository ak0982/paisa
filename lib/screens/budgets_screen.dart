import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/budget.dart';
import '../models/category_info.dart';
import '../providers/finance_store.dart';
import '../theme/paisa_colors.dart';
import '../theme/paisa_theme.dart';
import '../utils/formatters.dart';
import '../widgets/paisa_coin.dart';
import '../widgets/paisa_nav_chevron.dart';
import '../widgets/paisa_progress_bar.dart';
import 'category_transactions_screen.dart';

/// Envelope mint — plan spend per category for the month or the year.
///
/// Same Neo-Vault / Paisa Coin family as Stats & Day Coin: milled plan/spent
/// hero, then horizontal ledger strips (not Material card stacks) for every
/// budgetable category — including rows still at plan ₹0 / spent ₹0.
/// Monthly and yearly plans are stored separately.
class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key});

  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  /// Session-hidden nudge keys (also persisted per category/day).
  final Set<String> _dismissedNudgeKeys = {};
  bool _nudgePrefsLoaded = false;

  static String _dayStamp([DateTime? now]) {
    final d = now ?? DateTime.now();
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  static String _nudgeKey({
    required BudgetPeriod period,
    required SpendCategory category,
    required bool isOver,
    DateTime? now,
  }) {
    final tier = isOver ? '100' : '75';
    return '${period.name}|${category.name}|${_dayStamp(now)}|$tier';
  }

  Future<void> _ensureNudgePrefs() async {
    if (_nudgePrefsLoaded) return;
    _nudgePrefsLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList('budget_nudge_dismissed') ?? const [];
      if (!mounted) return;
      setState(() => _dismissedNudgeKeys.addAll(raw));
    } catch (_) {}
  }

  Future<void> _dismissNudge(String key) async {
    setState(() => _dismissedNudgeKeys.add(key));
    try {
      final prefs = await SharedPreferences.getInstance();
      final next = prefs.getStringList('budget_nudge_dismissed') ?? <String>[];
      if (!next.contains(key)) {
        next.add(key);
        // Keep a short rolling window so prefs don't grow forever.
        while (next.length > 80) {
          next.removeAt(0);
        }
        await prefs.setStringList('budget_nudge_dismissed', next);
      }
    } catch (_) {}
  }

  /// Highest-priority undismissed 75%/100% nudge for the active period, if any.
  ({Budget budget, String key, bool isOver})? _activeNudge(
    List<Budget> budgets,
    BudgetPeriod period,
  ) {
    ({Budget budget, String key, bool isOver})? overHit;
    ({Budget budget, String key, bool isOver})? warnHit;
    for (final b in budgets) {
      if (b.limit <= 0) continue;
      if (b.status == BudgetStatus.over) {
        final key = _nudgeKey(
          period: period,
          category: b.category,
          isOver: true,
        );
        if (_dismissedNudgeKeys.contains(key)) continue;
        overHit ??= (budget: b, key: key, isOver: true);
      } else if (b.status == BudgetStatus.warning) {
        final key = _nudgeKey(
          period: period,
          category: b.category,
          isOver: false,
        );
        if (_dismissedNudgeKeys.contains(key)) continue;
        warnHit ??= (budget: b, key: key, isOver: false);
      }
    }
    return overHit ?? warnHit;
  }

  @override
  void initState() {
    super.initState();
    _ensureNudgePrefs();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<FinanceStore>(
      builder: (context, store, _) {
        final period = store.budgetPeriod;
        final yearly = period == BudgetPeriod.yearly;
        final budgets = store.budgets;
        final planned = store.totalBudget;
        final spent = store.budgetSpent;
        final remaining = (planned - spent).clamp(0.0, double.infinity);
        final daysLeft = store.budgetDaysLeft;
        final periodLabel = store.budgetPeriodLabel;
        final hasSms = store.transactions.isNotEmpty;
        final setCount =
            budgets.where((b) => b.limit > 0 || b.hasStoredPlan).length;
        final over = Budget.isOverAggregate(planned: planned, spent: spent);
        final dailyPace = store.budgetDailyPaceLeft;
        final nudge = _activeNudge(budgets, period);

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  PaisaCoinWordmark(suffix: yearly ? 'YEAR' : 'PLAN'),
                  const Spacer(),
                  Text(
                    periodLabel.toUpperCase(),
                    style: PaisaTheme.manrope(
                      size: 11,
                      weight: FontWeight.w700,
                      color: PaisaColors.mutedCaption,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(width: 4),
                  _BudgetActionsMenu(
                    yearly: yearly,
                    hasMonthlyPlans: store
                        .budgetsFor(BudgetPeriod.monthly)
                        .any((b) => b.hasStoredPlan),
                    hasYearlyPlans: store.hasAnyYearlyBudgetPlan,
                    hasActivePlans: setCount > 0,
                    onCopyMonthlyToYearly: () =>
                        _confirmCopyMonthlyToYearly(context, store),
                    onResetActive: () =>
                        _confirmResetActivePlans(context, store, period),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _PeriodMintToggle(
                period: period,
                onChanged: store.setBudgetPeriod,
              ),
              const SizedBox(height: 16),
              _EnvelopeHero(
                periodLabel: periodLabel,
                period: period,
                planned: planned,
                spent: spent,
                remaining: remaining,
                daysLeft: daysLeft,
                over: over,
                dailyPace: dailyPace,
              ),
              if (nudge != null) ...[
                const SizedBox(height: 12),
                _BudgetNudgeBanner(
                  budget: nudge.budget,
                  isOver: nudge.isOver,
                  onDismiss: () => _dismissNudge(nudge.key),
                ),
              ],
              if (!hasSms) ...[
                const SizedBox(height: 14),
                _SoftScanHint(onSync: store.syncFromSms),
              ],
              const SizedBox(height: 22),
              _SectionHeading(
                label: yearly ? 'YEAR ENVELOPES' : 'MONTH ENVELOPES',
                trailing: setCount == 0
                    ? (yearly ? 'SET YEAR PLAN' : 'SET A PLAN')
                    : '$setCount / ${budgets.length} SET',
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  yearly
                      ? 'Yearly plans are separate from monthly — spent matches Reports “This year”.'
                      : 'Monthly plans apply to this month — spent matches Reports “This month”.',
                  style: PaisaTheme.manrope(
                    size: 11,
                    weight: FontWeight.w600,
                    color: PaisaColors.muted,
                  ),
                ),
              ),
              for (var i = 0; i < budgets.length; i++)
                _EnvelopeStrip(
                  budget: budgets[i],
                  period: period,
                  index: i,
                  isLast: i == budgets.length - 1,
                  onOpenTransactions: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CategoryTransactionsScreen(
                        category: budgets[i].category,
                        range: store.budgetPeriodRange,
                        periodLabel: periodLabel,
                        alignWithSpendKpi: true,
                      ),
                    ),
                  ),
                  onEditPlan: () =>
                      _editBudgetLimit(context, store, budgets[i], period),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ── Period mint toggle ──────────────────────────────────────────────────────

class _PeriodMintToggle extends StatelessWidget {
  const _PeriodMintToggle({
    required this.period,
    required this.onChanged,
  });

  final BudgetPeriod period;
  final ValueChanged<BudgetPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Budget period',
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: PaisaColors.cardElevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: PaisaColors.border, width: 1.2),
        ),
        child: Row(
          children: [
            Expanded(
              child: _PeriodChip(
                label: 'MONTHLY',
                selected: period == BudgetPeriod.monthly,
                onTap: () => onChanged(BudgetPeriod.monthly),
              ),
            ),
            Expanded(
              child: _PeriodChip(
                label: 'YEARLY',
                selected: period == BudgetPeriod.yearly,
                onTap: () => onChanged(BudgetPeriod.yearly),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({
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
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? PaisaColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
              border: selected
                  ? Border.all(color: PaisaColors.primaryDeep, width: 1)
                  : null,
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: PaisaTheme.sora(
                size: 12,
                weight: FontWeight.w800,
                letterSpacing: 1.4,
                color: selected ? PaisaColors.inkOnAccent : PaisaColors.mutedCaption,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Hero: Plan vs Spent coin ────────────────────────────────────────────────

class _EnvelopeHero extends StatelessWidget {
  const _EnvelopeHero({
    required this.periodLabel,
    required this.period,
    required this.planned,
    required this.spent,
    required this.remaining,
    required this.daysLeft,
    required this.over,
    required this.dailyPace,
  });

  final String periodLabel;
  final BudgetPeriod period;
  final double planned;
  final double spent;
  final double remaining;
  final int daysLeft;
  final bool over;
  final double? dailyPace;

  @override
  Widget build(BuildContext context) {
    final gaugeBase = math.max(planned, spent);
    final outShare = gaugeBase > 0 ? (spent / gaugeBase).clamp(0.0, 1.0) : 0.0;
    final yearly = period == BudgetPeriod.yearly;
    final footer = '$daysLeft days left in $periodLabel';
    final overValue = over
        ? (planned > 0 ? spent - planned : spent)
        : remaining;

    String? paceLine;
    if (dailyPace != null && !yearly) {
      paceLine =
          '${formatInr(dailyPace!)}/day left to stay on plan';
    }

    return PaisaCoinRise(
      child: Column(
        children: [
          PaisaCoinFace(
            outShare: outShare,
            hasFlow: planned > 0 || spent > 0,
            topLegend: '• ${periodLabel.toUpperCase()} •',
            bottomLegend: yearly ? '• YEAR PLAN •' : '• P L A N •',
            maxDiameter: 268,
            fieldWidthFactor: 0.58,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  yearly ? 'YTD SPENT' : 'SPENT',
                  style: PaisaTheme.label(
                    size: 9,
                    color: PaisaColors.mutedCaption,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatInr(spent),
                  textAlign: TextAlign.center,
                  style: PaisaTheme.sora(
                    size: 26,
                    weight: FontWeight.w800,
                    color: PaisaColors.ink,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  planned > 0
                      ? 'of ${formatInr(planned)} ${yearly ? 'year' : 'month'} plan'
                      : 'no ${yearly ? 'year' : 'month'} plan yet',
                  textAlign: TextAlign.center,
                  style: PaisaTheme.manrope(
                    size: 11,
                    weight: FontWeight.w600,
                    color: over
                        ? PaisaColors.overBudget
                        : PaisaColors.mutedCaption,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _HeroStat(
                  label: 'PLANNED',
                  value: formatInr(planned),
                  accent: PaisaColors.primary,
                ),
              ),
              Container(
                width: 1,
                height: 36,
                color: PaisaColors.border,
              ),
              Expanded(
                child: _HeroStat(
                  label: yearly ? 'YTD' : 'SPENT',
                  value: formatInr(spent),
                  accent: PaisaColors.ink,
                ),
              ),
              Container(
                width: 1,
                height: 36,
                color: PaisaColors.border,
              ),
              Expanded(
                child: _HeroStat(
                  label: over ? 'OVER' : 'LEFT',
                  value: formatInr(overValue),
                  accent: over
                      ? PaisaColors.overBudget
                      : PaisaColors.mutedCaption,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            footer,
            textAlign: TextAlign.center,
            style: PaisaTheme.manrope(
              size: 11.5,
              weight: FontWeight.w600,
              color: PaisaColors.muted,
            ),
          ),
          if (paceLine != null) ...[
            const SizedBox(height: 4),
            Text(
              paceLine,
              textAlign: TextAlign.center,
              style: PaisaTheme.manrope(
                size: 11,
                weight: FontWeight.w600,
                color: PaisaColors.mutedCaption,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: PaisaTheme.label(
            size: 9,
            color: PaisaColors.muted,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: PaisaTheme.sora(
            size: 13.5,
            weight: FontWeight.w800,
            color: accent,
          ),
        ),
      ],
    );
  }
}

// ── Soft 75% / 100% nudge ───────────────────────────────────────────────────

class _BudgetNudgeBanner extends StatelessWidget {
  const _BudgetNudgeBanner({
    required this.budget,
    required this.isOver,
    required this.onDismiss,
  });

  final Budget budget;
  final bool isOver;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final label = budget.info.label;
    final text = isOver
        ? '$label is over plan (${budget.usedPercent}%).'
        : '$label is at ${budget.usedPercent}% of plan.';
    final accent = isOver ? PaisaColors.overBudget : PaisaColors.warning;

    return Semantics(
      liveRegion: true,
      label: text,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        decoration: BoxDecoration(
          color: accent.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withOpacity(0.45), width: 1.2),
        ),
        child: Row(
          children: [
            Icon(
              isOver ? Icons.warning_amber_rounded : Icons.timelapse_rounded,
              size: 18,
              color: accent,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: PaisaTheme.manrope(
                  size: 12.5,
                  weight: FontWeight.w700,
                  color: PaisaColors.ink,
                ),
              ),
            ),
            Semantics(
              button: true,
              label: 'Dismiss budget nudge',
              child: IconButton(
                onPressed: onDismiss,
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: PaisaColors.mutedCaption,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Header overflow actions ─────────────────────────────────────────────────

class _BudgetActionsMenu extends StatelessWidget {
  const _BudgetActionsMenu({
    required this.yearly,
    required this.hasMonthlyPlans,
    required this.hasYearlyPlans,
    required this.hasActivePlans,
    required this.onCopyMonthlyToYearly,
    required this.onResetActive,
  });

  final bool yearly;
  final bool hasMonthlyPlans;
  final bool hasYearlyPlans;
  final bool hasActivePlans;
  final VoidCallback onCopyMonthlyToYearly;
  final VoidCallback onResetActive;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_BudgetMenuAction>(
      tooltip: 'Budget actions',
      padding: EdgeInsets.zero,
      icon: const Icon(
        Icons.more_horiz_rounded,
        color: PaisaColors.mutedCaption,
        size: 22,
      ),
      onSelected: (action) {
        switch (action) {
          case _BudgetMenuAction.copyMonthly:
            onCopyMonthlyToYearly();
          case _BudgetMenuAction.reset:
            onResetActive();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _BudgetMenuAction.copyMonthly,
          enabled: hasMonthlyPlans,
          child: Text(
            hasYearlyPlans
                ? 'Copy monthly → yearly…'
                : 'Copy monthly ×12 → yearly',
            style: PaisaTheme.manrope(size: 13, weight: FontWeight.w600),
          ),
        ),
        PopupMenuItem(
          value: _BudgetMenuAction.reset,
          enabled: hasActivePlans,
          child: Text(
            yearly ? 'Reset yearly plans…' : 'Reset monthly plans…',
            style: PaisaTheme.manrope(size: 13, weight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

enum _BudgetMenuAction { copyMonthly, reset }

// ── Envelope ledger strips ──────────────────────────────────────────────────

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

class _EnvelopeStrip extends StatelessWidget {
  const _EnvelopeStrip({
    required this.budget,
    required this.period,
    required this.index,
    required this.isLast,
    required this.onOpenTransactions,
    required this.onEditPlan,
  });

  final Budget budget;
  final BudgetPeriod period;
  final int index;
  final bool isLast;
  final VoidCallback onOpenTransactions;
  final VoidCallback onEditPlan;

  String get _planChipLabel {
    if (budget.isUnset) {
      return period == BudgetPeriod.yearly ? 'Set year' : 'Set plan';
    }
    if (budget.hasStoredPlan && budget.limit <= 0) {
      return 'Plan ₹0';
    }
    return formatInr(budget.limit);
  }

  String get _subtitle {
    final yearly = period == BudgetPeriod.yearly;
    if (budget.isUnset) {
      return yearly
          ? 'No year spend yet · tap plan to set'
          : 'No spend yet · tap plan to set';
    }
    return 'Spent ${formatInr(budget.spent)} · Plan ${formatInr(budget.limit)}';
  }

  /// Remaining / used line under the progress bar.
  String get _remainingLine {
    if (budget.isUnset) {
      return 'No plan yet';
    }
    if (budget.hasStoredPlan && budget.limit <= 0 && budget.spent <= 0) {
      return 'Plan ₹0 · —';
    }
    if (budget.status == BudgetStatus.over) {
      return 'Over ${formatInr(budget.overAmount)} · ${budget.usedPercent}%';
    }
    if (budget.limit <= 0) {
      return 'Left ₹0 · —';
    }
    return 'Left ${formatInr(budget.remaining)} · ${budget.usedPercent}%';
  }

  Color get _remainingColor {
    if (budget.isUnset ||
        (budget.hasStoredPlan && budget.limit <= 0 && budget.spent <= 0)) {
      return PaisaColors.muted;
    }
    if (budget.status == BudgetStatus.over) return PaisaColors.overBudget;
    if (budget.status == BudgetStatus.warning) return PaisaColors.warning;
    return PaisaColors.mutedCaption;
  }

  @override
  Widget build(BuildContext context) {
    final info = budget.info;
    final delayMs = math.min(index * 28, 180);
    final over = budget.status == BudgetStatus.over;
    final unset = budget.isUnset;
    final zeroPlan = budget.hasStoredPlan && budget.limit <= 0;

    final strip = Container(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 12),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(color: PaisaColors.border, width: 1),
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 34,
                decoration: BoxDecoration(
                  color: info.iconColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              PaisaCoinToken(
                color: info.iconColor,
                fill: budget.ratio.clamp(0.0, 1.0),
                size: 34,
                glyph: info.emoji,
                glyphSize: 14,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Semantics(
                  button: true,
                  label: '${info.label} transactions',
                  child: InkWell(
                    onTap: onOpenTransactions,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        info.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: PaisaTheme.sora(
                                          size: 14.5,
                                          weight: FontWeight.w800,
                                          color: PaisaColors.ink,
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                    ),
                                    if (over) ...[
                                      const SizedBox(width: 7),
                                      const _OverStamp(),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: PaisaTheme.manrope(
                                    size: 11,
                                    weight: FontWeight.w600,
                                    color: budget.statusColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const PaisaNavChevron(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const SizedBox(width: 13),
              Expanded(
                child: PaisaProgressBar(
                  progress: budget.ratio.clamp(0.0, 1.0),
                  color: unset ? PaisaColors.border : budget.barColor,
                  height: 5,
                  trackColor: PaisaColors.border,
                ),
              ),
              const SizedBox(width: 12),
              Semantics(
                button: true,
                label: 'Edit ${info.label} budget',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onEditPlan,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: unset
                            ? PaisaColors.cardElevated
                            : PaisaColors.card,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: unset
                              ? PaisaColors.primary.withOpacity(0.45)
                              : zeroPlan
                                  ? PaisaColors.primary.withOpacity(0.35)
                                  : PaisaColors.border,
                          width: 1.2,
                        ),
                      ),
                      child: Text(
                        _planChipLabel,
                        style: PaisaTheme.sora(
                          size: 11.5,
                          weight: FontWeight.w800,
                          color: unset || zeroPlan
                              ? PaisaColors.primary
                              : PaisaColors.ink,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 13),
            child: Text(
              _remainingLine,
              style: PaisaTheme.manrope(
                size: 11,
                weight: FontWeight.w600,
                color: _remainingColor,
              ),
            ),
          ),
        ],
      ),
    );

    return PaisaCoinRise(
      duration: Duration(milliseconds: 320 + delayMs),
      offsetY: 8,
      child: strip,
    );
  }
}

class _OverStamp extends StatelessWidget {
  const _OverStamp();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: PaisaColors.overBudget,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        'OVER',
        style: PaisaTheme.sora(
          size: 8,
          weight: FontWeight.w800,
          color: PaisaColors.ink,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _SoftScanHint extends StatelessWidget {
  const _SoftScanHint({required this.onSync});

  final Future<ScanResult> Function() onSync;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: PaisaColors.cardElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PaisaColors.border, width: 1.2),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Set envelopes now — scan SMS anytime to fill spent amounts.',
              style: PaisaTheme.manrope(
                size: 12,
                weight: FontWeight.w600,
                color: PaisaColors.mutedCaption,
              ),
            ),
          ),
          const SizedBox(width: 10),
          TextButton(
            onPressed: onSync,
            style: TextButton.styleFrom(
              foregroundColor: PaisaColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            child: Text(
              'SCAN',
              style: PaisaTheme.sora(
                size: 12,
                weight: FontWeight.w800,
                color: PaisaColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Confirm sheets / dialogs ────────────────────────────────────────────────

Future<void> _confirmCopyMonthlyToYearly(
  BuildContext context,
  FinanceStore store,
) async {
  final monthlySet =
      store.budgetsFor(BudgetPeriod.monthly).where((b) => b.hasStoredPlan);
  if (monthlySet.isEmpty) return;

  final hasYearly = store.hasAnyYearlyBudgetPlan;
  final confirmed = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: PaisaColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: PaisaColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Copy monthly → yearly',
              style: PaisaTheme.sora(
                size: 18,
                weight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasYearly
                  ? 'Multiply each monthly plan by 12. Yearly envelopes already set can be kept or overwritten.'
                  : 'Set each yearly plan to monthly × 12 for ${monthlySet.length} categories.',
              style: PaisaTheme.manrope(
                size: 13,
                color: PaisaColors.mutedCaption,
              ),
            ),
            const SizedBox(height: 18),
            if (hasYearly) ...[
              FilledButton(
                onPressed: () => Navigator.pop(ctx, 'fill'),
                style: FilledButton.styleFrom(
                  backgroundColor: PaisaColors.primary,
                  foregroundColor: PaisaColors.inkOnAccent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(
                  'Fill empty yearly only',
                  style: PaisaTheme.sora(
                    size: 13,
                    weight: FontWeight.w800,
                    color: PaisaColors.inkOnAccent,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.pop(ctx, 'overwrite'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: PaisaColors.ink,
                  side: const BorderSide(color: PaisaColors.border),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(
                  'Overwrite all yearly',
                  style: PaisaTheme.sora(size: 13, weight: FontWeight.w700),
                ),
              ),
            ] else
              FilledButton(
                onPressed: () => Navigator.pop(ctx, 'overwrite'),
                style: FilledButton.styleFrom(
                  backgroundColor: PaisaColors.primary,
                  foregroundColor: PaisaColors.inkOnAccent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(
                  'Copy ×12',
                  style: PaisaTheme.sora(
                    size: 13,
                    weight: FontWeight.w800,
                    color: PaisaColors.inkOnAccent,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: PaisaTheme.manrope(
                  size: 13,
                  weight: FontWeight.w600,
                  color: PaisaColors.mutedCaption,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  if (confirmed == null || !context.mounted) return;
  final written = await store.copyMonthlyPlansToYearly(
    overwrite: confirmed == 'overwrite',
  );
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        written == 0
            ? 'No yearly plans updated'
            : 'Updated $written yearly plan${written == 1 ? '' : 's'}',
      ),
    ),
  );
}

Future<void> _confirmResetActivePlans(
  BuildContext context,
  FinanceStore store,
  BudgetPeriod period,
) async {
  final yearly = period == BudgetPeriod.yearly;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: PaisaColors.card,
      title: Text(
        yearly ? 'Reset yearly plans?' : 'Reset monthly plans?',
        style: PaisaTheme.sora(size: 17, weight: FontWeight.w800),
      ),
      content: Text(
        yearly
            ? 'Clear every yearly envelope. Monthly plans stay as they are.'
            : 'Clear every monthly envelope. Yearly plans stay as they are.',
        style: PaisaTheme.manrope(size: 13.5, color: PaisaColors.mutedCaption),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(
            'Cancel',
            style: PaisaTheme.manrope(
              size: 13,
              weight: FontWeight.w600,
              color: PaisaColors.mutedCaption,
            ),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            'Reset',
            style: PaisaTheme.sora(
              size: 13,
              weight: FontWeight.w800,
              color: PaisaColors.overBudget,
            ),
          ),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  await store.clearAllBudgetLimits(period: period);
}

// ── Edit plan sheet ─────────────────────────────────────────────────────────

Future<void> _editBudgetLimit(
  BuildContext context,
  FinanceStore store,
  Budget budget,
  BudgetPeriod period,
) async {
  final controller = TextEditingController(
    text: budget.limit > 0 || budget.hasStoredPlan
        ? budget.limit.round().toString()
        : '',
  );
  final suggested =
      store.suggestedBudgetLimit(budget.category, period: period);
  final info = budget.info;
  final yearly = period == BudgetPeriod.yearly;

  final saved = await showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    backgroundColor: PaisaColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) {
      final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
      return Padding(
        padding: EdgeInsets.fromLTRB(22, 16, 22, 18 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: PaisaColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              yearly
                  ? '${info.label} yearly plan'
                  : '${info.label} monthly plan',
              style: PaisaTheme.sora(
                size: 18,
                weight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              yearly
                  ? 'How much do you want to spend on ${info.label.toLowerCase()} this year? (Separate from your monthly plan.)'
                  : 'How much do you want to spend on ${info.label.toLowerCase()} this month?',
              style: PaisaTheme.manrope(
                size: 13,
                color: PaisaColors.mutedCaption,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
              ],
              autofocus: true,
              style: PaisaTheme.sora(
                size: 22,
                weight: FontWeight.w800,
              ),
              decoration: InputDecoration(
                prefixText: '₹ ',
                prefixStyle: PaisaTheme.sora(
                  size: 22,
                  weight: FontWeight.w800,
                  color: PaisaColors.mutedCaption,
                ),
                hintText: '0',
                hintStyle: PaisaTheme.sora(
                  size: 22,
                  weight: FontWeight.w700,
                  color: PaisaColors.muted,
                ),
                filled: true,
                fillColor: PaisaColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: PaisaColors.border,
                    width: 1.4,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: PaisaColors.border,
                    width: 1.4,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: PaisaColors.primary,
                    width: 1.6,
                  ),
                ),
              ),
            ),
            if (suggested >= 1000) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () {
                    controller.text = suggested.round().toString();
                  },
                  child: Text(
                    'Hint from history · ${formatInr(suggested)}',
                    style: PaisaTheme.manrope(
                      size: 12,
                      weight: FontWeight.w600,
                      color: PaisaColors.primary,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: PaisaColors.ink,
                      side: const BorderSide(color: PaisaColors.border),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      'Cancel',
                      style: PaisaTheme.sora(
                        size: 13,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      final raw = controller.text.replaceAll(',', '').trim();
                      if (raw.isEmpty) {
                        Navigator.pop(ctx, 0.0);
                        return;
                      }
                      final parsed = double.tryParse(raw);
                      if (parsed == null || parsed < 0) return;
                      Navigator.pop(ctx, parsed);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: PaisaColors.primary,
                      foregroundColor: PaisaColors.inkOnAccent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      yearly ? 'Save year plan' : 'Save plan',
                      style: PaisaTheme.sora(
                        size: 13,
                        weight: FontWeight.w800,
                        color: PaisaColors.inkOnAccent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
  controller.dispose();
  if (saved != null) {
    await store.setCategoryBudgetLimit(
      budget.category,
      saved,
      period: period,
    );
  }
}
