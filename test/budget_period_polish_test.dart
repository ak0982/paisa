import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/data/transaction_database.dart';
import 'package:paisa_app/models/budget.dart';
import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/models/transaction.dart' as models;
import 'package:paisa_app/providers/finance_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Polish / period / hero / clear-rescan contracts for Budget envelopes.
void main() {
  late Directory tmp;
  var seq = 0;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('paisa_budget_polish');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  TransactionDatabase freshDb() => TransactionDatabase.forTesting(
        '${tmp.path}/paisa_${seq++}.db',
      );

  FinanceStore freshStore(TransactionDatabase db) => FinanceStore(database: db);

  final now = DateTime.now();
  final thisMonth = DateTime(now.year, now.month, now.day, 12);
  final earlierThisMonth = now.day > 1
      ? DateTime(now.year, now.month, now.day - 1, 12)
      : thisMonth;
  final earlierThisYear = DateTime(now.year, 1, 15, 12);

  models.Transaction debit({
    required String id,
    required SpendCategory category,
    required double amount,
    required DateTime at,
    String merchant = 'Merchant',
  }) =>
      models.Transaction(
        id: id,
        smsId: id,
        merchant: merchant,
        bank: 'HDFC',
        maskedAccount: '••••1234',
        category: category,
        amount: amount,
        isCredit: false,
        timestamp: at,
      );

  Budget catBudget(
    FinanceStore store,
    SpendCategory category, {
    BudgetPeriod? period,
  }) {
    final list = period == null ? store.budgets : store.budgetsFor(period);
    return list.singleWhere((b) => b.category == category);
  }

  group('Budget model semantics', () {
    test('ratio is 0 with no plan and no spend', () {
      const b = Budget(category: SpendCategory.food, spent: 0, limit: 0);
      expect(b.ratio, 0);
      expect(b.status, BudgetStatus.safe);
    });

    test('ratio is 1 when plan is 0 and there is spend', () {
      const b = Budget(
        category: SpendCategory.food,
        spent: 40,
        limit: 0,
        isUserSet: true,
      );
      expect(b.ratio, 1.0);
      expect(b.status, BudgetStatus.over);
    });

    test('ratio equals spent/limit for positive plans', () {
      const b = Budget(category: SpendCategory.food, spent: 250, limit: 1000);
      expect(b.ratio, closeTo(0.25, 0.0001));
    });

    test('status safe below 75%', () {
      const b = Budget(category: SpendCategory.food, spent: 749, limit: 1000);
      expect(b.status, BudgetStatus.safe);
      expect(b.statusLabel, 'On track');
    });

    test('status warning at exactly 75%', () {
      const b = Budget(category: SpendCategory.food, spent: 750, limit: 1000);
      expect(b.ratio, 0.75);
      expect(b.status, BudgetStatus.warning);
      expect(b.statusLabel, 'Almost there');
    });

    test('status warning just under 100%', () {
      const b = Budget(category: SpendCategory.food, spent: 999, limit: 1000);
      expect(b.status, BudgetStatus.warning);
    });

    test('status OVER when ratio >= 1 (spent == plan)', () {
      const b = Budget(category: SpendCategory.food, spent: 1000, limit: 1000);
      expect(b.ratio, 1.0);
      expect(b.status, BudgetStatus.over);
      expect(b.statusLabel, 'Over budget');
    });

    test('status OVER when spent exceeds plan', () {
      const b = Budget(category: SpendCategory.food, spent: 1001, limit: 1000);
      expect(b.ratio, greaterThan(1));
      expect(b.status, BudgetStatus.over);
    });

    test('remaining is 0 when over or plan not positive', () {
      expect(
        const Budget(category: SpendCategory.food, spent: 1200, limit: 1000)
            .remaining,
        0,
      );
      expect(
        const Budget(
          category: SpendCategory.food,
          spent: 50,
          limit: 0,
          isUserSet: true,
        ).remaining,
        0,
      );
    });

    test('remaining and overAmount under a positive plan', () {
      const under =
          Budget(category: SpendCategory.food, spent: 400, limit: 1000);
      expect(under.remaining, 600);
      expect(under.overAmount, 0);

      const over =
          Budget(category: SpendCategory.food, spent: 1300, limit: 1000);
      expect(over.remaining, 0);
      expect(over.overAmount, 300);
    });

    test('overAmount equals spend when plan is ₹0 with spend', () {
      const b = Budget(
        category: SpendCategory.food,
        spent: 88,
        limit: 0,
        isUserSet: true,
      );
      expect(b.overAmount, 88);
      expect(b.usedPercent, 100);
    });

    test('usedPercent is 0 for unset empty envelope', () {
      const b = Budget(category: SpendCategory.food, spent: 0, limit: 0);
      expect(b.usedPercent, 0);
      expect(b.isUnset, isTrue);
      expect(b.statusLabel, 'Set plan');
    });

    test('usedPercent rounds ratio × 100', () {
      const b = Budget(category: SpendCategory.food, spent: 1, limit: 3);
      expect(b.usedPercent, 33);
    });

    test('spend without stored plan is not unset', () {
      const b = Budget(category: SpendCategory.food, spent: 10, limit: 0);
      expect(b.hasStoredPlan, isFalse);
      expect(b.isUnset, isFalse);
      expect(b.status, BudgetStatus.over);
    });

    test('hasStoredPlan mirrors isUserSet including ₹0', () {
      const unset = Budget(category: SpendCategory.food, spent: 0, limit: 0);
      const zero = Budget(
        category: SpendCategory.food,
        spent: 0,
        limit: 0,
        isUserSet: true,
      );
      expect(unset.hasStoredPlan, isFalse);
      expect(zero.hasStoredPlan, isTrue);
      expect(zero.isUnset, isFalse);
    });

    test('isOverAggregate aligns with row OVER rules', () {
      expect(Budget.isOverAggregate(planned: 500, spent: 500), isTrue);
      expect(Budget.isOverAggregate(planned: 500, spent: 501), isTrue);
      expect(Budget.isOverAggregate(planned: 500, spent: 499), isFalse);
      expect(Budget.isOverAggregate(planned: 0, spent: 1), isTrue);
      expect(Budget.isOverAggregate(planned: 0, spent: 0), isFalse);
    });
  });

  group('budgetable set + hero aggregates', () {
    test('budgetableCategories matches Reports spend categories (10 envelopes)', () {
      expect(FinanceStore.budgetableCategories, [
        SpendCategory.food,
        SpendCategory.travel,
        SpendCategory.shopping,
        SpendCategory.bills,
        SpendCategory.entertainment,
        SpendCategory.health,
        SpendCategory.emi,
        SpendCategory.atm,
        SpendCategory.other,
        SpendCategory.transfer,
      ]);
      expect(FinanceStore.budgetableCategories.length, 10);
      expect(
        FinanceStore.budgetableCategories.contains(SpendCategory.income),
        isFalse,
      );
    });

    test('totalBudget and budgetSpent sum every envelope', () async {
      final store = freshStore(freshDb());
      await store.init();
      await store.setCategoryBudgetLimit(SpendCategory.food, 2000);
      await store.setCategoryBudgetLimit(SpendCategory.travel, 1000);
      store.seedTransactions([
        debit(
          id: 'f',
          category: SpendCategory.food,
          amount: 300,
          at: thisMonth,
        ),
        debit(
          id: 't',
          category: SpendCategory.travel,
          amount: 700,
          at: thisMonth,
        ),
      ]);

      expect(store.totalBudget, 3000);
      expect(store.budgetSpent, 1000);
      expect(
        Budget.isOverAggregate(
          planned: store.totalBudget,
          spent: store.budgetSpent,
        ),
        isFalse,
      );
    });

    test('hero OVER when spent equals total plan', () async {
      final store = freshStore(freshDb());
      await store.init();
      await store.setCategoryBudgetLimit(SpendCategory.food, 500);
      store.seedTransactions([
        debit(
          id: 'f',
          category: SpendCategory.food,
          amount: 500,
          at: thisMonth,
        ),
      ]);

      expect(store.totalBudget, 500);
      expect(store.budgetSpent, 500);
      expect(
        Budget.isOverAggregate(
          planned: store.totalBudget,
          spent: store.budgetSpent,
        ),
        isTrue,
      );
      expect(catBudget(store, SpendCategory.food).status, BudgetStatus.over);
    });

    test('hero OVER when aggregate plan is 0 but there is spend', () async {
      final store = freshStore(freshDb());
      await store.init();
      store.seedTransactions([
        debit(
          id: 'f',
          category: SpendCategory.food,
          amount: 120,
          at: thisMonth,
        ),
      ]);

      expect(store.totalBudget, 0);
      expect(store.budgetSpent, 120);
      expect(
        Budget.isOverAggregate(
          planned: store.totalBudget,
          spent: store.budgetSpent,
        ),
        isTrue,
      );
    });

    test('totalBudgetFor / budgetSpentFor are period-scoped', () async {
      final store = freshStore(freshDb());
      await store.init();
      await store.setCategoryBudgetLimit(
        SpendCategory.food,
        1000,
        period: BudgetPeriod.monthly,
      );
      await store.setCategoryBudgetLimit(
        SpendCategory.food,
        20000,
        period: BudgetPeriod.yearly,
      );

      final janOnly = now.month == 1;
      store.seedTransactions([
        debit(
          id: 'm',
          category: SpendCategory.food,
          amount: 200,
          at: thisMonth,
        ),
        if (!janOnly)
          debit(
            id: 'y',
            category: SpendCategory.food,
            amount: 800,
            at: earlierThisYear,
          ),
      ]);

      expect(store.totalBudgetFor(BudgetPeriod.monthly), 1000);
      expect(store.totalBudgetFor(BudgetPeriod.yearly), 20000);
      expect(store.budgetSpentFor(BudgetPeriod.monthly), 200);
      expect(
        store.budgetSpentFor(BudgetPeriod.yearly),
        janOnly ? 200 : 1000,
      );
    });
  });

  group('period preference + pacing', () {
    test('setBudgetPeriod monthly is a no-op when already monthly', () async {
      final store = freshStore(freshDb());
      await store.init();
      expect(store.budgetPeriod, BudgetPeriod.monthly);
      await store.setBudgetPeriod(BudgetPeriod.monthly);
      expect(store.budgetPeriod, BudgetPeriod.monthly);
    });

    test('budgetPeriodLabel and range follow active period', () async {
      final store = freshStore(freshDb());
      await store.init();

      expect(store.budgetPeriodLabel, store.currentMonthLabel);
      expect(store.budgetPeriodRange.start.month, now.month);
      expect(store.budgetPeriodRange.start.day, 1);
      expect(store.budgetPeriodRange.end.day, now.day);

      await store.setBudgetPeriod(BudgetPeriod.yearly);
      expect(store.budgetPeriodLabel, store.currentYearLabel);
      expect(store.budgetPeriodRange.start, DateTime(now.year, 1, 1));
      expect(store.budgetPeriodRange.end.day, now.day);
      expect(store.budgetPeriodRange.end.month, now.month);
    });

    test('budgetDaysLeft is non-negative within calendar window', () async {
      final store = freshStore(freshDb());
      await store.init();

      expect(store.budgetDaysLeft, inInclusiveRange(0, 31));
      await store.setBudgetPeriod(BudgetPeriod.yearly);
      final end = DateTime(now.year, 12, 31);
      final expected =
          end.difference(DateTime(now.year, now.month, now.day)).inDays;
      expect(store.budgetDaysLeft, expected);
    });

    test('budgetDailyPaceLeft null when over or no positive plan', () async {
      final store = freshStore(freshDb());
      await store.init();

      expect(store.budgetDailyPaceLeft, isNull);

      await store.setCategoryBudgetLimit(SpendCategory.food, 100);
      store.seedTransactions([
        debit(
          id: 'f',
          category: SpendCategory.food,
          amount: 100,
          at: thisMonth,
        ),
      ]);
      expect(store.budgetDailyPaceLeft, isNull);

      store.seedTransactions([
        debit(
          id: 'f',
          category: SpendCategory.food,
          amount: 40,
          at: thisMonth,
        ),
      ]);
      if (store.budgetDaysLeft > 0) {
        expect(store.budgetDailyPaceLeft, closeTo(60 / store.budgetDaysLeft, 0.01));
      }
    });
  });

  group('reset / copy / clear / rescan', () {
    test('clearCategoryBudgetLimit restores unset for that period only',
        () async {
      final store = freshStore(freshDb());
      await store.init();
      await store.setCategoryBudgetLimit(
        SpendCategory.food,
        3000,
        period: BudgetPeriod.monthly,
      );
      await store.setCategoryBudgetLimit(
        SpendCategory.food,
        40000,
        period: BudgetPeriod.yearly,
      );

      await store.clearCategoryBudgetLimit(
        SpendCategory.food,
        period: BudgetPeriod.monthly,
      );
      expect(
        store.userBudgetLimit(SpendCategory.food, period: BudgetPeriod.monthly),
        isNull,
      );
      expect(catBudget(store, SpendCategory.food).isUnset, isTrue);
      expect(
        store.userBudgetLimit(SpendCategory.food, period: BudgetPeriod.yearly),
        40000,
      );
    });

    test('clearAllBudgetLimits yearly leaves monthly intact', () async {
      final store = freshStore(freshDb());
      await store.init();
      await store.setCategoryBudgetLimit(
        SpendCategory.shopping,
        1500,
        period: BudgetPeriod.monthly,
      );
      await store.setCategoryBudgetLimit(
        SpendCategory.shopping,
        18000,
        period: BudgetPeriod.yearly,
      );

      await store.clearAllBudgetLimits(period: BudgetPeriod.yearly);
      expect(
        store.userBudgetLimit(
          SpendCategory.shopping,
          period: BudgetPeriod.yearly,
        ),
        isNull,
      );
      expect(
        store.userBudgetLimit(
          SpendCategory.shopping,
          period: BudgetPeriod.monthly,
        ),
        1500,
      );
      expect(store.hasAnyYearlyBudgetPlan, isFalse);
    });

    test('hasAnyYearlyBudgetPlan true for stored yearly ₹0', () async {
      final store = freshStore(freshDb());
      await store.init();
      expect(store.hasAnyYearlyBudgetPlan, isFalse);
      await store.setCategoryBudgetLimit(
        SpendCategory.atm,
        0,
        period: BudgetPeriod.yearly,
      );
      expect(store.hasAnyYearlyBudgetPlan, isTrue);
    });

    test('copyMonthlyPlansToYearly returns 0 when monthly empty', () async {
      final store = freshStore(freshDb());
      await store.init();
      expect(await store.copyMonthlyPlansToYearly(), 0);
    });

    test('copyMonthlyPlansToYearly fills only empty yearly rows', () async {
      final store = freshStore(freshDb());
      await store.init();
      await store.setCategoryBudgetLimit(
        SpendCategory.food,
        1000,
        period: BudgetPeriod.monthly,
      );
      await store.setCategoryBudgetLimit(
        SpendCategory.bills,
        2000,
        period: BudgetPeriod.monthly,
      );
      await store.setCategoryBudgetLimit(
        SpendCategory.food,
        50,
        period: BudgetPeriod.yearly,
      );

      final n = await store.copyMonthlyPlansToYearly(overwrite: false);
      expect(n, 1);
      expect(
        store.userBudgetLimit(SpendCategory.food, period: BudgetPeriod.yearly),
        50,
      );
      expect(
        store.userBudgetLimit(SpendCategory.bills, period: BudgetPeriod.yearly),
        24000,
      );
    });

    test('negative limit clamps to 0 and still stores a plan', () async {
      final store = freshStore(freshDb());
      await store.init();
      await store.setCategoryBudgetLimit(SpendCategory.health, -25);
      expect(store.userBudgetLimit(SpendCategory.health), 0);
      expect(catBudget(store, SpendCategory.health).hasStoredPlan, isTrue);
    });

    test('clearAllData clears both monthly and yearly budget tables', () async {
      final path = '${tmp.path}/clear_all_budgets.db';
      final db = TransactionDatabase.forTesting(path);
      final store = FinanceStore(database: db);
      await store.init();
      await store.setCategoryBudgetLimit(
        SpendCategory.food,
        2000,
        period: BudgetPeriod.monthly,
      );
      await store.setCategoryBudgetLimit(
        SpendCategory.food,
        24000,
        period: BudgetPeriod.yearly,
      );

      await store.clearAllData();
      expect(
        store.userBudgetLimit(SpendCategory.food, period: BudgetPeriod.monthly),
        isNull,
      );
      expect(
        store.userBudgetLimit(SpendCategory.food, period: BudgetPeriod.yearly),
        isNull,
      );
      expect(store.budgets.every((b) => b.isUnset), isTrue);

      final reloaded = FinanceStore(database: TransactionDatabase.forTesting(path));
      await reloaded.init();
      expect(
        reloaded.userBudgetLimit(
          SpendCategory.food,
          period: BudgetPeriod.monthly,
        ),
        isNull,
      );
      expect(
        reloaded.userBudgetLimit(
          SpendCategory.food,
          period: BudgetPeriod.yearly,
        ),
        isNull,
      );
    });

    test('SMS-derived wipe preserves monthly and yearly budget plans', () async {
      final path = '${tmp.path}/rescan_keep_budgets.db';
      final db = TransactionDatabase.forTesting(path);
      final store = FinanceStore(database: db);
      await store.init();
      await store.setCategoryBudgetLimit(
        SpendCategory.travel,
        4500,
        period: BudgetPeriod.monthly,
      );
      await store.setCategoryBudgetLimit(
        SpendCategory.travel,
        54000,
        period: BudgetPeriod.yearly,
      );

      await db.clearSmsDerivedData();

      final reloaded = FinanceStore(database: TransactionDatabase.forTesting(path));
      await reloaded.init();
      expect(
        reloaded.userBudgetLimit(
          SpendCategory.travel,
          period: BudgetPeriod.monthly,
        ),
        4500,
      );
      expect(
        reloaded.userBudgetLimit(
          SpendCategory.travel,
          period: BudgetPeriod.yearly,
        ),
        54000,
      );
    });
  });

  group('spend filter + list order', () {
    test('income credits do not inflate budget spent', () async {
      final store = freshStore(freshDb());
      await store.init();
      store.seedTransactions([
        debit(
          id: 'f',
          category: SpendCategory.food,
          amount: 200,
          at: thisMonth,
        ),
        models.Transaction(
          id: 'pay',
          smsId: 'pay',
          merchant: 'Salary',
          bank: 'HDFC',
          maskedAccount: '••••1234',
          category: SpendCategory.income,
          amount: 50000,
          isCredit: true,
          timestamp: thisMonth,
        ),
      ]);

      expect(store.budgetSpent, 200);
      expect(catBudget(store, SpendCategory.food).spent, 200);
    });

    test('budgetSpendTransactions matches envelope spent for food', () async {
      final store = freshStore(freshDb());
      await store.init();
      store.seedTransactions([
        debit(
          id: 'f1',
          category: SpendCategory.food,
          amount: 110,
          at: thisMonth,
        ),
        debit(
          id: 'f2',
          category: SpendCategory.food,
          amount: 90,
          at: earlierThisMonth,
        ),
        debit(
          id: 'ccbp',
          category: SpendCategory.bills,
          amount: 9999,
          at: thisMonth,
          merchant: 'CCBP HDFC Card',
        ),
      ]);

      final rows = store.budgetSpendTransactions(
        SpendCategory.food,
        store.reportsThisMonthRange,
      );
      expect(rows.map((t) => t.id).toSet(), {'f1', 'f2'});
      expect(
        rows.fold(0.0, (s, t) => s + t.amount),
        catBudget(store, SpendCategory.food).spent,
      );
    });

    test('active envelopes sort ahead of unset zero rows', () async {
      final store = freshStore(freshDb());
      await store.init();
      await store.setCategoryBudgetLimit(SpendCategory.other, 500);
      store.seedTransactions([
        debit(
          id: 'f',
          category: SpendCategory.food,
          amount: 50,
          at: thisMonth,
        ),
      ]);

      final budgets = store.budgets;
      expect(budgets.first.category, SpendCategory.food);
      expect(
        budgets.indexWhere((b) => b.category == SpendCategory.other),
        lessThan(budgets.indexWhere((b) => b.category == SpendCategory.travel)),
      );
      expect(budgets.length, FinanceStore.budgetableCategories.length);
    });

    test('transfer category appears and matches Reports category spend',
        () async {
      final store = freshStore(freshDb());
      await store.init();
      store.seedTransactions([
        debit(
          id: 'xfer',
          category: SpendCategory.transfer,
          amount: 1500,
          at: thisMonth,
          merchant: 'UPI Transfer',
        ),
      ]);

      final monthlyReport = store.buildReport(
        store.reportsThisMonthRange.start,
        store.reportsThisMonthRange.end,
      );
      final transferBudget = catBudget(store, SpendCategory.transfer);
      expect(transferBudget.spent, monthlyReport.categorySpending[SpendCategory.transfer]);
      expect(transferBudget.spent, 1500);
    });

    test('budgetSpentFor monthly equals buildReport this month spent', () async {
      final store = freshStore(freshDb());
      await store.init();
      store.seedTransactions([
        debit(
          id: 'f',
          category: SpendCategory.food,
          amount: 300,
          at: thisMonth,
        ),
        debit(
          id: 't',
          category: SpendCategory.transfer,
          amount: 200,
          at: thisMonth,
        ),
      ]);

      final range = store.reportsThisMonthRange;
      final report = store.buildReport(range.start, range.end);
      expect(store.budgetSpentFor(BudgetPeriod.monthly), report.spent);
      expect(store.budgetSpentFor(BudgetPeriod.monthly), 500);
    });

    test('budgetSpentFor yearly equals buildReport this year spent', () async {
      final store = freshStore(freshDb());
      await store.init();
      final janOnly = now.month == 1;
      store.seedTransactions([
        debit(
          id: 'm',
          category: SpendCategory.food,
          amount: 400,
          at: thisMonth,
        ),
        if (!janOnly)
          debit(
            id: 'y',
            category: SpendCategory.shopping,
            amount: 600,
            at: earlierThisYear,
          ),
      ]);

      final range = store.reportsThisYearRange;
      final report = store.buildReport(range.start, range.end);
      expect(store.budgetSpentFor(BudgetPeriod.yearly), report.spent);
      expect(
        store.budgetSpentFor(BudgetPeriod.yearly),
        janOnly ? 400 : 1000,
      );
    });

    test('each envelope spent matches buildReport categorySpending', () async {
      final store = freshStore(freshDb());
      await store.init();
      store.seedTransactions([
        debit(
          id: 'f',
          category: SpendCategory.food,
          amount: 111,
          at: thisMonth,
        ),
        debit(
          id: 'b',
          category: SpendCategory.bills,
          amount: 222,
          at: thisMonth,
        ),
      ]);

      final report = store.budgetReportFor(BudgetPeriod.monthly);
      for (final b in store.budgetsFor(BudgetPeriod.monthly)) {
        expect(
          b.spent,
          report.categorySpending[b.category] ?? 0,
          reason: '${b.category.name} spent',
        );
      }
    });

    test('switching period swaps spent window without mutating the other',
        () async {
      final store = freshStore(freshDb());
      await store.init();
      final janOnly = now.month == 1;
      store.seedTransactions([
        debit(
          id: 'm',
          category: SpendCategory.shopping,
          amount: 100,
          at: thisMonth,
        ),
        if (!janOnly)
          debit(
            id: 'y',
            category: SpendCategory.shopping,
            amount: 400,
            at: earlierThisYear,
          ),
      ]);
      await store.setCategoryBudgetLimit(
        SpendCategory.shopping,
        1000,
        period: BudgetPeriod.monthly,
      );
      await store.setCategoryBudgetLimit(
        SpendCategory.shopping,
        12000,
        period: BudgetPeriod.yearly,
      );

      expect(catBudget(store, SpendCategory.shopping).spent, 100);
      await store.setBudgetPeriod(BudgetPeriod.yearly);
      expect(
        catBudget(store, SpendCategory.shopping).spent,
        janOnly ? 100 : 500,
      );
      expect(catBudget(store, SpendCategory.shopping).limit, 12000);
      await store.setBudgetPeriod(BudgetPeriod.monthly);
      expect(catBudget(store, SpendCategory.shopping).limit, 1000);
      expect(catBudget(store, SpendCategory.shopping).spent, 100);
    });
  });
}
