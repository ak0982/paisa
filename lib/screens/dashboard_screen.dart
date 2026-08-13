import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_settings.dart';
import '../providers/finance_store.dart';
import '../models/category_info.dart';
import '../models/transaction.dart';
import 'edit_profile_screen.dart';
import 'category_transactions_screen.dart';
import 'filtered_transactions_screen.dart';
import '../theme/paisa_colors.dart';
import '../theme/paisa_theme.dart';
import '../utils/formatters.dart';
import '../widgets/category_spend_chip.dart';
import '../widgets/neo_surface.dart';
import '../widgets/paisa_progress_bar.dart';
import '../widgets/transaction_row.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  static const _monthPreviewLimit = 8;

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  void _openCurrentMonth(BuildContext context, FinanceStore store) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FilteredTransactionsScreen(
          title: store.currentMonthLabel,
          emoji: '📅',
          tintBg: PaisaColors.primary.withOpacity(0.18),
          totalLabel: 'All activity',
          countSingular: 'transaction',
          countPlural: 'transactions',
          emptyTitle: 'No transactions this month',
          emptySubtitleTemplate: 'Nothing imported for {period} yet.',
          range: store.currentMonthRange,
          periodLabel: store.currentMonthLabel,
          match: store.countsOnHome,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final firstName = settings.firstName;
    final initials = settings.initials;
    return Consumer<FinanceStore>(
      builder: (context, store, _) {
        final today = store.homeTodayTransactions;
        final earlier = store.earlierThisMonthHomeTransactions;
        final monthPreview = earlier.take(_monthPreviewLimit).toList();
        final chips = store.categorySpending.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final hasCashflowThisMonth = store.homeMonthTransactions.isNotEmpty;
        final recentSpend = store.monthlySpent <= 0
            ? store.recentSpendingOutsideCurrentMonth()
            : const <Transaction>[];
        final scanningOrEmpty =
            !hasCashflowThisMonth && store.transactions.isEmpty;

        return RefreshIndicator(
          color: PaisaColors.primary,
          backgroundColor: PaisaColors.cardElevated,
          onRefresh: store.syncFromSms,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _greeting().toUpperCase(),
                          style: PaisaTheme.label(
                            size: 10.5,
                            color: PaisaColors.muted,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$firstName ⚡',
                          style: PaisaTheme.sora(
                            size: 22,
                            weight: FontWeight.w800,
                            letterSpacing: -0.3,
                            color: PaisaColors.ink,
                          ),
                        ),
                      ],
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const EditProfileScreen(),
                          ),
                        );
                      },
                      child: NeoSticker(
                        child: Text(
                          initials,
                          style: PaisaTheme.sora(
                            size: 15,
                            weight: FontWeight.w800,
                            color: PaisaColors.inkOnAccent,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                NeoSurface(
                  color: PaisaColors.primary,
                  borderColor: PaisaColors.inkOnAccent,
                  borderWidth: 2.5,
                  radius: 20,
                  shadow: true,
                  shadowOffset: 5,
                  padding: const EdgeInsets.all(19),
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Spent in ${store.currentMonthLabel}'
                                      .toUpperCase(),
                                  style: PaisaTheme.manrope(
                                    size: 10.5,
                                    weight: FontWeight.w700,
                                    color: PaisaColors.inkOnAccent,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  formatInr(store.monthlySpent),
                                  style: PaisaTheme.sora(
                                    size: 32,
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
                                'INCOME',
                                style: PaisaTheme.manrope(
                                  size: 9,
                                  weight: FontWeight.w700,
                                  color: PaisaColors.inkOnAccent
                                      .withOpacity(0.7),
                                  letterSpacing: 1,
                                ),
                              ),
                              Text(
                                formatInr(store.monthlyIncome),
                                style: PaisaTheme.sora(
                                  size: 18,
                                  weight: FontWeight.w800,
                                  color: PaisaColors.inkOnAccent,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'SAVINGS RATE',
                            style: PaisaTheme.sora(
                              size: 10.5,
                              weight: FontWeight.w700,
                              color: PaisaColors.inkOnAccent,
                              letterSpacing: 1,
                            ),
                          ),
                          Text(
                            '${(store.savingsRate * 100).round()}%',
                            style: PaisaTheme.sora(
                              size: 10.5,
                              weight: FontWeight.w700,
                              color: PaisaColors.inkOnAccent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      PaisaProgressBar(
                        progress: store.savingsRate,
                        color: PaisaColors.inkOnAccent,
                        trackColor: PaisaColors.inkOnAccent.withOpacity(0.2),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${formatInr(store.monthlySaved)} saved · ${store.activeMonthTransactionCount} transactions',
                          style: PaisaTheme.manrope(
                            size: 11,
                            weight: FontWeight.w600,
                            color: PaisaColors.inkOnAccent.withOpacity(0.75),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (chips.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 64,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: chips.length.clamp(0, 6),
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, i) {
                        final info =
                            CategoryInfo.forCategory(chips[i].key);
                        return CategorySpendChip(
                          info: info,
                          amount: chips[i].value,
                          rotate: true,
                          angle: i.isEven ? -0.035 : 0.035,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => CategoryTransactionsScreen(
                                category: chips[i].key,
                                range: store.currentMonthRange,
                                periodLabel: store.currentMonthLabel,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                if (scanningOrEmpty) ...[
                  const SizedBox(height: 16),
                  _EmptyHint(store: store),
                ] else ...[
                  const SizedBox(height: 20),
                  _SectionHeader(
                    title: 'Today',
                    trailing: today.isEmpty
                        ? 'No activity'
                        : '${today.length} · ${_debitTotalLabel(today)}',
                  ),
                  const SizedBox(height: 6),
                  if (today.isEmpty)
                    const _SoftEmpty(
                      message: 'No spending or income today yet.',
                    )
                  else
                    _TxnCard(transactions: today),
                  const SizedBox(height: 18),
                  _SectionHeader(
                    title: 'This month',
                    trailing: hasCashflowThisMonth
                        ? '${store.activeMonthTransactionCount} total'
                        : null,
                    actionLabel: hasCashflowThisMonth ? 'See all' : null,
                    onAction: () => _openCurrentMonth(context, store),
                  ),
                  const SizedBox(height: 6),
                  if (!hasCashflowThisMonth)
                    _SoftEmpty(
                      message:
                          'No spending or income in ${store.shortMonthLabel} yet.',
                    )
                  else if (monthPreview.isEmpty)
                    _SoftEmpty(
                      message: today.isNotEmpty
                          ? 'Everything this month is from today.'
                          : 'No earlier transactions this month.',
                      actionLabel: today.isNotEmpty ? 'See all' : null,
                      onAction: today.isNotEmpty
                          ? () => _openCurrentMonth(context, store)
                          : null,
                    )
                  else
                    _TxnCard(transactions: monthPreview),
                  if (recentSpend.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    const _SectionHeader(
                      title: 'Recent spending',
                      trailing: 'Earlier months',
                    ),
                    const SizedBox(height: 6),
                    _TxnCard(
                      transactions: recentSpend,
                      showDates: true,
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

  static String _debitTotalLabel(List<Transaction> list) {
    final spent = list
        .where((t) => !t.isCredit)
        .fold(0.0, (sum, t) => sum + t.amount);
    if (spent <= 0) {
      final income = list
          .where((t) => t.isCredit)
          .fold(0.0, (sum, t) => sum + t.amount);
      return formatInr(income);
    }
    return formatAmount(spent, isCredit: false);
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.trailing,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? trailing;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Text(
                title,
                style: PaisaTheme.sora(
                  size: 15,
                  weight: FontWeight.w700,
                  color: PaisaColors.ink,
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    trailing!,
                    style: PaisaTheme.manrope(
                      size: 12,
                      weight: FontWeight.w600,
                      color: PaisaColors.muted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (actionLabel != null && onAction != null)
          GestureDetector(
            onTap: onAction,
            child: Text(
              actionLabel!,
              style: PaisaTheme.manrope(
                size: 12,
                weight: FontWeight.w700,
                color: PaisaColors.primary,
              ),
            ),
          ),
      ],
    );
  }
}

class _TxnCard extends StatelessWidget {
  const _TxnCard({
    required this.transactions,
    this.showDates = false,
  });

  final List<Transaction> transactions;
  final bool showDates;

  @override
  Widget build(BuildContext context) {
    return NeoSurface(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      radius: 16,
      borderWidth: 1.5,
      child: Column(
        children: [
          for (var i = 0; i < transactions.length; i++) ...[
            TransactionRow(
              transaction: transactions[i],
              showDate: showDates,
            ),
            if (i < transactions.length - 1)
              const Divider(
                height: 1,
                color: PaisaColors.divider,
              ),
          ],
        ],
      ),
    );
  }
}

class _SoftEmpty extends StatelessWidget {
  const _SoftEmpty({
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return NeoSurface(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      radius: 16,
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: PaisaTheme.manrope(
              size: 13,
              color: PaisaColors.muted,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: onAction,
              child: Text(
                actionLabel!,
                style: PaisaTheme.manrope(
                  size: 13,
                  weight: FontWeight.w700,
                  color: PaisaColors.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.store});

  final FinanceStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store.scanProgressListenable,
      builder: (context, _) => _buildHint(context),
    );
  }

  Widget _buildHint(BuildContext context) {
    final scanning = store.isLoading;
    final denied = store.permissionPermanentlyDenied;
    final progress = store.scanProgress;

    final String headline;
    final String subtitle;
    if (scanning) {
      headline = 'Scanning your SMS…';
      subtitle = progress != null && progress.total > 0
          ? 'Checked ${progress.scanned} of ${progress.total} messages'
          : 'Reading bank alerts on your device.';
    } else if (denied) {
      headline = 'SMS access is off';
      subtitle =
          'Paisa needs SMS access to read bank alerts. Enable it in Settings, then tap Scan.';
    } else if (store.error != null) {
      headline = store.error!;
      subtitle = 'Tap below to try scanning again.';
    } else {
      headline = 'No transactions yet';
      subtitle = 'Tap “Scan SMS now” to import your bank alerts.';
    }

    return NeoSurface(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      radius: 16,
      borderColor: PaisaColors.primary,
      borderWidth: 2,
      child: Column(
        children: [
          Text(scanning ? '🔎' : '📭', style: const TextStyle(fontSize: 32)),
          const SizedBox(height: 8),
          Text(
            headline,
            textAlign: TextAlign.center,
            style: PaisaTheme.sora(
              size: 14,
              weight: FontWeight.w700,
              color: PaisaColors.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: PaisaTheme.manrope(
              size: 12,
              color: PaisaColors.mutedCaption,
            ),
          ),
          const SizedBox(height: 16),
          if (scanning)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: PaisaColors.primary,
                ),
              ),
            )
          else ...[
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
                    side: const BorderSide(
                      color: PaisaColors.primary,
                      width: 2.5,
                    ),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'SCAN SMS NOW',
                  style: PaisaTheme.sora(
                    size: 14,
                    weight: FontWeight.w800,
                    color: PaisaColors.inkOnAccent,
                  ),
                ),
              ),
            ),
            if (denied) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => store.openPermissionSettings(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: PaisaColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(
                      color: PaisaColors.primary,
                      width: 2,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    'OPEN SETTINGS',
                    style: PaisaTheme.sora(
                      size: 14,
                      weight: FontWeight.w800,
                      color: PaisaColors.primary,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
