import 'package:flutter_test/flutter_test.dart';

import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/providers/finance_store.dart';
import 'package:paisa_app/services/sms/account_discovery.dart';

import 'helpers/dummy_data.dart';

void main() {
  group('U36-U43 FinanceStore settings integration', () {
    test('U36 seedTransactions populates bank accounts', () {
      final store = FinanceStore();
      store.seedTransactions(dummyTransactionHistory());
      expect(store.bankAccounts().length, greaterThan(0));
      expect(store.transactions.length, 14);
    });

    test('U37 seedTransactions computes monthly spent', () {
      final store = FinanceStore();
      store.seedTransactions(dummyTransactionHistory());
      expect(store.monthlySpent, greaterThan(0));
    });

    test('U38 seedTransactions computes monthly income', () {
      final store = FinanceStore();
      store.seedTransactions(dummyTransactionHistory());
      expect(store.monthlyIncome, greaterThan(0));
    });

    test('U39 empty store has no bank accounts', () {
      final store = FinanceStore();
      store.seedTransactions([]);
      expect(store.bankAccounts(), isEmpty);
    });

    test('U40 empty store monthly spent is zero', () {
      final store = FinanceStore();
      store.seedTransactions([]);
      expect(store.monthlySpent, 0);
    });

    test('U41 empty store savings rate is zero', () {
      final store = FinanceStore();
      store.seedTransactions([]);
      expect(store.savingsRate, 0);
    });

    test('U42 buildReport on seeded data is not empty', () {
      final store = FinanceStore();
      store.seedTransactions(dummyTransactionHistory());
      final report = store.buildReport(
        DateTime(2026, 7, 1),
        DateTime(2026, 7, 31, 23, 59, 59),
      );
      expect(report.isEmpty, isFalse);
      expect(report.transactionCount, greaterThan(0));
    });

    test('U43 topMerchants returns ranked list', () {
      final store = FinanceStore();
      store.seedTransactions(dummyTransactionHistory());
      final merchants = store.topMerchants;
      expect(merchants, isNotEmpty);
      if (merchants.length >= 2) {
        expect(merchants[0].$3, greaterThanOrEqualTo(merchants[1].$3));
      }
    });
  });

  group('U44-U45 Refresh re-entrancy guard', () {
    test('U44 concurrent syncFromSms returns the same in-flight future', () {
      final store = FinanceStore();
      final first = store.syncFromSms();
      final second = store.syncFromSms();
      expect(identical(first, second), isTrue);
      return Future.wait([first, second]);
    });

    test('U45 syncFromSms can run again after completing', () async {
      final store = FinanceStore();
      final first = store.syncFromSms();
      await first;
      final second = store.syncFromSms();
      expect(identical(first, second), isFalse);
      await second;
    });
  });

  group('U58-U61 Home uses current calendar month', () {
    test('U58 Home stays on current month when it is empty', () {
      final now = DateTime.now();
      final store = FinanceStore();
      store.seedTransactions([
        dummyTxn(
          id: 'a',
          merchant: 'Shop',
          amount: 500,
          isCredit: false,
          timestamp: DateTime(2020, 3, 10),
        ),
        dummyTxn(
          id: 'b',
          merchant: 'Salary',
          amount: 20000,
          isCredit: true,
          timestamp: DateTime(2020, 3, 1),
        ),
        dummyTxn(
          id: 'c',
          merchant: 'Old',
          amount: 100,
          isCredit: false,
          timestamp: DateTime(2020, 1, 5),
        ),
      ]);

      expect(store.currentMonth, DateTime(now.year, now.month));
      expect(store.monthlySpent, 0);
      expect(store.monthlyIncome, 0);
      expect(store.activeMonth, DateTime(2020, 3));
      expect(store.isViewingHistoricalMonth, isFalse);
    });

    test('U59 uses current month when it has data', () {
      final now = DateTime.now();
      final store = FinanceStore();
      store.seedTransactions([
        dummyTxn(
          id: 'cur',
          merchant: 'Now',
          amount: 300,
          isCredit: false,
          timestamp: DateTime(now.year, now.month, 1, 9),
        ),
        dummyTxn(
          id: 'old',
          merchant: 'Old',
          amount: 999,
          isCredit: false,
          timestamp: DateTime(2020, 1, 5),
        ),
      ]);

      expect(store.currentMonth.year, now.year);
      expect(store.currentMonth.month, now.month);
      expect(store.activeMonth.year, now.year);
      expect(store.activeMonth.month, now.month);
      expect(store.monthlySpent, 300);
    });

    test('U60 empty store current month is calendar month', () {
      final now = DateTime.now();
      final store = FinanceStore();
      store.seedTransactions([]);
      expect(store.currentMonth.year, now.year);
      expect(store.currentMonth.month, now.month);
      expect(store.activeMonth.year, now.year);
      expect(store.activeMonth.month, now.month);
    });

    test('U61 monthlySpent is zero when only past data exists', () {
      final store = FinanceStore();
      store.seedTransactions([
        dummyTxn(
          id: 'p1',
          merchant: 'Store',
          amount: 1500,
          isCredit: false,
          timestamp: DateTime(2019, 8, 12),
        ),
      ]);
      expect(store.monthlySpent, 0);
      expect(store.currentMonthTransactions, isEmpty);
    });

    test('U61b insights uses rolling 12-month window', () {
      final store = FinanceStore();
      final now = DateTime.now();
      store.seedTransactions([
        dummyTxn(
          id: 'old',
          merchant: 'IRCTC',
          amount: 5000,
          isCredit: false,
          category: SpendCategory.travel,
          timestamp: now.subtract(const Duration(days: 200)),
        ),
        dummyTxn(
          id: 'recent',
          merchant: 'Swiggy',
          amount: 300,
          isCredit: false,
          category: SpendCategory.food,
          timestamp: now.subtract(const Duration(days: 10)),
        ),
      ]);

      expect(store.insightsSpent, 5300);
      expect(store.insightsCategorySpending[SpendCategory.travel], 5000);
      expect(store.insightsCategorySpending[SpendCategory.food], 300);
      expect(store.insightsTopMerchants.first.$1, 'IRCTC');
    });

    test('U61c Home keeps current month when only credits this month', () {
      final now = DateTime.now();
      final store = FinanceStore();
      store.seedTransactions([
        dummyTxn(
          id: 'salary',
          merchant: 'Salary',
          amount: 50000,
          isCredit: true,
          timestamp: DateTime(now.year, now.month, 2),
        ),
        dummyTxn(
          id: 'oldspend',
          merchant: 'Amazon',
          amount: 1200,
          isCredit: false,
          timestamp: DateTime(now.year, now.month - 1, 15),
        ),
      ]);

      expect(store.currentMonth.month, now.month);
      expect(store.monthlySpent, 0);
      expect(store.monthlyIncome, 50000);
      expect(store.activeMonth.month, now.month - 1);
    });

    test('U61d todayTransactions filters to local calendar day', () {
      final now = DateTime.now();
      final store = FinanceStore();
      store.seedTransactions([
        dummyTxn(
          id: 'today',
          merchant: 'Cafe',
          amount: 220,
          isCredit: false,
          timestamp: DateTime(now.year, now.month, now.day, 10, 30),
        ),
        dummyTxn(
          id: 'yesterday',
          merchant: 'Shop',
          amount: 500,
          isCredit: false,
          timestamp: DateTime(now.year, now.month, now.day)
              .subtract(const Duration(days: 1))
              .add(const Duration(hours: 18)),
        ),
      ]);

      expect(store.todayTransactions.length, 1);
      expect(store.todayTransactions.first.id, 'today');
      expect(store.earlierThisMonthTransactions.any((t) => t.id == 'today'),
          isFalse);
    });

    test('U61e Home includes transfers in spend totals', () {
      final now = DateTime.now();
      final store = FinanceStore();
      store.seedTransactions([
        dummyTxn(
          id: 'xfer',
          merchant: 'Innofin Solution',
          amount: 3500,
          isCredit: false,
          category: SpendCategory.transfer,
          timestamp: DateTime(now.year, now.month, now.day, 9),
        ),
        dummyTxn(
          id: 'income',
          merchant: 'Borrower repayment',
          amount: 2700,
          isCredit: true,
          category: SpendCategory.income,
          timestamp: DateTime(now.year, now.month, now.day, 18)
              .subtract(const Duration(days: 1)),
        ),
        dummyTxn(
          id: 'past',
          merchant: 'Swiggy',
          amount: 400,
          isCredit: false,
          category: SpendCategory.food,
          timestamp: DateTime(now.year, now.month - 1, 20),
        ),
      ]);

      expect(store.monthlySpent, 3500);
      expect(store.monthlyIncome, 2700);
      expect(store.homeTodayTransactions.length, 1);
      expect(store.homeTodayTransactions.first.id, 'xfer');
      expect(store.homeMonthTransactions.length, 2);
      expect(store.currentMonthHasOnlyTransfers, isFalse);
      expect(store.activeMonthTransactionCount, 2);
      expect(store.recentSpendingOutsideCurrentMonth().first.id, 'past');
    });

    test('U61f transfer-only current month counts as spending', () {
      final now = DateTime.now();
      final store = FinanceStore();
      store.seedTransactions([
        dummyTxn(
          id: 'xfer',
          merchant: 'Wallet top-up',
          amount: 1500,
          isCredit: false,
          category: SpendCategory.transfer,
          timestamp: DateTime(now.year, now.month, 3),
        ),
        dummyTxn(
          id: 'old',
          merchant: 'Amazon',
          amount: 999,
          isCredit: false,
          category: SpendCategory.shopping,
          timestamp: DateTime(now.year, now.month - 1, 12),
        ),
      ]);

      expect(store.monthlySpent, 1500);
      expect(store.homeMonthTransactions.length, 1);
      expect(store.homeMonthTransactions.first.id, 'xfer');
      expect(store.currentMonthHasOnlyTransfers, isFalse);
      expect(store.recentSpendingOutsideCurrentMonth().map((t) => t.id), ['old']);
    });

    test('U61g self-transfer both legs shown on Home but netted from KPIs '
        '(ISSUE-4)', () {
      final now = DateTime.now();
      final store = FinanceStore();
      store.seedTransactions([
        dummyTxn(
          id: 'sbi-out',
          merchant: 'Transfer',
          amount: 5000,
          isCredit: false,
          bank: 'SBI',
          maskedAccount: '••••0429',
          category: SpendCategory.transfer,
          timestamp: DateTime(now.year, now.month, now.day, 10),
        ),
        dummyTxn(
          id: 'axis-in',
          merchant: 'Money received',
          amount: 5000,
          isCredit: true,
          bank: 'Axis',
          maskedAccount: '••••9867',
          category: SpendCategory.income,
          timestamp: DateTime(now.year, now.month, now.day, 10, 1),
        ),
      ]);

      // ISSUE-4: a self-transfer between the user's own accounts is internal
      // movement, so both legs net out of the headline spend/income KPIs...
      expect(store.monthlySpent, 0);
      expect(store.monthlyIncome, 0);
      // ...but the underlying rows are still visible in the Home lists.
      expect(store.homeMonthTransactions.length, 2);
      expect(store.homeTodayTransactions.length, 2);
    });

    test('U61h Home income excludes credit-card payment credits (ISSUE-4)', () {
      final now = DateTime.now();
      final store = FinanceStore();
      store.seedTransactions([
        dummyTxn(
          id: 'cc-in',
          merchant: 'Credit card payment',
          amount: 12000,
          isCredit: true,
          bank: 'SBI',
          maskedAccount: '••••3452',
          category: SpendCategory.transfer,
          accountKind: AccountKind.creditCard,
          timestamp: DateTime(now.year, now.month, 5),
        ),
        dummyTxn(
          id: 'salary',
          merchant: 'Salary',
          amount: 80000,
          isCredit: true,
          timestamp: DateTime(now.year, now.month, 1),
        ),
      ]);

      // ISSUE-4: a credit landing on a credit-card account is a bill payment
      // (internal movement), not real income — only the salary counts.
      expect(store.monthlyIncome, 80000);
    });


    test('U62 bankAccounts include savings with received and sent totals', () {
      final store = FinanceStore();
      final ts = DateTime(2026, 6, 10);
      store.seedTransactions([
        dummyTxn(
          id: 'h1',
          merchant: 'Salary',
          amount: 50000,
          isCredit: true,
          bank: 'HDFC',
          maskedAccount: '••••5300',
          timestamp: ts,
        ),
        dummyTxn(
          id: 'h2',
          merchant: 'Swiggy',
          amount: 500,
          isCredit: false,
          bank: 'HDFC',
          maskedAccount: '••••5300',
          timestamp: ts.add(const Duration(days: 1)),
        ),
        dummyTxn(
          id: 's1',
          merchant: 'LenDen Repayment',
          amount: 2602,
          isCredit: true,
          bank: 'SBI',
          maskedAccount: '••••0429',
          category: SpendCategory.income,
          timestamp: ts,
        ),
        dummyTxn(
          id: 's2',
          merchant: 'Transfer',
          amount: 1000,
          isCredit: false,
          bank: 'SBI',
          maskedAccount: '••••0429',
          timestamp: ts.add(const Duration(days: 2)),
        ),
      ]);

      final accounts = store.bankAccounts();
      expect(accounts.length, 2);
      final hdfc = accounts.firstWhere((a) => a.mask == '••••5300');
      expect(hdfc.receivedTotal, 50000);
      expect(hdfc.spentTotal, 500);
    });

    test('U63 hidden masks are excluded from bank accounts', () {
      final store = FinanceStore();
      final ts = DateTime(2026, 6, 10);
      store.seedTransactions([
        dummyTxn(
          id: 'a1',
          merchant: 'Salary',
          amount: 50000,
          isCredit: true,
          timestamp: ts,
        ),
        dummyTxn(
          id: 'a2',
          merchant: 'Bonus',
          amount: 10000,
          isCredit: true,
          timestamp: ts.add(const Duration(days: 1)),
        ),
      ]);

      expect(store.bankAccounts().length, 1);
      expect(
        store.bankAccounts(hiddenMasks: {'••••4321'}),
        isEmpty,
      );
    });
  });
}
