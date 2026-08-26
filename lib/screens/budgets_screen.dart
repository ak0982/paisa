import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/budget.dart';
import '../providers/finance_store.dart';
import '../theme/paisa_colors.dart';
import '../theme/paisa_theme.dart';
import '../utils/formatters.dart';
import '../widgets/paisa_progress_bar.dart';
import '../widgets/paisa_nav_chevron.dart';

class BudgetsScreen extends StatelessWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<FinanceStore>(
      builder: (context, store, _) {
        final budgets = store.budgets;
        final left = store.totalBudget - store.budgetSpent;
        final ratio = store.totalBudget > 0
            ? store.budgetSpent / store.totalBudget
            : 0.0;
        final daysLeft =
            DateTime(DateTime.now().year, DateTime.now().month + 1, 0).day -
                DateTime.now().day;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Budgets',
                    style: PaisaTheme.sora(
                      size: 22,
                      weight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  Text(
                    store.currentMonthLabel,
                    style: PaisaTheme.manrope(
                      size: 12,
                      weight: FontWeight.w600,
                      color: PaisaColors.mutedLight,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (budgets.isEmpty)
                _EmptyBudgets(onSync: store.syncFromSms)
              else ...[
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
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'SPENT SO FAR',
                                  style: PaisaTheme.manrope(
                                    size: 10.5,
                                    weight: FontWeight.w700,
                                    color: PaisaColors.inkOnAccent,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                Text(
                                  formatInr(store.budgetSpent),
                                  style: PaisaTheme.sora(
                                    size: 30,
                                    weight: FontWeight.w800,
                                    color: PaisaColors.inkOnAccent,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'BUDGET',
                                style: PaisaTheme.manrope(
                                  size: 9,
                                  weight: FontWeight.w700,
                                  color: PaisaColors.inkOnAccent
                                      .withOpacity(0.7),
                                  letterSpacing: 1,
                                ),
                              ),
                              Text(
                                formatInr(store.totalBudget),
                                style: PaisaTheme.sora(
                                  size: 17,
                                  weight: FontWeight.w800,
                                  color: PaisaColors.inkOnAccent,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      PaisaProgressBar(
                        progress: ratio,
                        color: PaisaColors.inkOnAccent,
                        height: 9,
                        trackColor: PaisaColors.inkOnAccent.withOpacity(0.22),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        '${formatInr(left.clamp(0, double.infinity))} left · $daysLeft days to go',
                        style: PaisaTheme.manrope(
                          size: 12,
                          weight: FontWeight.w600,
                          color: PaisaColors.inkOnAccent.withOpacity(0.85),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'By category',
                  style: PaisaTheme.sora(size: 14, weight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                ...budgets.map((budget) {
                  final info = budget.info;
                  return Semantics(
                    button: true,
                    label: 'Edit ${info.label} budget',
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => _editBudgetLimit(context, store, budget),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 11),
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                          decoration: BoxDecoration(
                            color: PaisaColors.card,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: PaisaColors.border,
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: info.tintBg,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: PaisaColors.inkOnAccent,
                                        width: 2,
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(info.emoji,
                                        style: const TextStyle(fontSize: 17)),
                                  ),
                                  const SizedBox(width: 11),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          info.label,
                                          style: PaisaTheme.manrope(
                                            size: 13.5,
                                            weight: FontWeight.w700,
                                          ),
                                        ),
                                        Text(
                                          budget.statusLabel,
                                          style: PaisaTheme.manrope(
                                            size: 11,
                                            color: budget.statusColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  RichText(
                                    text: TextSpan(
                                      children: [
                                        TextSpan(
                                          text: formatInr(budget.spent),
                                          style: PaisaTheme.sora(
                                            size: 14,
                                            weight: FontWeight.w700,
                                          ),
                                        ),
                                        TextSpan(
                                          text: ' / ${formatInr(budget.limit)}',
                                          style: PaisaTheme.manrope(
                                            size: 11.5,
                                            weight: FontWeight.w600,
                                            color: PaisaColors.navInactive,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  const PaisaNavChevron(),
                                ],
                              ),
                              const SizedBox(height: 12),
                              PaisaProgressBar(
                                progress: budget.ratio.clamp(0.0, 1.0),
                                color: budget.barColor,
                                height: 7,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ],
          ),
        );
      },
    );
  }
}

Future<void> _editBudgetLimit(
  BuildContext context,
  FinanceStore store,
  Budget budget,
) async {
  final controller = TextEditingController(
    text: budget.limit.round().toString(),
  );
  final saved = await showDialog<double>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Monthly ${budget.info.label} budget'),
      content: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          prefixText: '₹ ',
          hintText: 'e.g. 5000',
        ),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final parsed = double.tryParse(
              controller.text.replaceAll(',', '').trim(),
            );
            if (parsed == null || parsed <= 0) return;
            Navigator.pop(ctx, parsed);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (saved != null) {
    await store.setCategoryBudgetLimit(budget.category, saved);
  }
}

class _EmptyBudgets extends StatelessWidget {
  const _EmptyBudgets({required this.onSync});

  final Future<ScanResult> Function() onSync;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: PaisaColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: PaisaColors.dividerAlt),
      ),
      child: Column(
        children: [
          const Text('📊', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 12),
          Text(
            'No spending data yet',
            style: PaisaTheme.sora(size: 16, weight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Scan your SMS inbox to auto-build budgets from real transactions.',
            textAlign: TextAlign.center,
            style: PaisaTheme.manrope(size: 13, color: PaisaColors.muted),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onSync,
            style: FilledButton.styleFrom(
              backgroundColor: PaisaColors.primary,
              foregroundColor: PaisaColors.inkOnAccent,
            ),
            child: Text(
              'SCAN SMS',
              style: PaisaTheme.sora(
                size: 13,
                weight: FontWeight.w800,
                color: PaisaColors.inkOnAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
