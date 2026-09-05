import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/data/transaction_database.dart';
import 'package:paisa_app/models/budget.dart';
import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/models/transaction.dart' as models;
import 'package:paisa_app/providers/app_settings.dart';
import 'package:paisa_app/providers/finance_store.dart';
import 'package:paisa_app/screens/budgets_screen.dart';
import 'package:paisa_app/screens/reports_screen.dart';
import 'package:paisa_app/screens/transactions_screen.dart';
import 'package:paisa_app/services/sms/parsed_sms_transaction.dart';
import 'package:paisa_app/services/sms/sms_scan_pipeline.dart';
import 'package:paisa_app/widgets/paisa_bottom_nav.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/dummy_data.dart';
import 'helpers/test_harness.dart';

/// End-to-end integration flows across SMS ingest, ledger, Reports, Budget,
/// navigation, and persistence. Uses in-memory / FFI SQLite — no device needed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  var seq = 0;
  late AppSettings settings;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await AppSettings.load();
    tmp = Directory.systemTemp.createTempSync('paisa_e2e');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  TransactionDatabase freshDb() =>
      TransactionDatabase.forTesting('${tmp.path}/e2e_${seq++}.db');

  FinanceStore freshStore(TransactionDatabase db) => FinanceStore(database: db);

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, 12);

  models.Transaction debit({
    required String id,
    required SpendCategory category,
    required double amount,
    DateTime? at,
    String merchant = 'Shop',
  }) =>
      models.Transaction(
        id: id,
        smsId: id,
        merchant: merchant,
        bank: 'HDFC',
        maskedAccount: '••••4321',
        category: category,
        amount: amount,
        isCredit: false,
        timestamp: at ?? today,
      );

  group('SMS ingest → ledger', () {
    test('pipeline parses debit and lands in FinanceStore list', () async {
      final parsed = SmsScanPipeline.process(
        SmsMessageInput(
          id: 'sms_e2e',
          sender: 'VM-HDFCBK',
          body:
              'Sent Rs.486.00 from a/c **4321 to Swiggy on 07-Jul-26 UPI ref 5521.',
          timestamp: today,
        ),
      );
      expect(parsed.outcome, SmsPipelineOutcome.parsed);
      expect(parsed.transaction?.merchant, 'Swiggy');
      expect(parsed.transaction?.amount, 486);

      final store = FinanceStore()
        ..seedTransactions([
          dummyTxn(
            id: 'from_sms',
            merchant: parsed.transaction!.merchant,
            amount: parsed.transaction!.amount,
            isCredit: false,
            category: SpendCategory.food,
            timestamp: today,
          ),
        ]);

      expect(store.transactions.length, 1);
      expect(store.transactions.first.merchant, 'Swiggy');
    });
  });

  group('manual mint persistence', () {
    test('addManualTransaction survives DB reload', () async {
      final path = '${tmp.path}/manual_persist.db';
      final db = TransactionDatabase.forTesting(path);
      final store = freshStore(db);
      await store.init();

      final tx = await store.addManualTransaction(
        amount: 250,
        date: today,
        category: SpendCategory.food,
        message: 'Cash · Food',
        isCredit: false,
        now: now,
      );

      expect(tx.id.startsWith('manual_'), isTrue);

      final reloaded = freshStore(TransactionDatabase.forTesting(path));
      await reloaded.init();
      expect(reloaded.transactions.length, 1);
      expect(reloaded.transactions.single.merchant, 'Cash · Food');
      expect(reloaded.transactions.single.amount, 250);
    });
  });

  group('Reports KPIs', () {
    test('this month spent/income match elapsed-month fixtures', () {
      final store = FinanceStore()..seedTransactions(dummyTransactionHistory());
      final (start, end) = reportsMonthBounds();
      final report = store.buildReport(start, end);

      expect(report.income, greaterThan(0));
      expect(report.spent, greaterThan(0));
      expect(report.transactionCount, greaterThan(0));
      expect(report.net, report.income - report.spent);
    });

    test('this year includes prior months in dummy set', () {
      final store = FinanceStore()..seedTransactions(dummyTransactionHistory());
      final range = store.reportsThisYearRange;
      final report = store.buildReport(range.start, range.end);

      expect(report.transactionCount, greaterThan(6));
      expect(report.income, greaterThan(report.spent));
    });
  });

  group('Budget ↔ Reports parity', () {
    test('monthly budgetSpent equals Reports this-month spent', () async {
      final store = freshStore(freshDb());
      await store.init();
      store.seedTransactions(dummyTransactionHistory());

      final range = store.reportsThisMonthRange;
      final report = store.buildReport(range.start, range.end);
      expect(store.budgetSpentFor(BudgetPeriod.monthly), report.spent);
    });

    test('each category envelope spent matches Reports categorySpending', () async {
      final store = freshStore(freshDb());
      await store.init();
      store.seedTransactions(dummyTransactionHistory());

      final report = store.budgetReportFor(BudgetPeriod.monthly);
      for (final b in store.budgetsFor(BudgetPeriod.monthly)) {
        expect(
          b.spent,
          report.categorySpending[b.category] ?? 0,
          reason: b.category.name,
        );
      }
    });

    test('yearly toggle uses YTD window', () async {
      final store = freshStore(freshDb());
      await store.init();
      store.seedTransactions(dummyTransactionHistory());
      await store.setBudgetPeriod(BudgetPeriod.yearly);

      final report = store.budgetReportFor(BudgetPeriod.yearly);
      expect(store.budgetSpentFor(BudgetPeriod.yearly), report.spent);
    });
  });

  group('corner cases', () {
    test('empty store yields zero KPIs and unset budgets', () async {
      final store = freshStore(freshDb());
      await store.init();

      final (start, end) = reportsMonthBounds();
      final report = store.buildReport(start, end);
      expect(report.isEmpty, isTrue);
      expect(store.monthlySpent, 0);
      expect(store.monthlyIncome, 0);
      expect(store.budgets.every((b) => b.isUnset), isTrue);
    });

    test('transfer category counts in budget and Reports spend', () async {
      final store = freshStore(freshDb());
      await store.init();
      store.seedTransactions([
        debit(
          id: 'xfer',
          category: SpendCategory.transfer,
          amount: 1200,
          merchant: 'UPI Transfer',
        ),
      ]);

      final report = store.budgetReportFor(BudgetPeriod.monthly);
      final transfer =
          store.budgets.singleWhere((b) => b.category == SpendCategory.transfer);
      expect(transfer.spent, 1200);
      expect(report.categorySpending[SpendCategory.transfer], 1200);
    });

    test('over-budget when plan below spent', () async {
      final store = freshStore(freshDb());
      await store.init();
      store.seedTransactions([
        debit(id: 'f1', category: SpendCategory.food, amount: 800),
        debit(
          id: 'f2',
          category: SpendCategory.food,
          amount: 400,
          at: today.add(const Duration(hours: 2)),
        ),
      ]);
      await store.setCategoryBudgetLimit(SpendCategory.food, 500);

      final food =
          store.budgets.singleWhere((b) => b.category == SpendCategory.food);
      expect(food.spent, 1200);
      expect(food.status, BudgetStatus.over);
      expect(food.ratio, greaterThan(1));
    });

    test('period boundary: only txs on or before today in this-month report',
        () {
      final futureDay = now.day < 28 ? now.day + 1 : now.day;
      final store = FinanceStore()
        ..seedTransactions([
          debit(
            id: 'today',
            category: SpendCategory.food,
            amount: 100,
            at: today,
          ),
          debit(
            id: 'future',
            category: SpendCategory.food,
            amount: 999,
            at: DateTime(now.year, now.month, futureDay, 15),
          ),
        ]);

      final (start, end) = reportsMonthBounds();
      final report = store.buildReport(start, end);
      if (futureDay > now.day) {
        expect(report.spent, 100);
      } else {
        expect(report.spent, 1100);
      }
    });
  });

  group('navigation + UI smoke', () {
    testWidgets('bottom nav exposes all tab labels', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: PaisaBottomNav(
              currentIndex: 0,
              onTap: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      for (final label in [
        'HOME',
        'TRANSACTIONS',
        'BUDGET',
        'STATS',
        'YOU',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('transactions screen lists seeded merchants', (tester) async {
      final store = FinanceStore()..seedTransactions(dummyTransactionHistory());

      await tester.pumpWidget(
        buildTestApp(
          settings: settings,
          store: store,
          child: const TransactionsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Swiggy'), findsWidgets);
      expect(find.text('Salary'), findsWidgets);
    });

    testWidgets('reports screen shows category and merchant sections',
        (tester) async {
      final store = FinanceStore()..seedTransactions(dummyTransactionHistory());

      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildTestApp(
          settings: settings,
          store: store,
          child: const ReportsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Where money went'), findsOneWidget);
      expect(find.text('Where money came from'), findsOneWidget);
      expect(find.text('Top merchants'), findsOneWidget);
    });

    testWidgets('budget screen shows all 10 envelope categories', (tester) async {
      final store = FinanceStore()..seedTransactions(dummyTransactionHistory());

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

      expect(find.text('MONTH ENVELOPES'), findsOneWidget);
      expect(
        find.text('MONTHLY'),
        findsOneWidget,
      );
      for (final c in FinanceStore.budgetableCategories) {
        expect(find.text(CategoryInfo.forCategory(c).label), findsOneWidget);
      }
    });
  });
}
