import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/data/transaction_database.dart';
import 'package:paisa_app/models/budget.dart';
import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/models/transaction.dart' as models;
import 'package:paisa_app/providers/finance_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Budget plans are user intent (including ₹0), not a live function of spend.
void main() {
  late Directory tmp;
  var seq = 0;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('paisa_budget_test');
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
  final lastMonth = DateTime(now.year, now.month - 1, 10, 12);
  final twoAgo = DateTime(now.year, now.month - 2, 10, 12);
  final threeAgo = DateTime(now.year, now.month - 3, 10, 12);
  final earlierThisYear = DateTime(now.year, 1, 15, 12);
  final lastYear = DateTime(now.year - 1, 6, 10, 12);

  models.Transaction food({
    required String id,
    required double amount,
    required DateTime at,
  }) =>
      models.Transaction(
        id: id,
        smsId: id,
        merchant: 'Swiggy',
        bank: 'HDFC',
        maskedAccount: '••••1234',
        category: SpendCategory.food,
        amount: amount,
        isCredit: false,
        timestamp: at,
      );

  Budget foodBudget(FinanceStore store, {BudgetPeriod? period}) {
    final list = period == null ? store.budgets : store.budgetsFor(period);
    return list.singleWhere((b) => b.category == SpendCategory.food);
  }

  test('lists every budgetable category at plan 0 when empty', () async {
    final db = freshDb();
    final store = freshStore(db);
    await store.init();

    expect(store.budgets.length, FinanceStore.budgetableCategories.length);
    expect(
      store.budgets.map((b) => b.category).toSet(),
      FinanceStore.budgetableCategories.toSet(),
    );
    expect(store.budgets.every((b) => b.limit == 0 && b.spent == 0), isTrue);
    expect(store.budgets.every((b) => b.isUnset), isTrue);
    expect(
      store.budgets.any((b) => b.category == SpendCategory.income),
      isFalse,
    );
    expect(
      store.budgets.any((b) => b.category == SpendCategory.transfer),
      isTrue,
    );
  });

  test('yearly mode also lists every budgetable category at plan 0', () async {
    final db = freshDb();
    final store = freshStore(db);
    await store.init();
    await store.setBudgetPeriod(BudgetPeriod.yearly);

    expect(store.budgets.length, FinanceStore.budgetableCategories.length);
    expect(store.budgets.every((b) => b.limit == 0 && b.spent == 0), isTrue);
    expect(
      store.budgetsFor(BudgetPeriod.yearly).map((b) => b.category).toSet(),
      FinanceStore.budgetableCategories.toSet(),
    );
  });

  test('limit 0 persists and stays visible on the food row', () async {
    final db = freshDb();
    final store = freshStore(db);
    await store.init();

    await store.setCategoryBudgetLimit(SpendCategory.food, 0);
    expect(store.userBudgetLimit(SpendCategory.food), 0);
    expect(foodBudget(store).limit, 0);
    expect(foodBudget(store).hasStoredPlan, isTrue);
    // Explicit ₹0 is stored intent — not identical to never-set.
    expect(foodBudget(store).isUnset, isFalse);
  });

  test('never-set plan is unset; stored ₹0 is not', () async {
    final db = freshDb();
    final store = freshStore(db);
    await store.init();

    expect(foodBudget(store).isUnset, isTrue);
    expect(foodBudget(store).hasStoredPlan, isFalse);

    await store.setCategoryBudgetLimit(SpendCategory.food, 0);
    expect(foodBudget(store).isUnset, isFalse);
    expect(foodBudget(store).hasStoredPlan, isTrue);
    expect(foodBudget(store).status, BudgetStatus.safe);
  });

  test('hero OVER matches row status for spent == plan and plan 0 spend', () {
    expect(
      Budget.isOverAggregate(planned: 1000, spent: 1000),
      isTrue,
    );
    expect(
      Budget.isOverAggregate(planned: 1000, spent: 999),
      isFalse,
    );
    expect(
      Budget.isOverAggregate(planned: 0, spent: 50),
      isTrue,
    );
    expect(
      Budget.isOverAggregate(planned: 0, spent: 0),
      isFalse,
    );
  });

  test('remaining and usedPercent on each envelope', () async {
    final db = freshDb();
    final store = freshStore(db);
    await store.init();

    await store.setCategoryBudgetLimit(SpendCategory.food, 2000);
    store.seedTransactions([
      food(id: 'f1', amount: 500, at: thisMonth),
    ]);

    final budget = foodBudget(store);
    expect(budget.remaining, 1500);
    expect(budget.usedPercent, 25);
    expect(budget.overAmount, 0);

    store.seedTransactions([
      food(id: 'f1', amount: 500, at: thisMonth),
      food(id: 'f2', amount: 1600, at: earlierThisMonth),
    ]);
    final over = foodBudget(store);
    expect(over.remaining, 0);
    expect(over.usedPercent, greaterThanOrEqualTo(100));
    expect(over.overAmount, 100);
    expect(over.status, BudgetStatus.over);
  });

  test('copy monthly plans ×12 into yearly with overwrite guard', () async {
    final db = freshDb();
    final store = freshStore(db);
    await store.init();

    await store.setCategoryBudgetLimit(
      SpendCategory.food,
      3000,
      period: BudgetPeriod.monthly,
    );
    await store.setCategoryBudgetLimit(
      SpendCategory.travel,
      2000,
      period: BudgetPeriod.monthly,
    );
    await store.setCategoryBudgetLimit(
      SpendCategory.food,
      100,
      period: BudgetPeriod.yearly,
    );

    final filled = await store.copyMonthlyPlansToYearly(overwrite: false);
    expect(filled, 1);
    expect(
      store.userBudgetLimit(SpendCategory.food, period: BudgetPeriod.yearly),
      100,
    );
    expect(
      store.userBudgetLimit(SpendCategory.travel, period: BudgetPeriod.yearly),
      24000,
    );

    final overwritten = await store.copyMonthlyPlansToYearly(overwrite: true);
    expect(overwritten, 2);
    expect(
      store.userBudgetLimit(SpendCategory.food, period: BudgetPeriod.yearly),
      36000,
    );
  });

  test('clearAllBudgetLimits resets only the active period', () async {
    final db = freshDb();
    final store = freshStore(db);
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

    await store.clearAllBudgetLimits(period: BudgetPeriod.monthly);
    expect(
      store.userBudgetLimit(SpendCategory.food, period: BudgetPeriod.monthly),
      isNull,
    );
    expect(
      store.userBudgetLimit(SpendCategory.food, period: BudgetPeriod.yearly),
      40000,
    );
    expect(foodBudget(store, period: BudgetPeriod.monthly).isUnset, isTrue);
  });

  test('budgetSpendTransactions excludes CCBP from category total', () async {
    final db = freshDb();
    final store = freshStore(db);
    await store.init();

    store.seedTransactions([
      food(id: 'f1', amount: 400, at: thisMonth),
      models.Transaction(
        id: 'ccbp',
        smsId: 'ccbp',
        merchant: 'CCBP Credit Card Bill',
        bank: 'HDFC',
        maskedAccount: '••••1234',
        category: SpendCategory.bills,
        amount: 5000,
        isCredit: false,
        timestamp: thisMonth,
      ),
      models.Transaction(
        id: 'bill',
        smsId: 'bill',
        merchant: 'Electricity',
        bank: 'HDFC',
        maskedAccount: '••••1234',
        category: SpendCategory.bills,
        amount: 800,
        isCredit: false,
        timestamp: thisMonth,
      ),
    ]);

    final range = store.currentMonthRange;
    final bills = store.budgetSpendTransactions(SpendCategory.bills, range);
    expect(bills.map((t) => t.id), ['bill']);
    expect(
      bills.fold(0.0, (s, t) => s + t.amount),
      800,
    );

    final billsBudget = store.budgets
        .singleWhere((b) => b.category == SpendCategory.bills);
    expect(billsBudget.spent, 800);
  });

  test('budgetDailyPaceLeft uses remaining / days left', () async {
    final db = freshDb();
    final store = freshStore(db);
    await store.init();

    await store.setCategoryBudgetLimit(SpendCategory.food, 10000);
    store.seedTransactions([
      food(id: 'f1', amount: 1000, at: thisMonth),
    ]);

    final pace = store.budgetDailyPaceLeft;
    expect(pace, isNotNull);
    expect(pace!, greaterThan(0));
    expect(
      pace * store.budgetDaysLeft,
      closeTo(store.totalBudget - store.budgetSpent, 0.01),
    );
  });

  test('spent updates progress against a fixed plan', () async {
    final db = freshDb();
    final store = freshStore(db);
    await store.init();

    await store.setCategoryBudgetLimit(SpendCategory.food, 2000);
    store.seedTransactions([
      food(id: 'f1', amount: 500, at: thisMonth),
    ]);

    var budget = foodBudget(store);
    expect(budget.limit, 2000);
    expect(budget.spent, 500);
    expect(budget.ratio, closeTo(0.25, 0.001));
    expect(budget.status, BudgetStatus.safe);

    store.seedTransactions([
      food(id: 'f1', amount: 500, at: thisMonth),
      food(id: 'f2', amount: 1600, at: earlierThisMonth),
    ]);
    budget = foodBudget(store);
    expect(budget.spent, 2100);
    expect(budget.ratio, greaterThan(1.0));
    expect(budget.status, BudgetStatus.over);
  });

  test('set limit persists across reload', () async {
    final path = '${tmp.path}/paisa_plan_persist.db';
    final db1 = TransactionDatabase.forTesting(path);
    final store1 = FinanceStore(database: db1);
    await store1.init();
    await store1.setCategoryBudgetLimit(SpendCategory.travel, 3500);

    final db2 = TransactionDatabase.forTesting(path);
    final store2 = FinanceStore(database: db2);
    await store2.init();
    expect(store2.userBudgetLimit(SpendCategory.travel), 3500);
    expect(
      store2.budgets
          .singleWhere((b) => b.category == SpendCategory.travel)
          .limit,
      3500,
    );
  });

  test('stored limit stays fixed when current spend grows past it', () async {
    final db = freshDb();
    final store = freshStore(db);
    await store.init();

    store.seedTransactions([
      food(id: 'f1', amount: 2000, at: thisMonth),
    ]);
    await store.setCategoryBudgetLimit(SpendCategory.food, 2500);

    expect(foodBudget(store).limit, 2500);
    expect(foodBudget(store).spent, 2000);
    expect(foodBudget(store).ratio, lessThan(1.0));
    expect(foodBudget(store).status, isNot(BudgetStatus.over));

    store.seedTransactions([
      food(id: 'f1', amount: 2000, at: thisMonth),
      food(id: 'f2', amount: 1500, at: earlierThisMonth),
    ]);
    expect(store.userBudgetLimit(SpendCategory.food), 2500);

    final budget = foodBudget(store);
    expect(budget.limit, 2500);
    expect(budget.spent, 3500);
    expect(budget.ratio, greaterThan(1.0));
    expect(budget.status, BudgetStatus.over);
  });

  test('suggestion uses median of prior months, not current×1.3', () async {
    final db = freshDb();
    final store = freshStore(db);
    await store.init();

    store.seedTransactions([
      food(id: 'h1', amount: 1000, at: threeAgo),
      food(id: 'h2', amount: 3000, at: twoAgo),
      food(id: 'h3', amount: 5000, at: lastMonth),
      food(id: 'c1', amount: 20000, at: thisMonth),
    ]);

    expect(store.suggestedBudgetLimit(SpendCategory.food), 3300);

    await store.ensureDefaultBudgetsSeeded();
    final budget = foodBudget(store);
    expect(budget.limit, 3300);
    expect(budget.spent, 20000);
    expect(budget.status, BudgetStatus.over);
    expect(budget.limit, isNot(26000));
  });

  test('seeds a budget for a category spent only in prior months (R2-9)',
      () async {
    final db = freshDb();
    final store = freshStore(db);
    await store.init();

    store.seedTransactions([
      food(id: 'h1', amount: 2000, at: lastMonth),
    ]);

    await store.ensureDefaultBudgetsSeeded();
    expect(store.userBudgetLimit(SpendCategory.food), isNotNull);
    expect(
      store.userBudgetLimit(SpendCategory.food),
      greaterThanOrEqualTo(1000),
    );
  });

  test('category_budgets table survives reload', () async {
    final path = '${tmp.path}/paisa_persist.db';
    final db1 = TransactionDatabase.forTesting(path);
    final store1 = FinanceStore(database: db1);
    await store1.init();
    await store1.setCategoryBudgetLimit(SpendCategory.shopping, 4000);

    final db2 = TransactionDatabase.forTesting(path);
    final store2 = FinanceStore(database: db2);
    await store2.init();
    expect(store2.userBudgetLimit(SpendCategory.shopping), 4000);
  });

  test('zero-plan with spend marks over', () async {
    final db = freshDb();
    final store = freshStore(db);
    await store.init();

    await store.setCategoryBudgetLimit(SpendCategory.food, 0);
    store.seedTransactions([
      food(id: 'f1', amount: 120, at: thisMonth),
    ]);

    final budget = foodBudget(store);
    expect(budget.limit, 0);
    expect(budget.spent, 120);
    expect(budget.status, BudgetStatus.over);
    expect(budget.ratio, 1.0);
  });

  test('monthly and yearly limits are independent', () async {
    final db = freshDb();
    final store = freshStore(db);
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

    expect(
      store.userBudgetLimit(SpendCategory.food, period: BudgetPeriod.monthly),
      3000,
    );
    expect(
      store.userBudgetLimit(SpendCategory.food, period: BudgetPeriod.yearly),
      40000,
    );
    expect(foodBudget(store, period: BudgetPeriod.monthly).limit, 3000);
    expect(foodBudget(store, period: BudgetPeriod.yearly).limit, 40000);
  });

  test('yearly spent is year-to-date, monthly is this month only', () async {
    final db = freshDb();
    final store = freshStore(db);
    await store.init();

    // Skip Jan earlier-year txn when January (same as this month).
    final janOnly = now.month == 1;
    store.seedTransactions([
      food(id: 'm', amount: 500, at: thisMonth),
      if (!janOnly) food(id: 'y', amount: 800, at: earlierThisYear),
      food(id: 'ly', amount: 9999, at: lastYear),
    ]);

    final monthly = foodBudget(store, period: BudgetPeriod.monthly);
    final yearly = foodBudget(store, period: BudgetPeriod.yearly);

    expect(monthly.spent, 500);
    if (janOnly) {
      expect(yearly.spent, 500);
    } else {
      expect(yearly.spent, 1300);
    }
    // Prior calendar year spend must not count toward this year's YTD.
    expect(yearly.spent, lessThan(9999));
  });

  test('yearly limits persist across reload', () async {
    final path = '${tmp.path}/paisa_yearly_persist.db';
    final db1 = TransactionDatabase.forTesting(path);
    final store1 = FinanceStore(database: db1);
    await store1.init();
    await store1.setCategoryBudgetLimit(
      SpendCategory.bills,
      120000,
      period: BudgetPeriod.yearly,
    );
    await store1.setCategoryBudgetLimit(
      SpendCategory.bills,
      10000,
      period: BudgetPeriod.monthly,
    );

    final db2 = TransactionDatabase.forTesting(path);
    final store2 = FinanceStore(database: db2);
    await store2.init();
    expect(
      store2.userBudgetLimit(SpendCategory.bills, period: BudgetPeriod.yearly),
      120000,
    );
    expect(
      store2.userBudgetLimit(SpendCategory.bills, period: BudgetPeriod.monthly),
      10000,
    );
  });

  test('budget period preference survives reload', () async {
    SharedPreferences.setMockInitialValues({});
    final db = freshDb();
    final store1 = freshStore(db);
    await store1.init();
    expect(store1.budgetPeriod, BudgetPeriod.monthly);
    await store1.setBudgetPeriod(BudgetPeriod.yearly);

    final store2 = freshStore(freshDb());
    await store2.init();
    expect(store2.budgetPeriod, BudgetPeriod.yearly);
  });

  test('editing active period does not overwrite the other', () async {
    final db = freshDb();
    final store = freshStore(db);
    await store.init();

    await store.setCategoryBudgetLimit(
      SpendCategory.travel,
      2000,
      period: BudgetPeriod.monthly,
    );
    await store.setBudgetPeriod(BudgetPeriod.yearly);
    await store.setCategoryBudgetLimit(SpendCategory.travel, 25000);

    expect(
      store.userBudgetLimit(SpendCategory.travel, period: BudgetPeriod.monthly),
      2000,
    );
    expect(
      store.userBudgetLimit(SpendCategory.travel, period: BudgetPeriod.yearly),
      25000,
    );
  });

  test('ratio >= 1 is OVER including spent == plan boundary', () async {
    final db = freshDb();
    final store = freshStore(db);
    await store.init();
    await store.setCategoryBudgetLimit(SpendCategory.food, 1000);
    store.seedTransactions([
      food(id: 'eq', amount: 1000, at: thisMonth),
    ]);
    final eq = foodBudget(store);
    expect(eq.ratio, 1.0);
    expect(eq.status, BudgetStatus.over);
    expect(
      Budget.isOverAggregate(planned: store.totalBudget, spent: store.budgetSpent),
      isTrue,
    );
  });

  test('warning band is [0.75, 1)', () async {
    final db = freshDb();
    final store = freshStore(db);
    await store.init();
    await store.setCategoryBudgetLimit(SpendCategory.food, 1000);

    store.seedTransactions([food(id: 'w', amount: 750, at: thisMonth)]);
    expect(foodBudget(store).status, BudgetStatus.warning);

    store.seedTransactions([food(id: 'w', amount: 999, at: thisMonth)]);
    expect(foodBudget(store).status, BudgetStatus.warning);

    store.seedTransactions([food(id: 'w', amount: 749, at: thisMonth)]);
    expect(foodBudget(store).status, BudgetStatus.safe);
  });

  test('explicit ₹0 plan contributes to totalBudget as 0 but is counted set',
      () async {
    final db = freshDb();
    final store = freshStore(db);
    await store.init();
    await store.setCategoryBudgetLimit(SpendCategory.food, 0);
    await store.setCategoryBudgetLimit(SpendCategory.travel, 2000);

    expect(store.totalBudget, 2000);
    expect(
      store.budgets.where((b) => b.hasStoredPlan).length,
      2,
    );
  });

  test('copy overwrite true replaces every yearly row from monthly ×12',
      () async {
    final db = freshDb();
    final store = freshStore(db);
    await store.init();
    await store.setCategoryBudgetLimit(
      SpendCategory.food,
      500,
      period: BudgetPeriod.monthly,
    );
    await store.setCategoryBudgetLimit(
      SpendCategory.food,
      1,
      period: BudgetPeriod.yearly,
    );

    final n = await store.copyMonthlyPlansToYearly(overwrite: true);
    expect(n, 1);
    expect(
      store.userBudgetLimit(SpendCategory.food, period: BudgetPeriod.yearly),
      6000,
    );
  });

  test('budgetSpendTransactions uses active period range when yearly', () async {
    final db = freshDb();
    final store = freshStore(db);
    await store.init();
    final janOnly = now.month == 1;
    store.seedTransactions([
      food(id: 'm', amount: 100, at: thisMonth),
      if (!janOnly) food(id: 'y', amount: 250, at: earlierThisYear),
    ]);
    await store.setBudgetPeriod(BudgetPeriod.yearly);

    final rows = store.budgetSpendTransactions(
      SpendCategory.food,
      store.budgetPeriodRange,
    );
    final sum = rows.fold(0.0, (s, t) => s + t.amount);
    expect(sum, foodBudget(store).spent);
    expect(sum, janOnly ? 100 : 350);
  });

  test('budgetSpentFor matches Reports this month and this year', () async {
    final db = freshDb();
    final store = freshStore(db);
    await store.init();
    store.seedTransactions([
      food(id: 'm', amount: 250, at: thisMonth),
      models.Transaction(
        id: 'xfer',
        smsId: 'xfer',
        merchant: 'Self transfer',
        bank: 'HDFC',
        maskedAccount: '••••1234',
        category: SpendCategory.transfer,
        amount: 750,
        isCredit: false,
        timestamp: thisMonth,
      ),
      if (now.month > 1)
        food(id: 'y', amount: 300, at: earlierThisYear),
    ]);

    final monthRange = store.reportsThisMonthRange;
    final monthReport =
        store.buildReport(monthRange.start, monthRange.end);
    expect(store.budgetSpentFor(BudgetPeriod.monthly), monthReport.spent);

    final yearRange = store.reportsThisYearRange;
    final yearReport = store.buildReport(yearRange.start, yearRange.end);
    expect(store.budgetSpentFor(BudgetPeriod.yearly), yearReport.spent);

    final transfer = store.budgets
        .singleWhere((b) => b.category == SpendCategory.transfer);
    expect(
      transfer.spent,
      monthReport.categorySpending[SpendCategory.transfer] ?? 0,
    );
    expect(transfer.spent, 750);
  });
}
