import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/models/transaction.dart';
import 'package:paisa_app/providers/app_settings.dart';
import 'package:paisa_app/providers/finance_store.dart';
import 'package:paisa_app/screens/insights_screen.dart';
import 'package:paisa_app/services/sms/account_discovery.dart';
import 'package:paisa_app/utils/formatters.dart';
import 'package:paisa_app/widgets/pulse_calendar_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/test_harness.dart';

/// Stats = period chips → Pulse Ribbon → period Ledger Coin → Share → merchants.
/// One filter drives graph, coin, categories, and merchants together.
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
    tester.view.physicalSize = const Size(400, 2800);
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

  testWidgets('period coin mints exact spend / income for selected range',
      (tester) async {
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

    final range = store.statsSpiralRange(StatsSpiralPeriod.oneMonth);
    final report = store.buildReport(range.start, range.end);
    expect(report.spent, 441.00);
    expect(report.income, 5000.00);

    await pumpStats(tester, store);

    // Period chips sit under STATS header (before graph / coin).
    expect(find.text('PAISA'), findsOneWidget);
    expect(find.text('STATS'), findsOneWidget);
    expect(find.byKey(const Key('spiral_filters')), findsOneWidget);
    expect(find.byKey(const Key('spiral_filter_1m')), findsOneWidget);
    expect(find.byKey(const Key('spiral_filter_6m')), findsOneWidget);
    expect(find.byKey(const Key('spiral_filter_1y')), findsOneWidget);
    expect(find.byKey(const Key('spiral_filter_all')), findsOneWidget);
    expect(find.byKey(const Key('spiral_filter_custom')), findsOneWidget);

    // Graph first, then period coin.
    expect(find.text('SPEND'), findsOneWidget);
    expect(find.text('PULSE RIBBON'), findsOneWidget);
    expect(find.byKey(const Key('pulse_ribbon_chart')), findsOneWidget);
    expect(find.textContaining('X = time'), findsOneWidget);
    expect(find.text('PERIOD SPENT'), findsNothing);
    expect(find.text('TOP CATEGORY'), findsNothing);

    expect(find.text('LEDGER'), findsOneWidget);
    expect(find.text('1 MONTH'), findsOneWidget);
    expect(find.text('SPENT'), findsOneWidget);
    expect(find.text(formatInr(441.00)), findsWidgets);
    expect(find.text(formatInr(5000.00)), findsOneWidget);

    // Legends scoped to period report.
    expect(find.text('DAILY AVG'), findsOneWidget);
    expect(find.text('PEAK DAY'), findsOneWidget);
    expect(find.text('NET'), findsOneWidget);
    expect(find.text(formatInr(report.highestDaySpend)), findsWidgets);
    expect(
      find.text(formatAmount(report.net, isCredit: true)),
      findsOneWidget,
    );

    // Compact share bar (not full category ledger).
    expect(find.text('SHARE'), findsOneWidget);
    expect(find.text('BY CATEGORY'), findsNothing);
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Shopping'), findsOneWidget);

    expect(find.text('MINT LEDGER'), findsNothing);
    expect(find.text('MINT RHYTHM'), findsNothing);
    expect(find.text('THIS MONTH PULSE'), findsNothing);
    expect(find.text('SPEND SPIRAL'), findsNothing);

    // Top merchants + See All Moves (Reports Ledger for selected period).
    expect(find.text('TOP MERCHANTS'), findsOneWidget);
    expect(find.text('Swiggy'), findsOneWidget);
    expect(find.text('Blinkit'), findsOneWidget);
    expect(find.text('SEE ALL MOVES'), findsOneWidget);
    expect(find.byKey(const Key('stats_see_all_moves')), findsOneWidget);

    // REPORTS chrome + PEAK DAY + SEE ALL MOVES — no category row chevrons.
    final chevrons = find.byIcon(Icons.chevron_right_rounded);
    expect(chevrons, findsNWidgets(3));
  });

  testWidgets('period filter chips refresh coin + share + merchants together',
      (tester) async {
    final now = DateTime.now();
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'recent',
          amount: 100,
          isCredit: false,
          category: SpendCategory.food,
          merchant: 'Near',
          timestamp: now.subtract(const Duration(days: 3)),
        ),
        tx(
          id: 'old',
          amount: 900,
          isCredit: false,
          category: SpendCategory.shopping,
          merchant: 'Far',
          timestamp: now.subtract(const Duration(days: 200)),
        ),
      ]);

    await pumpStats(tester, store);

    // Default 1M — only recent spend in window.
    expect(find.text(formatInr(100)), findsWidgets);
    expect(find.text('Near'), findsOneWidget);
    expect(find.text('Far'), findsNothing);
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Shopping'), findsNothing);
    expect(find.text('1 MONTH'), findsOneWidget);

    await tester.tap(find.byKey(const Key('spiral_filter_1y')));
    await tester.pumpAndSettle();

    // 1Y includes both buckets — coin, share, merchants all refresh.
    expect(find.text('1 YEAR'), findsOneWidget);
    expect(find.text(formatInr(1000)), findsWidgets);
    expect(find.text('Near'), findsOneWidget);
    expect(find.text('Far'), findsOneWidget);
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Shopping'), findsOneWidget);
  });

  testWidgets('pulse ribbon empty state when selected range has no spend',
      (tester) async {
    final now = DateTime.now();
    // Old OUT only — outside default 1M window.
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'old-only',
          amount: 250,
          isCredit: false,
          category: SpendCategory.shopping,
          merchant: 'Far',
          timestamp: now.subtract(const Duration(days: 120)),
        ),
      ]);

    await pumpStats(tester, store);

    expect(find.text('SPEND'), findsOneWidget);
    expect(find.text('PULSE RIBBON'), findsOneWidget);
    expect(find.byKey(const Key('pulse_ribbon_chart_empty')), findsOneWidget);
    expect(find.text('No spend in this range'), findsOneWidget);
    // Period coin still shows for the empty window.
    expect(find.text('LEDGER'), findsOneWidget);
    expect(find.text('1 MONTH'), findsOneWidget);
    expect(find.text('SHARE'), findsNothing);
    expect(find.text('TOP MERCHANTS'), findsNothing);
  });

  testWidgets('CUSTOM chip opens Pulse Calendar range picker', (tester) async {
    final now = DateTime.now();
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'food',
          amount: 50,
          isCredit: false,
          category: SpendCategory.food,
          timestamp: now.subtract(const Duration(days: 2)),
        ),
      ]);

    tester.view.physicalSize = const Size(420, 900);
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

    await tester.tap(find.byKey(const Key('spiral_filter_custom')));
    await tester.pump(); // sheet animates in
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(PulseCalendarSheet), findsOneWidget);
  });

  testWidgets('tapping share legend opens category transactions',
      (tester) async {
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
      ]);

    await pumpStats(tester, store);

    await tester.tap(find.text('Food'));
    await tester.pumpAndSettle();

    expect(find.text('Swiggy'), findsOneWidget);
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

  testWidgets('SEE ALL MOVES opens Reports Ledger for selected period',
      (tester) async {
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
      ]);

    await pumpStats(tester, store);

    await tester.tap(find.byKey(const Key('stats_see_all_moves')));
    await tester.pumpAndSettle();

    // Period Folio with initialRange defaults to Ledger tab + Custom preset.
    expect(find.text('Custom'), findsOneWidget);
    expect(find.text('LEDGER'), findsWidgets);
    expect(find.text('Swiggy'), findsOneWidget);
  });

  testWidgets('empty ledger keeps zeroed coin and scan prompt', (tester) async {
    await pumpStats(tester, FinanceStore());

    expect(find.byKey(const Key('spiral_filters')), findsOneWidget);
    expect(find.text('LEDGER'), findsOneWidget);
    expect(find.text(formatInr(0)), findsWidgets);
    expect(find.text('No transactions yet'), findsOneWidget);
    expect(find.text('Scan SMS now'), findsOneWidget);
    expect(find.text('SHARE'), findsNothing);
    expect(find.text('SPEND'), findsNothing);
    expect(find.text('PULSE RIBBON'), findsNothing);
    expect(find.text('MINT LEDGER'), findsNothing);
    expect(find.text('SPEND SPIRAL'), findsNothing);
    expect(find.text('MINT RHYTHM'), findsNothing);
  });

  test('statsSpiralRange resolves rolling windows', () {
    final clock = DateTime(2026, 9, 5, 15);
    final store = FinanceStore();

    final oneM = store.statsSpiralRange(
      StatsSpiralPeriod.oneMonth,
      clock: clock,
    );
    expect(oneM.start, DateTime(2026, 8, 5));
    expect(oneM.end.year, 2026);
    expect(oneM.end.month, 9);
    expect(oneM.end.day, 5);

    final sixM = store.statsSpiralRange(
      StatsSpiralPeriod.sixMonths,
      clock: clock,
    );
    expect(sixM.start, DateTime(2026, 3, 5));

    final oneY = store.statsSpiralRange(
      StatsSpiralPeriod.oneYear,
      clock: clock,
    );
    expect(oneY.start, DateTime(2025, 9, 5));
  });

  test('spendSeriesInRange daily buckets sum OUT only', () {
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'a',
          amount: 100,
          isCredit: false,
          category: SpendCategory.food,
          timestamp: DateTime(2026, 9, 1, 10),
        ),
        tx(
          id: 'b',
          amount: 50,
          isCredit: false,
          category: SpendCategory.shopping,
          timestamp: DateTime(2026, 9, 2, 12),
        ),
        tx(
          id: 'income',
          amount: 5000,
          isCredit: true,
          category: SpendCategory.income,
          timestamp: DateTime(2026, 9, 1, 9),
        ),
      ]);

    final series = store.spendSeriesInRange(
      DateTime(2026, 9, 1),
      DateTime(2026, 9, 3),
    );
    expect(series, hasLength(3));
    expect(series[0].$2, 100);
    expect(series[1].$2, 50);
    expect(series[2].$2, 0);
  });

  test('spendSeriesInRange uses weekly buckets for long spans', () {
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'w1',
          amount: 10,
          isCredit: false,
          category: SpendCategory.food,
          timestamp: DateTime(2026, 1, 2),
        ),
        tx(
          id: 'w2',
          amount: 20,
          isCredit: false,
          category: SpendCategory.food,
          timestamp: DateTime(2026, 3, 15),
        ),
      ]);

    final series = store.spendSeriesInRange(
      DateTime(2026, 1, 1),
      DateTime(2026, 6, 30),
    );
    // ~181 days → weekly.
    expect(series.length, greaterThan(20));
    expect(series.length, lessThan(40));
    final total = series.fold<double>(0, (m, e) => m + e.$2);
    expect(total, 30);
  });

  test('buildReport highestDay matches peak spend day in range', () {
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'a',
          amount: 40,
          isCredit: false,
          category: SpendCategory.food,
          timestamp: DateTime(2026, 9, 1, 10),
        ),
        tx(
          id: 'b',
          amount: 90,
          isCredit: false,
          category: SpendCategory.shopping,
          timestamp: DateTime(2026, 9, 2, 12),
        ),
      ]);

    final report = store.buildReport(
      DateTime(2026, 9, 1),
      DateTime(2026, 9, 3),
    );
    expect(report.spent, 130);
    expect(report.highestDaySpend, 90);
    expect(report.highestDay, DateTime(2026, 9, 2));
    expect(report.spendCount, 2);
    expect(report.dailyAverage, closeTo(130 / 3, 0.001));
  });

  test('insightsMonthlySpendSeries returns last N months oldest→newest', () {
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month, 10);
    final lastMonth = DateTime(now.year, now.month - 1, 12);
    final twoAgo = DateTime(now.year, now.month - 2, 8);

    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'a',
          amount: 100,
          isCredit: false,
          category: SpendCategory.food,
          timestamp: thisMonth,
        ),
        tx(
          id: 'b',
          amount: 250,
          isCredit: false,
          category: SpendCategory.shopping,
          timestamp: lastMonth,
        ),
        tx(
          id: 'c',
          amount: 50,
          isCredit: false,
          category: SpendCategory.bills,
          timestamp: twoAgo,
        ),
        tx(
          id: 'income',
          amount: 5000,
          isCredit: true,
          category: SpendCategory.income,
          timestamp: thisMonth,
        ),
      ]);

    final series = store.insightsMonthlySpendSeries(count: 6);
    expect(series, hasLength(6));
    expect(series.last.$1.year, now.year);
    expect(series.last.$1.month, now.month);
    expect(series.last.$2, 100);
    expect(series[series.length - 2].$2, 250);
    expect(series[series.length - 3].$2, 50);
    for (var i = 0; i < series.length - 3; i++) {
      expect(series[i].$2, 0);
    }
  });
}
