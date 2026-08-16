import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/models/transaction.dart';
import 'package:paisa_app/providers/app_settings.dart';
import 'package:paisa_app/providers/finance_store.dart';
import 'package:paisa_app/screens/reports_screen.dart';
import 'package:paisa_app/utils/formatters.dart';
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
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      buildTestApp(
        child: const ReportsScreen(),
        settings: settings,
        store: store,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> revealCustomChip(WidgetTester tester) async {
    // Chip row is wider than the viewport; scroll until Custom is hittable.
    for (var i = 0; i < 8; i++) {
      final target = find.text('Custom');
      if (target.evaluate().isNotEmpty) {
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        return;
      }
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(-220, 0),
      );
      await tester.pumpAndSettle();
    }
    expect(find.text('Custom'), findsOneWidget);
  }

  group('Reports Custom period', () {
    testWidgets('Custom opens Pulse Calendar (not Material range picker)',
        (tester) async {
      final store = FinanceStore()..seedTransactions(dummyTransactionHistory());
      await pumpReports(tester, store: store);

      await revealCustomChip(tester);
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();

      expect(find.text('PULSE'), findsOneWidget);
      expect(find.text('CALENDAR'), findsOneWidget);
      expect(find.text('JUMP'), findsOneWidget);
      expect(find.text('RANGE'), findsOneWidget);
      // Stock Material date-range chrome must not appear.
      expect(find.textContaining('Select range'), findsNothing);
    });

    testWidgets('JUMP applies inclusive custom range and updates KPIs',
        (tester) async {
      final day = dummyNowMonth(day: 5, hour: 13, minute: 20);
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

      await revealCustomChip(tester);
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();

      // Range mode is preselected; switch to Day and pick the 5th.
      await tester.tap(find.text('DAY'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('JUMP'));
      await tester.pumpAndSettle();

      final label = DateFormat('d MMM yyyy').format(DateTime(day.year, day.month, 5));
      expect(find.textContaining(label), findsWidgets);
      expect(find.text('Swiggy'), findsWidgets);
      expect(find.text('Jio Recharge'), findsNothing);
      expect(find.text(formatInr(486)), findsWidgets);
    });

    testWidgets('Cancel leaves preset unchanged', (tester) async {
      final store = FinanceStore()..seedTransactions(dummyTransactionHistory());
      await pumpReports(tester, store: store);

      expect(find.text('Salary'), findsWidgets);

      await revealCustomChip(tester);
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();

      expect(find.byType(PulseCalendarSheet), findsNothing);
      // Still on This month defaults — salary from day 1 is visible.
      expect(find.text('Salary'), findsWidgets);
      expect(find.text('Amazon'), findsWidgets);
    });

    testWidgets('Last month preset still works after Custom flow',
        (tester) async {
      final store = FinanceStore()..seedTransactions(dummyTransactionHistory());
      await pumpReports(tester, store: store);

      await revealCustomChip(tester);
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Last month'));
      await tester.tap(find.text('Last month'));
      await tester.pumpAndSettle();

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
