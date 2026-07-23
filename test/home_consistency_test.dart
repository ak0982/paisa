import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/models/transaction.dart';
import 'package:paisa_app/providers/finance_store.dart';
import 'package:paisa_app/services/sms/account_discovery.dart';

/// Home LISTS still show every real debit and credit in the current calendar
/// month — including both legs of a self-transfer — but the headline KPI totals
/// (spent / income) EXCLUDE internal movement (self-transfer legs, CC bill
/// payments, CC payment-received) so the numbers reflect real money in/out.
/// See ISSUE-4.
void main() {
  Transaction tx({
    required String id,
    required double amount,
    required bool isCredit,
    required DateTime ts,
    required SpendCategory category,
    String merchant = 'Test',
    AccountKind kind = AccountKind.savings,
  }) {
    return Transaction(
      id: id,
      smsId: id,
      merchant: merchant,
      bank: 'SBI',
      maskedAccount: '••••0429',
      category: category,
      amount: amount,
      isCredit: isCredit,
      timestamp: ts,
      accountKind: kind,
    );
  }

  test('Home lists show transfers but KPI totals net out self-transfer legs',
      () {
    final now = DateTime.now();
    // Anchor two items to "today" and two "earlier this month" (noon on the 1st)
    // so the Today / This month split is exercised without midnight edge cases.
    final today = DateTime(now.year, now.month, now.day, 12);
    final earlier = DateTime(now.year, now.month, 1, 12);

    final store = FinanceStore();
    store.seedTransactions([
      // Ordinary current-month spend.
      tx(
        id: 'debit',
        amount: 1200,
        isCredit: false,
        ts: earlier,
        category: SpendCategory.food,
        merchant: 'Swiggy',
      ),
      // Ordinary current-month income.
      tx(
        id: 'credit',
        amount: 50000,
        isCredit: true,
        ts: earlier,
        category: SpendCategory.income,
        merchant: 'Salary',
      ),
      // Self-transfer SBI -> Axis: debit leg out of SBI.
      tx(
        id: 'xfer_out',
        amount: 5000,
        isCredit: false,
        ts: today,
        category: SpendCategory.transfer,
        merchant: 'Axis Transfer',
      ),
      // Self-transfer SBI -> Axis: credit leg into Axis (must be a different
      // real bank+mask — same-account pairs are not self-transfers).
      Transaction(
        id: 'xfer_in',
        smsId: 'xfer_in',
        merchant: 'Self Transfer',
        bank: 'Axis',
        maskedAccount: '••••9867',
        category: SpendCategory.transfer,
        amount: 5000,
        isCredit: true,
        timestamp: today,
        accountKind: AccountKind.savings,
      ),
    ]);

    // Headline KPI totals exclude the self-transfer pair (money moved between
    // your own accounts is not spend or income), so only the real food debit
    // and salary credit count.
    expect(store.monthlySpent, 1200);
    expect(store.monthlyIncome, 50000);

    // Lists still show ALL four rows (the transfer legs are visible with their
    // flowLabel badges) — only the headline math excludes them.
    final month = store.homeMonthTransactions;
    expect(month.length, 4);

    // Today + earlier-this-month partition the month exactly (no dropped rows,
    // no duplicates).
    final today0 = store.homeTodayTransactions;
    final earlier0 = store.earlierThisMonthHomeTransactions;
    expect(today0.length + earlier0.length, month.length);
    final ids = {...today0.map((t) => t.id), ...earlier0.map((t) => t.id)};
    expect(ids, month.map((t) => t.id).toSet());

    // The "See all" screen (current-month range + countsOnHome) matches Home.
    final range = store.currentMonthRange;
    final seeAll = store
        .transactionsInRange(range.start, range.end)
        .where(store.countsOnHome)
        .toList();
    expect(seeAll.length, month.length);
  });

  test('transactions outside the current month never reach Home', () {
    final now = DateTime.now();
    final lastMonth = DateTime(now.year, now.month - 1, 15, 12);

    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'old_debit',
          amount: 9999,
          isCredit: false,
          ts: lastMonth,
          category: SpendCategory.shopping,
        ),
      ]);

    expect(store.monthlySpent, 0);
    expect(store.monthlyIncome, 0);
    expect(store.homeMonthTransactions, isEmpty);
  });
}
