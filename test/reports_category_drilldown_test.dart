import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/providers/app_settings.dart';
import 'package:paisa_app/providers/finance_store.dart';
import 'package:paisa_app/screens/category_transactions_screen.dart';
import 'package:paisa_app/screens/filtered_transactions_screen.dart';
import 'package:paisa_app/screens/reports_screen.dart';

import 'helpers/dummy_data.dart';
import 'helpers/test_harness.dart';

void main() {
  late AppSettings settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await AppSettings.load();
  });

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    FinanceStore? store,
  }) async {
    await tester.pumpWidget(
      buildTestApp(
        child: child,
        settings: settings,
        store: store,
      ),
    );
    await tester.pumpAndSettle();
  }

  group('CategoryTransactionsScreen range filter', () {
    testWidgets('without range uses Insights period (all recent debits)',
        (tester) async {
      final store = FinanceStore()..seedTransactions(dummyTransactionHistory());

      await pump(
        tester,
        const CategoryTransactionsScreen(category: SpendCategory.food),
        store: store,
      );

      expect(find.text('Food'), findsOneWidget);
      // Insights now cover the full history; label reflects earliest txn month
      // (Apr 2026 in the dummy dataset) rather than a fixed "Last 12 months".
      expect(find.text('Since Apr 2026'), findsOneWidget);
      expect(find.text('Swiggy'), findsOneWidget);
      expect(find.text('Zomato'), findsOneWidget);
    });

    testWidgets('with range only shows category txs in that period',
        (tester) async {
      final store = FinanceStore()..seedTransactions(dummyTransactionHistory());
      final range = DateTimeRange(
        start: DateTime(2026, 6, 1),
        end: DateTime(2026, 6, 30, 23, 59, 59, 999),
      );

      await pump(
        tester,
        CategoryTransactionsScreen(
          category: SpendCategory.bills,
          range: range,
          periodLabel: 'Last month',
        ),
        store: store,
      );

      expect(find.text('Bills'), findsOneWidget);
      expect(find.text('Last month'), findsOneWidget);
      expect(find.text('Jio Recharge'), findsOneWidget);
      expect(find.text('Swiggy'), findsNothing);
      expect(find.text('Zomato'), findsNothing);
    });

    testWidgets('empty range shows empty state', (tester) async {
      final store = FinanceStore()..seedTransactions(dummyTransactionHistory());
      final range = DateTimeRange(
        start: DateTime(2025, 1, 1),
        end: DateTime(2025, 1, 31, 23, 59, 59, 999),
      );

      await pump(
        tester,
        CategoryTransactionsScreen(
          category: SpendCategory.food,
          range: range,
          periodLabel: 'Custom',
        ),
        store: store,
      );

      expect(find.text('No food spending'), findsOneWidget);
      expect(
        find.text('Nothing in this category for custom.'),
        findsOneWidget,
      );
    });
  });

  group('FilteredTransactionsScreen merchant & income', () {
    testWidgets('merchant filter shows only matching debits in range',
        (tester) async {
      final store = FinanceStore()..seedTransactions(dummyTransactionHistory());
      final range = DateTimeRange(
        start: DateTime(2026, 7, 1),
        end: DateTime(2026, 7, 31, 23, 59, 59, 999),
      );

      await pump(
        tester,
        FilteredTransactionsScreen.merchant(
          merchant: 'Swiggy',
          range: range,
          periodLabel: 'This month',
        ),
        store: store,
      );

      expect(find.text('Swiggy'), findsWidgets);
      expect(find.text('Total spent'), findsOneWidget);
      expect(find.text('1 transaction'), findsOneWidget);
      expect(find.text('Zomato'), findsNothing);
      expect(find.text('Amazon'), findsNothing);
    });

    testWidgets('merchant match is case-insensitive', (tester) async {
      final store = FinanceStore()..seedTransactions(dummyTransactionHistory());
      final range = DateTimeRange(
        start: DateTime(2026, 7, 1),
        end: DateTime(2026, 7, 31, 23, 59, 59, 999),
      );

      await pump(
        tester,
        FilteredTransactionsScreen.merchant(
          merchant: 'swiggy',
          range: range,
          periodLabel: 'This month',
        ),
        store: store,
      );

      // Title shows the requested label; row still shows canonical merchant.
      expect(find.text('swiggy'), findsOneWidget);
      expect(find.text('Swiggy'), findsOneWidget);
      expect(find.text('1 transaction'), findsOneWidget);
    });

    testWidgets('income source filter shows only matching credits in range',
        (tester) async {
      final store = FinanceStore()..seedTransactions(dummyTransactionHistory());
      final range = DateTimeRange(
        start: DateTime(2026, 7, 1),
        end: DateTime(2026, 7, 31, 23, 59, 59, 999),
      );

      await pump(
        tester,
        FilteredTransactionsScreen.incomeSource(
          source: 'Salary',
          range: range,
          periodLabel: 'This month',
        ),
        store: store,
      );

      expect(find.text('Salary'), findsWidgets);
      expect(find.text('Total received'), findsOneWidget);
      expect(find.text('1 credit'), findsOneWidget);
      expect(find.text('Cashback'), findsNothing);
      expect(find.text('Bonus Credit'), findsNothing);
    });

    testWidgets('income empty range shows empty state', (tester) async {
      final store = FinanceStore()..seedTransactions(dummyTransactionHistory());
      final range = DateTimeRange(
        start: DateTime(2025, 1, 1),
        end: DateTime(2025, 1, 31, 23, 59, 59, 999),
      );

      await pump(
        tester,
        FilteredTransactionsScreen.incomeSource(
          source: 'Salary',
          range: range,
          periodLabel: 'Custom',
        ),
        store: store,
      );

      expect(find.text('No income from Salary'), findsOneWidget);
      expect(
        find.text('Nothing from this source for custom.'),
        findsOneWidget,
      );
    });
  });

  group('Reports drill-down', () {
    testWidgets('tapping Where money went row opens filtered list',
        (tester) async {
      // Large surface so category rows are hit-testable without overflow.
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final store = FinanceStore()..seedTransactions(dummyTransactionHistory());

      await pump(tester, const ReportsScreen(), store: store);

      expect(find.text('Where money went'), findsOneWidget);

      // Food row label includes share percent, e.g. "Food  ·  12%"
      final foodRow = find.textContaining('Food  ·');
      await tester.tap(foodRow);
      await tester.pumpAndSettle();

      expect(find.byType(CategoryTransactionsScreen), findsOneWidget);
      expect(find.text('This month'), findsWidgets);
      expect(find.text('Swiggy'), findsOneWidget);
      expect(find.text('Zomato'), findsOneWidget);
      // June bills should not appear in This month food drill-down
      expect(find.text('Jio Recharge'), findsNothing);
    });

    testWidgets('tapping Where money came from opens income credits',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final store = FinanceStore()..seedTransactions(dummyTransactionHistory());

      await pump(tester, const ReportsScreen(), store: store);

      expect(find.text('Where money came from'), findsOneWidget);

      await tester.tap(find.text('Salary'));
      await tester.pumpAndSettle();

      expect(find.byType(FilteredTransactionsScreen), findsOneWidget);
      expect(find.text('Total received'), findsOneWidget);
      expect(find.text('This month'), findsWidgets);
      expect(find.text('1 credit'), findsOneWidget);
      // Debits must not appear in income drill-down
      expect(find.text('Amazon'), findsNothing);
      expect(find.text('Swiggy'), findsNothing);
    });

    testWidgets('tapping Top merchants opens merchant debits', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final store = FinanceStore()..seedTransactions(dummyTransactionHistory());

      await pump(tester, const ReportsScreen(), store: store);

      expect(find.text('Top merchants'), findsOneWidget);

      // Amazon is a July debit in the dummy set; tap the merchant name in the list.
      await tester.ensureVisible(find.text('Amazon').first);
      await tester.tap(find.text('Amazon').first);
      await tester.pumpAndSettle();

      expect(find.byType(FilteredTransactionsScreen), findsOneWidget);
      expect(find.text('Total spent'), findsOneWidget);
      expect(find.text('This month'), findsWidgets);
      expect(find.text('1 transaction'), findsOneWidget);
      expect(find.text('Swiggy'), findsNothing);
      expect(find.text('Zomato'), findsNothing);
    });
  });
}
