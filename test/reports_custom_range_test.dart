import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/models/transaction.dart';
import 'package:paisa_app/providers/app_settings.dart';
import 'package:paisa_app/providers/finance_store.dart';
import 'package:paisa_app/screens/reports_screen.dart';
import 'package:paisa_app/widgets/pulse_calendar_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/dummy_data.dart';
import 'helpers/test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppSettings settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await AppSettings.load();
  });

  Future<void> pumpReports(
    WidgetTester tester, {
    required FinanceStore store,
    DateTimeRange? initialRange,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      buildTestApp(
        child: ReportsScreen(initialRange: initialRange),
        settings: settings,
        store: store,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openBreakdown(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey<String>('folio-tab-BREAKDOWN')));
    await tester.pumpAndSettle();
  }

  Future<void> openLedger(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey<String>('folio-tab-LEDGER')));
    await tester.pumpAndSettle();
  }

  group('Reports Period Folio', () {
    testWidgets('defaults to Summary with Ledger Coin chrome', (tester) async {
      final store = FinanceStore()..seedTransactions(dummyTransactionHistory());
      await pumpReports(tester, store: store);

      expect(find.text('SUMMARY'), findsOneWidget);
      expect(find.text('BREAKDOWN'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('folio-tab-LEDGER')),
        findsOneWidget,
      );
      expect(find.text('This month'), findsWidgets);
      expect(find.text('3M'), findsOneWidget);
      expect(find.text('SPENT'), findsWidgets);
      expect(find.text('IN'), findsWidgets);
      expect(find.text('DAILY AVG'), findsOneWidget);
      expect(find.text('PEAK DAY'), findsOneWidget);
      expect(find.text('NET'), findsOneWidget);
      expect(find.text('SAVED'), findsOneWidget);
      // Demoted surfaces must not appear on Summary.
      expect(find.text('Where money went'), findsNothing);
      expect(find.text('NET FOR THIS RANGE'), findsNothing);
    });

    testWidgets('Ledger All/Out/In filters by isCredit with sort still available',
        (tester) async {
      final day = dummyElapsedMonth(day: 8, hour: 10);
      final store = FinanceStore()
        ..seedTransactions([
          dummyTxn(
            id: 'food',
            merchant: 'Swiggy',
            amount: 486,
            isCredit: false,
            category: SpendCategory.food,
            timestamp: day,
          ),
          dummyTxn(
            id: 'salary',
            merchant: 'Salary',
            amount: 50000,
            isCredit: true,
            category: SpendCategory.income,
            timestamp: day.add(const Duration(hours: 1)),
          ),
        ]);

      await pumpReports(tester, store: store);
      await openLedger(tester);

      expect(find.byKey(const ValueKey<String>('ledger-flow-All')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('ledger-flow-Out')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('ledger-flow-In')), findsOneWidget);
      expect(find.text('Newest'), findsOneWidget);
      expect(find.text('Swiggy'), findsOneWidget);
      expect(find.text('Salary'), findsOneWidget);
      expect(find.text('2 items'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('ledger-flow-Out')));
      await tester.pumpAndSettle();
      expect(find.text('Swiggy'), findsOneWidget);
      expect(find.text('Salary'), findsNothing);
      expect(find.text('1 item'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('ledger-flow-In')));
      await tester.pumpAndSettle();
      expect(find.text('Swiggy'), findsNothing);
      expect(find.text('Salary'), findsOneWidget);
      expect(find.text('1 item'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('ledger-flow-All')));
      await tester.pumpAndSettle();
      expect(find.text('Swiggy'), findsOneWidget);
      expect(find.text('Salary'), findsOneWidget);
      expect(find.text('2 items'), findsOneWidget);
    });

    testWidgets('initialRange opens Custom on Ledger tab', (tester) async {
      final day = dummyElapsedMonth(day: 5, hour: 13, minute: 20);
      final store = FinanceStore()
        ..seedTransactions([
          dummyTxn(
            id: 'food',
            merchant: 'Swiggy',
            amount: 486,
            isCredit: false,
            category: SpendCategory.food,
            timestamp: day,
          ),
        ]);
      final range = DateTimeRange(
        start: DateTime(day.year, day.month, day.day),
        end: DateTime(day.year, day.month, day.day, 23, 59, 59, 999),
      );

      await pumpReports(tester, store: store, initialRange: range);

      expect(find.text('Custom'), findsWidgets);
      expect(find.text('Swiggy'), findsWidgets);
      expect(find.textContaining(DateFormat('d MMM yyyy').format(day)), findsWidgets);
    });
  });

  group('Reports Custom period', () {
    testWidgets('Custom opens Pulse Calendar (not Material range picker)',
        (tester) async {
      final store = FinanceStore()..seedTransactions(dummyTransactionHistory());
      await pumpReports(tester, store: store);

      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();

      expect(find.text('PULSE'), findsOneWidget);
      expect(find.text('CALENDAR'), findsOneWidget);
      expect(find.text('JUMP'), findsOneWidget);
      expect(find.text('RANGE'), findsOneWidget);
      expect(find.textContaining('Select range'), findsNothing);
    });

    testWidgets('JUMP applies inclusive custom range and updates Ledger',
        (tester) async {
      final day = dummyElapsedMonth(day: 5, hour: 13, minute: 20);
      final store = FinanceStore()
        ..seedTransactions([
          dummyTxn(
            id: 'food',
            merchant: 'Swiggy',
            amount: 486,
            isCredit: false,
            category: SpendCategory.food,
            timestamp: day,
          ),
          dummyTxn(
            id: 'other-month',
            merchant: 'Jio Recharge',
            amount: 299,
            isCredit: false,
            category: SpendCategory.bills,
            timestamp: dummyNowMonth(monthsAgo: 1, day: 15, hour: 11),
          ),
        ]);

      await pumpReports(tester, store: store);

      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('DAY'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('${day.day}').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('JUMP'));
      await tester.pumpAndSettle();

      final label = DateFormat('d MMM yyyy').format(day);
      expect(find.textContaining(label), findsWidgets);

      await openLedger(tester);
      expect(find.text('Swiggy'), findsWidgets);
      expect(find.text('Jio Recharge'), findsNothing);
      expect(find.textContaining('486'), findsWidgets);
    });

    testWidgets('Cancel leaves preset unchanged', (tester) async {
      final store = FinanceStore()..seedTransactions(dummyTransactionHistory());
      await pumpReports(tester, store: store);

      await openBreakdown(tester);
      expect(find.text('Salary'), findsWidgets);

      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();

      expect(find.byType(PulseCalendarSheet), findsNothing);
      await openBreakdown(tester);
      expect(find.text('Salary'), findsWidgets);
      expect(find.text('Amazon'), findsWidgets);
    });

    testWidgets('Last month preset still works after Custom flow',
        (tester) async {
      final store = FinanceStore()..seedTransactions(dummyTransactionHistory());
      await pumpReports(tester, store: store);

      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Last month'));
      await tester.pumpAndSettle();

      await openLedger(tester);
      expect(find.text('Jio Recharge'), findsWidgets);
      expect(find.text('Netflix'), findsWidgets);
      expect(find.text('Swiggy'), findsNothing);
      expect(find.text('Amazon'), findsNothing);
    });
  });

  group('buildReport inclusive end day', () {
    test('includes spend on the end calendar day', () {
      final start = DateTime(2026, 8, 10);
      final endInclusive = DateTime(2026, 8, 12, 23, 59, 59, 999);
      final store = FinanceStore()
        ..seedTransactions([
          Transaction(
            id: 'mid',
            smsId: 'mid',
            merchant: 'Cafe',
            bank: 'SBI',
            maskedAccount: '••••0429',
            category: SpendCategory.food,
            amount: 100,
            isCredit: false,
            timestamp: DateTime(2026, 8, 12, 22, 30),
          ),
          Transaction(
            id: 'after',
            smsId: 'after',
            merchant: 'Late',
            bank: 'SBI',
            maskedAccount: '••••0429',
            category: SpendCategory.food,
            amount: 50,
            isCredit: false,
            timestamp: DateTime(2026, 8, 13, 0, 0, 1),
          ),
        ]);

      final report = store.buildReport(start, endInclusive);
      expect(report.spent, 100);
      expect(report.transactionCount, 1);
      expect(report.dayCount, 3);
    });
  });
}
