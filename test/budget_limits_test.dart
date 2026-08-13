import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/data/transaction_database.dart';
import 'package:paisa_app/models/budget.dart';
import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/models/transaction.dart' as models;
import 'package:paisa_app/providers/finance_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// ISSUE-5: budgets must be fixed user intent (or once-seeded suggestions),
/// not a live function of the current month's own spend — otherwise progress
/// is capped at ~77% and the "limit" grows as you spend.
void main() {
  late Directory tmp;
  var seq = 0;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
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
  final thisMonth = DateTime(now.year, now.month, 10, 12);
  final lastMonth = DateTime(now.year, now.month - 1, 10, 12);
  final twoAgo = DateTime(now.year, now.month - 2, 10, 12);
  final threeAgo = DateTime(now.year, now.month - 3, 10, 12);

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

  test('stored limit stays fixed when current spend grows past it', () async {
    final db = freshDb();
    final store = freshStore(db);
    await store.init();

    store.seedTransactions([
      food(id: 'f1', amount: 2000, at: thisMonth),
    ]);
    await store.setCategoryBudgetLimit(SpendCategory.food, 2500);

    expect(store.budgets.single.limit, 2500);
    expect(store.budgets.single.spent, 2000);
    expect(store.budgets.single.ratio, lessThan(1.0));
    expect(store.budgets.single.status, isNot(BudgetStatus.over));

    // More spend this month must NOT grow the limit (the old circular bug).
    store.seedTransactions([
      food(id: 'f1', amount: 2000, at: thisMonth),
      food(id: 'f2', amount: 1500, at: thisMonth.add(const Duration(days: 1))),
    ]);
    // Re-apply the persisted limit after seedTransactions wiped in-memory only
    // transactions — limits live in the DB / _userBudgetLimits map.
    expect(store.userBudgetLimit(SpendCategory.food), 2500);

    final budget = store.budgets.singleWhere((b) => b.category == SpendCategory.food);
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
      // Current month is huge — old formula would set limit ≈ current×1.3.
      food(id: 'c1', amount: 20000, at: thisMonth),
    ]);

    // Median of [1000, 3000, 5000] = 3000 → ×1.1 = 3300 → round to 3300.
    expect(store.suggestedBudgetLimit(SpendCategory.food), 3300);

    await store.ensureDefaultBudgetsSeeded();
    final budget =
        store.budgets.singleWhere((b) => b.category == SpendCategory.food);
    expect(budget.limit, 3300);
    expect(budget.spent, 20000);
    expect(budget.status, BudgetStatus.over);
    // Old circular formula: ceil(20000*1.3/100)*100 = 26000 — must not appear.
    expect(budget.limit, isNot(26000));
  });

  test('seeds a budget for a category spent only in prior months (R2-9)', () async {
    final db = freshDb();
    final store = freshStore(db);
    await store.init();

    store.seedTransactions([
      food(id: 'h1', amount: 2000, at: lastMonth),
    ]);

    await store.ensureDefaultBudgetsSeeded();
    expect(store.userBudgetLimit(SpendCategory.food), isNotNull);
    expect(store.userBudgetLimit(SpendCategory.food), greaterThanOrEqualTo(1000));
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
}
