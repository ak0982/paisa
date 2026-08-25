import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/models/transaction.dart';
import 'package:paisa_app/providers/app_settings.dart';
import 'package:paisa_app/providers/finance_store.dart';
import 'package:paisa_app/screens/insights_screen.dart';
import 'package:paisa_app/services/sms/account_discovery.dart';
import 'package:paisa_app/utils/formatters.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/test_harness.dart';

/// Stats = Paisa Ledger Coin. These guard the coin face numbers against the
/// store KPIs and the legends/rows below it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppSettings settings;

  Transaction tx({
    required String id,
    required double amount,
    required bool isCredit,
    required SpendCategory category,
    String merchant = 'Test',
    String bank = 'SBI',
    String mask = '••••0429',
    required DateTime timestamp,
  }) =>
      Transaction(
        id: id,
        smsId: id,
        merchant: merchant,
        bank: bank,
        maskedAccount: mask,
        category: category,
        amount: amount,
        isCredit: isCredit,
        timestamp: timestamp,
        accountKind: AccountKind.savings,
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await AppSettings.load();
  });

  Future<void> pumpStats(WidgetTester tester, FinanceStore store) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildTestApp(
        settings: settings,
        store: store,
        child: const InsightsScreen(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('ledger coin mints exact spend / income totals', (tester) async {
    final now = DateTime.now();
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'food',
          amount: 320.58,
          isCredit: false,
          category: SpendCategory.food,
          merchant: 'Swiggy',
          timestamp: now.subtract(const Duration(days: 2)),
        ),
        tx(
          id: 'shop',
          amount: 120.42,
          isCredit: false,
          category: SpendCategory.shopping,
          merchant: 'Blinkit',
          timestamp: now.subtract(const Duration(days: 1)),
        ),
        tx(
          id: 'salary',
          amount: 5000.00,
          isCredit: true,
          category: SpendCategory.income,
          merchant: 'Salary',
          timestamp: now.subtract(const Duration(days: 3)),
        ),
      ]);

    expect(store.insightsSpent, 441.00);
    expect(store.insightsIncome, 5000.00);

    await pumpStats(tester, store);

    // Coin chrome + hero.
    expect(find.text('PAISA'), findsOneWidget);
    expect(find.text('STATS'), findsOneWidget);
    expect(find.text('LEDGER'), findsOneWidget);
    expect(find.text('SPENT'), findsOneWidget);
    // Exact paise on the coin face, not rounded rupees.
    expect(find.text(formatInr(441.00)), findsOneWidget);
    expect(find.text(formatInr(5000.00)), findsOneWidget);

    // Legends.
    expect(find.text('DAILY AVG'), findsOneWidget);
    expect(find.text('PEAK DAY'), findsOneWidget);
    expect(find.text('NET'), findsOneWidget);
    expect(find.text(formatInr(store.insightsHighestDaySpend)), findsWidgets);
    expect(
      find.text(formatAmount(store.insightsNet, isCredit: true)),
      findsOneWidget,
    );

    // Category rows carry coin tokens + share captions, biggest first.
    expect(find.text('BY CATEGORY'), findsOneWidget);
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Shopping'), findsOneWidget);
    expect(find.text('TOP'), findsOneWidget);
    // Also echoed by the peak-day legend and the merchant rows.
    expect(find.text(formatInr(320.58)), findsWidgets);
    expect(find.text(formatInr(120.42)), findsWidgets);
    expect(
      tester.getTopLeft(find.text('Food')).dy <
          tester.getTopLeft(find.text('Shopping')).dy,
      isTrue,
    );

    // Top merchants reuse the same stamped rows.
    expect(find.text('TOP MERCHANTS'), findsOneWidget);
    expect(find.text('Swiggy'), findsOneWidget);
    expect(find.text('Blinkit'), findsOneWidget);
  });

  testWidgets('peak day legend opens the Paisa Coin for that day',
      (tester) async {
    final peak = DateTime.now().subtract(const Duration(days: 4));
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'peak',
          amount: 999.99,
          isCredit: false,
          category: SpendCategory.shopping,
          merchant: 'BigDay',
          timestamp: DateTime(peak.year, peak.month, peak.day, 11),
        ),
      ]);

    await pumpStats(tester, store);

    await tester.tap(find.text('PEAK DAY'));
    await tester.pumpAndSettle();

    expect(find.text('DAY'), findsOneWidget);
    expect(find.text('BigDay'), findsOneWidget);
  });

  testWidgets('empty ledger keeps zeroed coin and scan prompt', (tester) async {
    await pumpStats(tester, FinanceStore());

    expect(find.text('LEDGER'), findsOneWidget);
    // SPENT + IN fields both mint zero.
    expect(find.text(formatInr(0)), findsWidgets);
    expect(find.text('No transactions yet'), findsOneWidget);
    expect(find.text('Scan SMS now'), findsOneWidget);
    expect(find.text('BY CATEGORY'), findsNothing);
  });
}
