import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/category_info.dart';
import '../providers/finance_store.dart';
import '../models/transaction.dart';
import '../models/transaction_sort.dart';
import '../services/sms/account_discovery.dart';
import '../theme/paisa_colors.dart';
import '../theme/paisa_theme.dart';
import '../utils/formatters.dart';
import '../widgets/grouped_transaction_list.dart';
import '../widgets/transaction_sort_control.dart';

enum _FlowFilter { all, incoming, outgoing, creditCard, loan }

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  String _query = '';
  _FlowFilter _flow = _FlowFilter.all;
  TransactionSort _sort = TransactionSort.defaultSort;

  bool _isLoanTransaction(Transaction t) {
    return t.accountKind == AccountKind.loan ||
        (t.category == SpendCategory.emi && !t.isCredit);
  }

  bool _isCreditCardTransaction(Transaction t) {
    if (t.accountKind == AccountKind.creditCard) return true;
    final m = t.merchant.toLowerCase();
    return m.contains('ccbp') ||
        m.contains('credit card bill') ||
        m.contains('credit card payment') ||
        m.contains('bobcard');
  }

  bool _matchesFlow(Transaction t) {
    return switch (_flow) {
      _FlowFilter.all => true,
      _FlowFilter.incoming =>
        t.isCredit && t.accountKind == AccountKind.savings,
      _FlowFilter.outgoing =>
        !t.isCredit && t.accountKind == AccountKind.savings,
      _FlowFilter.creditCard => _isCreditCardTransaction(t),
      _FlowFilter.loan => _isLoanTransaction(t),
    };
  }

  /// Applies flow + search filters. Ordering is handled separately via [_sort]
  /// so sorting always composes with the active filters instead of resetting.
  List<Transaction> _filtered(FinanceStore store) {
    return store.transactions.where((t) {
      if (!_matchesFlow(t)) return false;
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return t.merchant.toLowerCase().contains(q) ||
          t.flowLabel.toLowerCase().contains(q) ||
          t.accountLine.toLowerCase().contains(q) ||
          t.categoryInfo.label.toLowerCase().contains(q) ||
          t.amount.toString().contains(q);
    }).toList();
  }

  ({double moneyIn, double moneyOut, double ccIn, double ccOut, double ccBillPaid, double loanPaid})
      _summary(List<Transaction> list) {
    var moneyIn = 0.0;
    var moneyOut = 0.0;
    var ccIn = 0.0;
    var ccOut = 0.0;
    var ccBillPaid = 0.0;
    var loanPaid = 0.0;

    for (final t in list) {
      if (_isCreditCardTransaction(t)) {
        if (t.isCredit) {
          ccIn += t.amount;
        } else if (t.isCreditCardBillPayment) {
          ccBillPaid += t.amount;
        } else {
          ccOut += t.amount;
        }
        continue;
      }
      if (_isLoanTransaction(t)) {
        if (!t.isCredit) loanPaid += t.amount;
        continue;
      }
      switch (t.accountKind) {
        case AccountKind.savings:
          if (t.isCredit) {
            if (t.countsTowardIncome) moneyIn += t.amount;
          } else {
            moneyOut += t.amount;
          }
        case AccountKind.creditCard:
          if (t.isCredit) {
            ccIn += t.amount;
          } else {
            ccOut += t.amount;
          }
        case AccountKind.loan:
          if (!t.isCredit) loanPaid += t.amount;
      }
    }

    return (
      moneyIn: moneyIn,
      moneyOut: moneyOut,
      ccIn: ccIn,
      ccOut: ccOut,
      ccBillPaid: ccBillPaid,
      loanPaid: loanPaid,
    );
  }

  double _ccBillsPaidForDisplay(
    ({double ccIn, double ccBillPaid, double ccOut, double loanPaid, double moneyIn, double moneyOut}) summary,
  ) =>
      summary.ccBillPaid > 0 ? summary.ccBillPaid : summary.ccIn;

  Future<void> _handleSync(BuildContext context, FinanceStore store) async {
    if (store.isLoading) return;
    final messenger = ScaffoldMessenger.of(context);
    final result = await store.syncFromSms();
    if (!context.mounted) return;

    if (store.error != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(store.error!),
          behavior: SnackBarBehavior.floating,
          backgroundColor: PaisaColors.overBudget,
        ),
      );
      return;
    }

    final message = result.newCount > 0
        ? 'Added ${result.newCount} new · ${result.totalCount} total'
        : 'Up to date · ${result.totalCount} transactions';

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
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
    return Consumer<FinanceStore>(
      builder: (context, store, _) {
        final filtered = _filtered(store);
        final sections = buildTransactionSections(filtered, _sort);
        final summary = _summary(filtered);

        return Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Transactions',
                            style: PaisaTheme.sora(
                              size: 22,
                              weight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${filtered.length} shown',
                                style: PaisaTheme.manrope(
                                  size: 12,
                                  weight: FontWeight.w600,
                                  color: PaisaColors.mutedLight,
                                ),
                              ),
                              const SizedBox(width: 10),
                              TransactionSortControl(
                                sort: _sort,
                                onChanged: (value) =>
                                    setState(() => _sort = value),
                              ),
                            ],
                          ),
                        ],
                      ),
                      if (filtered.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _SummaryStrip(
                          summary: summary,
                          flow: _flow,
                          ccBillsPaid: _ccBillsPaidForDisplay(summary),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Container(
                        height: 46,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: PaisaColors.card,
                          border: Border.all(color: PaisaColors.border),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.search,
                              size: 18,
                              color: PaisaColors.navInactive,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                onChanged: (v) => setState(() => _query = v),
                                decoration: InputDecoration(
                                  hintText:
                                      'Search merchant, account, amount',
                                  hintStyle: PaisaTheme.manrope(
                                    size: 13.5,
                                    color: PaisaColors.navInactive,
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                                style: PaisaTheme.manrope(size: 13.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    children: [
                      _FilterChip(
                        label: 'All',
                        active: _flow == _FlowFilter.all,
                        onTap: () => setState(() => _flow = _FlowFilter.all),
                      ),
                      _FilterChip(
                        label: 'Money in',
                        active: _flow == _FlowFilter.incoming,
                        onTap: () =>
                            setState(() => _flow = _FlowFilter.incoming),
                      ),
                      _FilterChip(
                        label: 'Money out',
                        active: _flow == _FlowFilter.outgoing,
                        onTap: () =>
                            setState(() => _flow = _FlowFilter.outgoing),
                      ),
                      _FilterChip(
                        label: 'Credit card',
                        active: _flow == _FlowFilter.creditCard,
                        onTap: () =>
                            setState(() => _flow = _FlowFilter.creditCard),
                      ),
                      _FilterChip(
                        label: 'Loans',
                        active: _flow == _FlowFilter.loan,
                        onTap: () => setState(() => _flow = _FlowFilter.loan),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: filtered.isEmpty
                      ? _EmptyState(error: store.error)
                      : ListView.builder(
                          padding:
                              const EdgeInsets.fromLTRB(22, 0, 22, 100),
                          itemCount: sections.length,
                          itemBuilder: (context, index) =>
                              TransactionSectionCard(section: sections[index]),
                        ),
                ),
              ],
            ),
            Positioned(
              right: 20,
              bottom: 20,
              child: FloatingActionButton(
                onPressed: store.isLoading
                    ? null
                    : () => _handleSync(context, store),
                elevation: 0,
                backgroundColor: Colors.transparent,
                child: Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: PaisaColors.primary,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: PaisaColors.inkOnAccent,
                      width: 2.5,
                    ),
                    boxShadow: PaisaColors.hardShadow(offset: 4),
                  ),
                  child: store.isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: PaisaColors.inkOnAccent,
                          ),
                        )
                      : const Icon(
                          Icons.sync,
                          color: PaisaColors.inkOnAccent,
                          size: 24,
                        ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({
    required this.summary,
    required this.flow,
    required this.ccBillsPaid,
  });

  final ({
    double moneyIn,
    double moneyOut,
    double ccIn,
    double ccOut,
    double ccBillPaid,
    double loanPaid,
  }) summary;
  final _FlowFilter flow;
  final double ccBillsPaid;

  @override
  Widget build(BuildContext context) {
    final items = <({String label, double amount, bool isCredit})>[];

    switch (flow) {
      case _FlowFilter.all:
        if (summary.moneyIn > 0) {
          items.add((label: 'In', amount: summary.moneyIn, isCredit: true));
        }
        if (summary.moneyOut > 0) {
          items.add((label: 'Out', amount: summary.moneyOut, isCredit: false));
        }
      case _FlowFilter.incoming:
        if (summary.moneyIn > 0) {
          items.add((label: 'Money in', amount: summary.moneyIn, isCredit: true));
        }
      case _FlowFilter.outgoing:
        if (summary.moneyOut > 0) {
          items.add((label: 'Money out', amount: summary.moneyOut, isCredit: false));
        }
      case _FlowFilter.creditCard:
        if (summary.ccOut > 0) {
          items.add((label: 'CC spend', amount: summary.ccOut, isCredit: false));
        }
        if (ccBillsPaid > 0) {
          items.add(
            (label: 'CC bills paid', amount: ccBillsPaid, isCredit: false),
          );
        }
      case _FlowFilter.loan:
        if (summary.loanPaid > 0) {
          items.add(
            (label: 'Loan paid', amount: summary.loanPaid, isCredit: false),
          );
        }
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: items.map((item) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: PaisaColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: PaisaColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.label,
                style: PaisaTheme.manrope(
                  size: 11,
                  weight: FontWeight.w600,
                  color: PaisaColors.mutedCaption,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                formatAmount(item.amount, isCredit: item.isCredit),
                style: PaisaTheme.sora(
                  size: 11.5,
                  weight: FontWeight.w700,
                  color: item.isCredit ? PaisaColors.credit : PaisaColors.ink,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
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
              size: 11.5,
              weight: FontWeight.w700,
              color: active ? PaisaColors.inkOnAccent : PaisaColors.mutedCaption,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.error});

  final String? error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('📭', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text(
              error ?? 'No transactions yet',
              style: PaisaTheme.sora(size: 18, weight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap sync for new bank SMS. For a full rebuild after updates, use Profile → Rescan SMS.',
              textAlign: TextAlign.center,
              style: PaisaTheme.manrope(
                size: 13,
                color: PaisaColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
