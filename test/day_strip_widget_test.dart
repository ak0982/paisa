import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/models/transaction.dart';
import 'package:paisa_app/providers/app_settings.dart';
import 'package:paisa_app/providers/finance_store.dart';
import 'package:paisa_app/screens/day_strip_screen.dart';
import 'package:paisa_app/services/sms/account_discovery.dart';
import 'package:paisa_app/utils/formatters.dart';
import 'package:paisa_app/widgets/day_strip_teaser.dart';
import 'package:paisa_app/widgets/paisa_coin.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppSettings settings;
  final day = DateTime(2026, 8, 15, 12);

  Transaction tx({
    required String id,
    required double amount,
    required bool isCredit,
    required SpendCategory category,
    AccountKind kind = AccountKind.savings,
    String merchant = 'Test',
    String bank = 'SBI',
    String mask = '••••0429',
    DateTime? timestamp,
    Duration offset = Duration.zero,
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
        timestamp: (timestamp ?? day).add(offset),
        accountKind: kind,
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await AppSettings.load();
  });

  Future<void> pumpCoin(
    WidgetTester tester, {
    required FinanceStore store,
    DateTime? initialDay,
    DateTime? initialEnd,
  }) async {
    // Tall viewport so day/range list rows are all built (not virtualized away).
    tester.view.physicalSize = const Size(400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildTestApp(
        settings: settings,
        store: store,
        child: DayStripScreen(
          initialDay: initialDay ?? day,
          initialEnd: initialEnd,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Filter chips render as ALL/OUT/IN; coin face also has OUT/IN labels.
  /// Index 1 is the filter chip (coin face is index 0).
  Finder flowFilter(String label) => find.text(label).at(1);

  testWidgets('Paisa Coin empty day shows unstruck coin', (tester) async {
    final store = FinanceStore();

    await tester.pumpWidget(
      buildTestApp(
        settings: settings,
        store: store,
        child: DayStripScreen(initialDay: DateTime(2026, 8, 16)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No money moved'), findsOneWidget);
    expect(find.textContaining('net'), findsOneWidget);
    // Coin face still mints zeroes for OUT and IN.
    expect(find.text('PAISA'), findsOneWidget);
    expect(find.text('SUN 16 AUG'), findsOneWidget);
    // OUT/IN appear on the coin face and again as flow chips.
    expect(find.text('OUT'), findsWidgets);
    expect(find.text('IN'), findsWidgets);
    expect(find.text('₹0.00'), findsNWidgets(2));
  });

  testWidgets('Paisa Coin shows MOVE badge for CC bill payment', (tester) async {
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'food',
          amount: 100,
          isCredit: false,
          category: SpendCategory.food,
          merchant: 'Swiggy',
        ),
        tx(
          id: 'ccbp',
          amount: 500,
          isCredit: false,
          category: SpendCategory.transfer,
          kind: AccountKind.creditCard,
          merchant: 'Credit card bill payment',
          bank: 'HDFC',
          mask: '••••1111',
          offset: const Duration(hours: 1),
        ),
      ]);

    await pumpCoin(tester, store: store);

    expect(find.text('MOVE'), findsOneWidget);
    expect(find.text('Swiggy'), findsOneWidget);
    expect(find.text('Food'), findsOneWidget);
    expect(find.textContaining('₹100.00'), findsWidgets);
    // Coin centre carries the exact OUT total; internals stay out of it.
    expect(find.text('DAY'), findsOneWidget);
    expect(find.text('SAT 15 AUG'), findsOneWidget);
    expect(find.text('₹100.00'), findsWidgets);
  });

  testWidgets('Paisa Coin range header and calendar control', (tester) async {
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'a',
          amount: 80,
          isCredit: false,
          category: SpendCategory.food,
          merchant: 'Cafe',
          timestamp: DateTime(2026, 8, 12, 10),
        ),
        tx(
          id: 'b',
          amount: 200,
          isCredit: true,
          category: SpendCategory.income,
          merchant: 'Pay',
          timestamp: DateTime(2026, 8, 15, 11),
        ),
      ]);

    await pumpCoin(
      tester,
      store: store,
      initialDay: DateTime(2026, 8, 12),
      initialEnd: DateTime(2026, 8, 15),
    );

    expect(find.text('12–15 AUG'), findsOneWidget);
    expect(find.text('RANGE'), findsOneWidget);
    expect(find.byTooltip('Pulse Calendar'), findsOneWidget);
    expect(find.text('ALL'), findsOneWidget);
    expect(find.text('OUT'), findsWidgets);
    expect(find.text('IN'), findsWidgets);
    // Range arcs use whole-range totals in exact paise.
    expect(find.text(formatInr(80)), findsWidgets);
    expect(find.text(formatInr(200)), findsWidgets);
    expect(find.textContaining('Cafe'), findsOneWidget);
    expect(find.textContaining('Pay'), findsOneWidget);
  });

  testWidgets('coin OUT/IN match store KPIs for mixed fixture day', (tester) async {
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'food',
          amount: 320.58,
          isCredit: false,
          category: SpendCategory.food,
          merchant: 'Swiggy',
        ),
        tx(
          id: 'salary',
          amount: 500.00,
          isCredit: true,
          category: SpendCategory.income,
          merchant: 'Salary',
          offset: const Duration(hours: 1),
        ),
        tx(
          id: 'ccbp',
          amount: 1200.00,
          isCredit: false,
          category: SpendCategory.transfer,
          kind: AccountKind.creditCard,
          merchant: 'Credit card bill payment',
          mask: '••••1111',
          offset: const Duration(hours: 2),
        ),
        tx(
          id: 'cc_in',
          amount: 1200.00,
          isCredit: true,
          category: SpendCategory.transfer,
          kind: AccountKind.creditCard,
          merchant: 'Credit card payment',
          mask: '••••1111',
          offset: const Duration(hours: 2, minutes: 1),
        ),
        tx(
          id: 'xfer_out',
          amount: 2000.00,
          isCredit: false,
          category: SpendCategory.transfer,
          merchant: 'Axis Transfer',
          offset: const Duration(hours: 3),
        ),
        tx(
          id: 'xfer_in',
          amount: 2000.00,
          isCredit: true,
          category: SpendCategory.income,
          merchant: 'Self Transfer',
          bank: 'Axis',
          mask: '••••9867',
          offset: const Duration(hours: 3, minutes: 1),
        ),
      ]);

    expect(store.daySpend(day), 320.58);
    expect(store.dayIncome(day), 500.00);

    await pumpCoin(tester, store: store);

    expect(find.text(formatInr(320.58)), findsWidgets);
    expect(find.text(formatInr(500.00)), findsWidgets);
    expect(find.text('net +${formatInr(500.00 - 320.58)}'), findsOneWidget);
    // All six rows listed (including MOVE internals).
    expect(find.text('Swiggy'), findsOneWidget);
    expect(find.text('Salary'), findsOneWidget);
    expect(find.text('Credit card bill payment'), findsOneWidget);
    expect(find.text('Credit card payment'), findsOneWidget);
    expect(find.text('Axis Transfer'), findsOneWidget);
    expect(find.text('Self Transfer'), findsOneWidget);
    expect(find.text('MOVE'), findsNWidgets(4));
  });

  testWidgets('list row amounts use formatAmount with debit/credit signs',
      (tester) async {
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'out',
          amount: 12.34,
          isCredit: false,
          category: SpendCategory.food,
          merchant: 'Cafe',
        ),
        tx(
          id: 'inn',
          amount: 56.78,
          isCredit: true,
          category: SpendCategory.income,
          merchant: 'Refund',
          offset: const Duration(hours: 1),
        ),
      ]);

    await pumpCoin(tester, store: store);

    expect(find.text(formatAmount(12.34, isCredit: false)), findsOneWidget);
    expect(find.text(formatAmount(56.78, isCredit: true)), findsOneWidget);
    expect(find.text(formatInr(12.34)), findsWidgets);
    expect(find.text(formatInr(56.78)), findsWidgets);
  });

  testWidgets('Out filter keeps debits including MOVE; hides credits',
      (tester) async {
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'food',
          amount: 40,
          isCredit: false,
          category: SpendCategory.food,
          merchant: 'Swiggy',
        ),
        tx(
          id: 'ccbp',
          amount: 500,
          isCredit: false,
          category: SpendCategory.transfer,
          kind: AccountKind.creditCard,
          merchant: 'Credit card bill payment',
          mask: '••••1111',
          offset: const Duration(hours: 1),
        ),
        tx(
          id: 'salary',
          amount: 200,
          isCredit: true,
          category: SpendCategory.income,
          merchant: 'Salary',
          offset: const Duration(hours: 2),
        ),
      ]);

    await pumpCoin(tester, store: store);

    await tester.tap(flowFilter('OUT'));
    await tester.pumpAndSettle();

    expect(find.text('Swiggy'), findsOneWidget);
    expect(find.text('Credit card bill payment'), findsOneWidget);
    expect(find.text('MOVE'), findsOneWidget);
    expect(find.text('Salary'), findsNothing);
    // Coin KPIs unchanged by list filter.
    expect(find.text(formatInr(40)), findsWidgets);
    expect(find.text(formatInr(200)), findsWidgets);
  });

  testWidgets('In filter keeps credits including CC payment-received MOVE',
      (tester) async {
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'food',
          amount: 40,
          isCredit: false,
          category: SpendCategory.food,
          merchant: 'Swiggy',
        ),
        tx(
          id: 'cc_in',
          amount: 500,
          isCredit: true,
          category: SpendCategory.transfer,
          kind: AccountKind.creditCard,
          merchant: 'Credit card payment',
          mask: '••••1111',
          offset: const Duration(hours: 1),
        ),
        tx(
          id: 'salary',
          amount: 200,
          isCredit: true,
          category: SpendCategory.income,
          merchant: 'Salary',
          offset: const Duration(hours: 2),
        ),
      ]);

    await pumpCoin(tester, store: store);

    await tester.tap(flowFilter('IN'));
    await tester.pumpAndSettle();

    expect(find.text('Swiggy'), findsNothing);
    expect(find.text('Credit card payment'), findsOneWidget);
    expect(find.text('Salary'), findsOneWidget);
    expect(find.text('MOVE'), findsOneWidget);
    expect(find.text(formatInr(40)), findsWidgets); // coin OUT
    expect(find.text(formatInr(200)), findsWidgets); // coin IN (excludes CC)
  });

  testWidgets('All filter restores full day list after Out', (tester) async {
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'food',
          amount: 10,
          isCredit: false,
          category: SpendCategory.food,
          merchant: 'Swiggy',
        ),
        tx(
          id: 'salary',
          amount: 20,
          isCredit: true,
          category: SpendCategory.income,
          merchant: 'Salary',
          offset: const Duration(hours: 1),
        ),
      ]);

    await pumpCoin(tester, store: store);
    await tester.tap(flowFilter('OUT'));
    await tester.pumpAndSettle();
    expect(find.text('Salary'), findsNothing);

    await tester.tap(find.text('ALL'));
    await tester.pumpAndSettle();
    expect(find.text('Swiggy'), findsOneWidget);
    expect(find.text('Salary'), findsOneWidget);
  });

  testWidgets('sort newest / oldest / high / low reorder list rows',
      (tester) async {
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'mid',
          amount: 200,
          isCredit: false,
          category: SpendCategory.food,
          merchant: 'MidMart',
          offset: const Duration(hours: 2),
        ),
        tx(
          id: 'low',
          amount: 50,
          isCredit: false,
          category: SpendCategory.food,
          merchant: 'LowCafe',
          offset: const Duration(hours: 5),
        ),
        tx(
          id: 'high',
          amount: 500,
          isCredit: false,
          category: SpendCategory.food,
          merchant: 'HighShop',
          offset: const Duration(hours: 1),
        ),
      ]);

    await pumpCoin(tester, store: store);

    // Default sort is oldest-first.
    expect(
      tester.getTopLeft(find.text('HighShop')).dy <
          tester.getTopLeft(find.text('MidMart')).dy,
      isTrue,
    );
    expect(
      tester.getTopLeft(find.text('MidMart')).dy <
          tester.getTopLeft(find.text('LowCafe')).dy,
      isTrue,
    );

    await tester.tap(find.byTooltip('Sort transactions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Newest first'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('LowCafe')).dy <
          tester.getTopLeft(find.text('MidMart')).dy,
      isTrue,
    );

    await tester.tap(find.byTooltip('Sort transactions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Amount: high to low'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('HighShop')).dy <
          tester.getTopLeft(find.text('MidMart')).dy,
      isTrue,
    );
    expect(
      tester.getTopLeft(find.text('MidMart')).dy <
          tester.getTopLeft(find.text('LowCafe')).dy,
      isTrue,
    );

    await tester.tap(find.byTooltip('Sort transactions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Amount: low to high'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('LowCafe')).dy <
          tester.getTopLeft(find.text('MidMart')).dy,
      isTrue,
    );
  });

  testWidgets('range mode lists all days and shows range OUT/IN totals',
      (tester) async {
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'd14',
          amount: 100.25,
          isCredit: false,
          category: SpendCategory.food,
          merchant: 'Day14Food',
          timestamp: DateTime(2026, 8, 14, 10),
        ),
        tx(
          id: 'd15_out',
          amount: 50.50,
          isCredit: false,
          category: SpendCategory.food,
          merchant: 'Day15Food',
          timestamp: DateTime(2026, 8, 15, 12),
        ),
        tx(
          id: 'd15_in',
          amount: 200.00,
          isCredit: true,
          category: SpendCategory.income,
          merchant: 'Day15Pay',
          timestamp: DateTime(2026, 8, 15, 14),
        ),
        tx(
          id: 'd16',
          amount: 75.00,
          isCredit: false,
          category: SpendCategory.food,
          merchant: 'Day16Food',
          timestamp: DateTime(2026, 8, 16, 9),
        ),
        tx(
          id: 'ccbp',
          amount: 999,
          isCredit: false,
          category: SpendCategory.transfer,
          kind: AccountKind.creditCard,
          merchant: 'Credit card bill payment',
          mask: '••••1111',
          timestamp: DateTime(2026, 8, 15, 16),
        ),
      ]);

    final start = DateTime(2026, 8, 14);
    final end = DateTime(2026, 8, 16);
    expect(store.rangeSpend(start, end), 100.25 + 50.50 + 75.00);
    expect(store.rangeIncome(start, end), 200.00);

    await pumpCoin(tester, store: store, initialDay: start, initialEnd: end);

    expect(find.text('RANGE'), findsOneWidget);
    expect(find.text('14–16 AUG'), findsOneWidget);
    expect(find.text(formatInr(225.75)), findsWidgets);
    expect(find.text(formatInr(200.00)), findsWidgets);
    expect(find.text('Day14Food'), findsOneWidget);
    expect(find.text('Day15Food'), findsOneWidget);
    expect(find.text('Day15Pay'), findsOneWidget);
    expect(find.text('Day16Food'), findsOneWidget);
    expect(find.text('Credit card bill payment'), findsOneWidget);
    expect(find.text('MOVE'), findsOneWidget);
    // Range rows show date prefix (day + month).
    expect(find.textContaining('14 AUG'), findsWidgets);
  });

  testWidgets('day chevron navigates to neighbor day amounts', (tester) async {
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'd15',
          amount: 15.15,
          isCredit: false,
          category: SpendCategory.food,
          merchant: 'SatCafe',
          timestamp: DateTime(2026, 8, 15, 12),
        ),
        tx(
          id: 'd16',
          amount: 16.16,
          isCredit: false,
          category: SpendCategory.food,
          merchant: 'SunCafe',
          timestamp: DateTime(2026, 8, 16, 12),
        ),
      ]);

    await pumpCoin(tester, store: store);

    expect(find.text('SAT 15 AUG'), findsOneWidget);
    expect(find.text('SatCafe'), findsOneWidget);
    expect(find.text(formatInr(15.15)), findsWidgets);

    await tester.tap(
      find.descendant(
        of: find.byType(PaisaChromeIconButton),
        matching: find.byIcon(Icons.chevron_right_rounded),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('SUN 16 AUG'), findsOneWidget);
    expect(find.text('SunCafe'), findsOneWidget);
    expect(find.text(formatInr(16.16)), findsWidgets);
    expect(find.text('SatCafe'), findsNothing);
  });

  testWidgets('empty filter result shows empty state while coin keeps totals',
      (tester) async {
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'salary',
          amount: 100,
          isCredit: true,
          category: SpendCategory.income,
          merchant: 'Salary',
        ),
      ]);

    await pumpCoin(tester, store: store);
    expect(find.text('Salary'), findsOneWidget);

    await tester.tap(flowFilter('OUT'));
    await tester.pumpAndSettle();

    expect(find.text('No money moved'), findsOneWidget);
    expect(find.text('Salary'), findsNothing);
    // Coin still shows IN from the day KPI.
    expect(find.text(formatInr(100)), findsWidgets);
    expect(find.text(formatInr(0)), findsWidgets);
  });

  testWidgets('DayStripTeaser shows day OUT/IN and opens coin screen',
      (tester) async {
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'food',
          amount: 88.88,
          isCredit: false,
          category: SpendCategory.food,
          merchant: 'TeaserFood',
        ),
        tx(
          id: 'pay',
          amount: 200.00,
          isCredit: true,
          category: SpendCategory.income,
          merchant: 'TeaserPay',
          offset: const Duration(hours: 1),
        ),
      ]);

    await tester.pumpWidget(
      buildTestApp(
        settings: settings,
        store: store,
        child: Scaffold(
          body: DayStripTeaser(initialDay: day),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('out ${formatInr(88.88)}  in ${formatInr(200.00)}'),
      findsOneWidget,
    );

    await tester.tap(find.text('DAY'));
    await tester.pumpAndSettle();

    expect(find.text('PAISA'), findsOneWidget);
    expect(find.text('SAT 15 AUG'), findsOneWidget);
    expect(find.text('TeaserFood'), findsOneWidget);
    expect(find.text(formatInr(88.88)), findsWidgets);
  });

  testWidgets('self-transfer MOVE badges; coin OUT/IN exclude both legs',
      (tester) async {
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'xfer_out',
          amount: 1500.75,
          isCredit: false,
          category: SpendCategory.transfer,
          bank: 'SBI',
          mask: '••••0429',
          merchant: 'NEFT to Axis',
        ),
        tx(
          id: 'xfer_in',
          amount: 1500.75,
          isCredit: true,
          category: SpendCategory.income,
          bank: 'Axis',
          mask: '••••9867',
          merchant: 'Self Transfer',
          offset: const Duration(minutes: 1),
        ),
        tx(
          id: 'food',
          amount: 12.50,
          isCredit: false,
          category: SpendCategory.food,
          merchant: 'Snack',
          offset: const Duration(hours: 3),
        ),
      ]);

    await pumpCoin(tester, store: store);

    expect(find.text('MOVE'), findsNWidgets(2));
    expect(find.text('NEFT to Axis'), findsOneWidget);
    expect(find.text('Self Transfer'), findsOneWidget);
    expect(find.text('Snack'), findsOneWidget);
    expect(find.text(formatInr(12.50)), findsWidgets);
    expect(find.text(formatInr(0)), findsWidgets); // IN = 0
    expect(find.text(formatInr(1500.75)), findsNothing); // not on coin face
  });
}
