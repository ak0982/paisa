import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/models/budget.dart';
import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/models/transaction.dart';
import 'package:paisa_app/providers/app_settings.dart';
import 'package:paisa_app/providers/finance_store.dart';
import 'package:paisa_app/screens/budgets_screen.dart';
import 'package:paisa_app/screens/category_transactions_screen.dart';
import 'package:paisa_app/utils/formatters.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/test_harness.dart';

/// UI contracts for BudgetsScreen period toggle, nudges, chips, hero labels.
///
/// Uses [FinanceStore.seedCategoryBudgetLimit] (in-memory) — do not call
/// [FinanceStore.init] / SQLite here; both hang under the widget binding
/// (SMS platform channel / FFI open).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppSettings settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await AppSettings.load();
  });

  final now = DateTime.now();
  final thisMonth = DateTime(now.year, now.month, now.day, 12);

  Transaction debit({
    required String id,
    required SpendCategory category,
    required double amount,
    String merchant = 'Shop',
  }) =>
      Transaction(
        id: id,
        smsId: id,
        merchant: merchant,
        bank: 'HDFC',
        maskedAccount: '••••1234',
        category: category,
        amount: amount,
        isCredit: false,
        timestamp: thisMonth,
      );

  FinanceStore readyStore({
    List<Transaction> txns = const [],
    void Function(FinanceStore store)? setup,
  }) {
    final store = FinanceStore();
    setup?.call(store);
    if (txns.isNotEmpty) store.seedTransactions(txns);
    return store;
  }

  /// Short pumps — coin painters are expensive (adversarial BudgetsScreen style).
  Future<void> pumpBudgets(WidgetTester tester, FinanceStore store) async {
    tester.view.physicalSize = const Size(400, 2800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildTestApp(
        settings: settings,
        store: store,
        child: const BudgetsScreen(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('period toggle + envelope list', () {
    testWidgets('shows all category labels and MONTH ENVELOPES', (tester) async {
      await pumpBudgets(tester, readyStore());

      expect(find.text('MONTH ENVELOPES'), findsOneWidget);
      expect(find.text('SET A PLAN'), findsOneWidget);
      expect(find.text('MONTHLY'), findsOneWidget);
      expect(find.text('YEARLY'), findsOneWidget);
      for (final c in FinanceStore.budgetableCategories) {
        expect(find.text(CategoryInfo.forCategory(c).label), findsOneWidget);
      }
    });

    testWidgets('YEARLY toggle switches copy and hero legend', (tester) async {
      final store = readyStore();
      await pumpBudgets(tester, store);

      await tester.tap(find.text('YEARLY'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(store.budgetPeriod, BudgetPeriod.yearly);
      expect(find.text('YEAR ENVELOPES'), findsOneWidget);
      expect(find.text('SET YEAR PLAN'), findsOneWidget);
      expect(find.textContaining('This year'), findsOneWidget);
      expect(find.text('YTD SPENT'), findsOneWidget);
    });

    testWidgets('set-count trailing updates after a stored plan', (tester) async {
      final store = readyStore(
        setup: (s) => s.seedCategoryBudgetLimit(SpendCategory.food, 2000),
      );
      await pumpBudgets(tester, store);

      expect(
        find.text('1 / ${FinanceStore.budgetableCategories.length} SET'),
        findsOneWidget,
      );
    });

    testWidgets('Plan ₹0 chip appears for explicit zero plan', (tester) async {
      final store = readyStore(
        setup: (s) => s.seedCategoryBudgetLimit(SpendCategory.food, 0),
      );
      await pumpBudgets(tester, store);

      expect(find.text('Plan ₹0'), findsOneWidget);
      expect(find.textContaining('Plan ₹0 · —'), findsOneWidget);
    });

    testWidgets('soft scan hint shows when there are no SMS rows', (tester) async {
      await pumpBudgets(tester, readyStore());
      expect(
        find.textContaining('scan SMS anytime to fill spent'),
        findsOneWidget,
      );
      expect(find.text('SCAN'), findsOneWidget);
    });
  });

  group('hero OVER / LEFT + pacing', () {
    testWidgets('LEFT label when under total plan', (tester) async {
      final store = readyStore(
        txns: [
          debit(id: 'f', category: SpendCategory.food, amount: 200),
        ],
        setup: (s) => s.seedCategoryBudgetLimit(SpendCategory.food, 1000),
      );
      await pumpBudgets(tester, store);

      expect(find.text('LEFT'), findsOneWidget);
      expect(find.text('OVER'), findsNothing);
      expect(find.textContaining('days left'), findsOneWidget);
      if (store.budgetDailyPaceLeft != null) {
        expect(find.textContaining('/day left to stay on plan'), findsOneWidget);
      }
    });

    testWidgets('OVER label when spent equals plan', (tester) async {
      final store = readyStore(
        txns: [
          debit(id: 'f', category: SpendCategory.food, amount: 1000),
        ],
        setup: (s) => s.seedCategoryBudgetLimit(SpendCategory.food, 1000),
      );
      await pumpBudgets(tester, store);

      expect(find.text('OVER'), findsWidgets);
      expect(find.text('LEFT'), findsNothing);
    });

    testWidgets('OVER when plan is 0 and there is spend', (tester) async {
      final store = readyStore(
        txns: [
          debit(id: 'f', category: SpendCategory.food, amount: 75),
        ],
      );
      await pumpBudgets(tester, store);

      expect(find.text('OVER'), findsWidgets);
      expect(find.textContaining('no month plan yet'), findsOneWidget);
    });

    testWidgets('remaining line shows Over amount when row is over',
        (tester) async {
      final store = readyStore(
        txns: [
          debit(id: 'f', category: SpendCategory.food, amount: 1200),
        ],
        setup: (s) => s.seedCategoryBudgetLimit(SpendCategory.food, 1000),
      );
      await pumpBudgets(tester, store);

      expect(
        find.textContaining('Over ${formatInr(200)}'),
        findsOneWidget,
      );
    });
  });

  group('soft 75% / 100% nudges', () {
    testWidgets('shows 75% warning nudge', (tester) async {
      final store = readyStore(
        txns: [
          debit(id: 'f', category: SpendCategory.food, amount: 750),
        ],
        setup: (s) => s.seedCategoryBudgetLimit(SpendCategory.food, 1000),
      );
      await pumpBudgets(tester, store);

      expect(find.text('Food is at 75% of plan.'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });

    testWidgets('shows 100% over nudge and prefers it over warning',
        (tester) async {
      final store = readyStore(
        txns: [
          debit(id: 'f', category: SpendCategory.food, amount: 1000),
          debit(id: 't', category: SpendCategory.travel, amount: 800),
        ],
        setup: (s) {
          s.seedCategoryBudgetLimit(SpendCategory.food, 1000);
          s.seedCategoryBudgetLimit(SpendCategory.travel, 1000);
        },
      );
      await pumpBudgets(tester, store);

      expect(find.text('Food is over plan (100%).'), findsOneWidget);
      expect(find.textContaining('is at 80% of plan'), findsNothing);
    });

    testWidgets('plan ₹0 with spend does not show nudge banner', (tester) async {
      final store = readyStore(
        txns: [
          debit(id: 'f', category: SpendCategory.food, amount: 50),
        ],
        setup: (s) => s.seedCategoryBudgetLimit(SpendCategory.food, 0),
      );
      await pumpBudgets(tester, store);

      expect(find.textContaining('is at'), findsNothing);
      expect(find.textContaining('is over plan'), findsNothing);
      expect(find.byIcon(Icons.close_rounded), findsNothing);
    });

    testWidgets('dismiss hides nudge and does not re-nag same day',
        (tester) async {
      final store = readyStore(
        txns: [
          debit(id: 'f', category: SpendCategory.food, amount: 800),
        ],
        setup: (s) => s.seedCategoryBudgetLimit(SpendCategory.food, 1000),
      );
      await pumpBudgets(tester, store);

      expect(find.text('Food is at 80% of plan.'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Food is at 80% of plan.'), findsNothing);

      await tester.pumpWidget(
        buildTestApp(
          settings: settings,
          store: store,
          child: const BudgetsScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Food is at 80% of plan.'), findsNothing);

      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getStringList('budget_nudge_dismissed') ?? [];
      expect(
        keys.any((k) => k.contains('food') && k.endsWith('|75')),
        isTrue,
      );
    });

    testWidgets('dismissed 100% key is persisted for monthly food',
        (tester) async {
      final store = readyStore(
        txns: [
          debit(id: 'f', category: SpendCategory.food, amount: 1100),
        ],
        setup: (s) => s.seedCategoryBudgetLimit(SpendCategory.food, 1000),
      );
      await pumpBudgets(tester, store);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getStringList('budget_nudge_dismissed') ?? [];
      final today = DateTime.now();
      final stamp =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      expect(keys, contains('monthly|food|$stamp|100'));
    });
  });

  group('actions menu + drill-down', () {
    testWidgets('budget actions menu exposes reset when plans exist',
        (tester) async {
      final store = readyStore(
        setup: (s) => s.seedCategoryBudgetLimit(SpendCategory.food, 500),
      );
      await pumpBudgets(tester, store);

      await tester.tap(find.byTooltip('Budget actions'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Reset monthly plans…'), findsOneWidget);
      expect(find.textContaining('Copy monthly'), findsOneWidget);
    });

    testWidgets('category row opens spend-aligned drill-down', (tester) async {
      final store = readyStore(
        txns: [
          debit(
            id: 'f',
            category: SpendCategory.food,
            amount: 220,
            merchant: 'SwiggyBudget',
          ),
          debit(
            id: 'ccbp',
            category: SpendCategory.bills,
            amount: 5000,
            merchant: 'CCBP Credit Card Bill',
          ),
        ],
        setup: (s) => s.seedCategoryBudgetLimit(SpendCategory.food, 2000),
      );
      await pumpBudgets(tester, store);

      await tester.tap(find.text('Food'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(CategoryTransactionsScreen), findsOneWidget);
      expect(find.text('SwiggyBudget'), findsOneWidget);
      expect(find.textContaining('CCBP'), findsNothing);
    });
  });
}
