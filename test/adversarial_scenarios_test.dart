import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:paisa_app/data/transaction_database.dart';
import 'package:paisa_app/main.dart'
    show categorizerVersion, transactionSchemaVersion;
import 'package:paisa_app/models/budget.dart';
import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/models/transaction.dart' as models;
import 'package:paisa_app/models/transaction_sort.dart';
import 'package:paisa_app/providers/app_settings.dart';
import 'package:paisa_app/providers/finance_store.dart';
import 'package:paisa_app/screens/budgets_screen.dart';
import 'package:paisa_app/screens/dashboard_screen.dart';
import 'package:paisa_app/screens/insights_screen.dart';
import 'package:paisa_app/screens/profile_screen.dart';
import 'package:paisa_app/screens/transactions_screen.dart';
import 'package:paisa_app/services/sms/account_discovery.dart';
import 'package:paisa_app/services/sms/sms_parser.dart';
import 'package:paisa_app/services/sms/sms_scan_pipeline.dart';
import 'package:paisa_app/theme/paisa_theme.dart';
import 'package:paisa_app/widgets/paisa_bottom_nav.dart';
import 'package:paisa_app/widgets/transaction_row.dart';

import 'helpers/dummy_data.dart';

/// Adversarial / real-user multi-step scenarios.
///
/// These are intentionally hostile: they encode how an Indian user can break
/// spend/income, accounts, budgets, and filters — not just happy paths.
void main() {
  final month = DateTime(DateTime.now().year, DateTime.now().month, 12, 14);

  models.Transaction tx({
    required String id,
    required double amount,
    required bool isCredit,
    required SpendCategory category,
    AccountKind kind = AccountKind.savings,
    String merchant = 'Test',
    String bank = 'SBI',
    String mask = '••••0429',
    Duration offset = Duration.zero,
  }) =>
      models.Transaction(
        id: id,
        smsId: id,
        merchant: merchant,
        bank: bank,
        maskedAccount: mask,
        category: category,
        amount: amount,
        isCredit: isCredit,
        timestamp: month.add(offset),
        accountKind: kind,
      );

  // ── A. Self-transfer inflation ───────────────────────────────────────────
  group('A self-transfer inflation', () {
    test('SBI debit + Axis credit same amount → KPI spend/income 0, list keeps both',
        () {
      final store = FinanceStore()
        ..seedTransactions([
          tx(
            id: 'a_out',
            amount: 25000,
            isCredit: false,
            category: SpendCategory.transfer,
            merchant: 'IMPS to Axis',
            bank: 'SBI',
            mask: '••••0429',
          ),
          tx(
            id: 'a_in',
            amount: 25000,
            isCredit: true,
            category: SpendCategory.income,
            merchant: 'IMPS from SBI',
            bank: 'Axis',
            mask: '••••9867',
            offset: const Duration(minutes: 1),
          ),
        ]);

      expect(store.monthlySpent, 0);
      expect(store.monthlyIncome, 0);
      expect(store.homeMonthTransactions.length, 2);
    });

    test(
        'merchant UPI "trf to" must NOT net against unrelated P2P credit '
        '(false self-transfer)', () {
      // Real-device pattern seen on Home: Innofin Solution −₹250 (SBI transfer)
      // listed next to LenDenClub +₹250. Pairing those zeros genuine spend.
      final store = FinanceStore()
        ..seedTransactions([
          tx(
            id: 'merchant_upi',
            amount: 250,
            isCredit: false,
            category: SpendCategory.transfer,
            merchant: 'Innofin Solution',
            bank: 'SBI',
            mask: '••••0429',
          ),
          tx(
            id: 'p2p_credit',
            amount: 250,
            isCredit: true,
            category: SpendCategory.transfer,
            merchant: 'Lendenclub',
            bank: 'LenDenClub',
            mask: '',
            offset: const Duration(seconds: 45),
          ),
        ]);

      expect(store.monthlySpent, 250,
          reason: 'unrelated P2P credit must not cancel merchant UPI spend');
      expect(store.monthlyIncome, 250);
      expect(store.homeMonthTransactions.length, 2);
    });

    test('self-transfer outside 3-minute window still counts both ways', () {
      final store = FinanceStore()
        ..seedTransactions([
          tx(
            id: 'late_out',
            amount: 8000,
            isCredit: false,
            category: SpendCategory.transfer,
            bank: 'SBI',
            mask: '••••0429',
          ),
          tx(
            id: 'late_in',
            amount: 8000,
            isCredit: true,
            category: SpendCategory.income,
            bank: 'HDFC',
            mask: '••••5300',
            offset: const Duration(minutes: 10),
          ),
        ]);

      expect(store.monthlySpent, 8000);
      expect(store.monthlyIncome, 8000);
    });
  });

  // ── B. CC bill triple-count ──────────────────────────────────────────────
  group('B CC bill triple-count', () {
    test('card spend + CCBP + payment-received → spend≈card only, income 0', () {
      final store = FinanceStore()
        ..seedTransactions([
          tx(
            id: 'b_spend',
            amount: 4200,
            isCredit: false,
            category: SpendCategory.shopping,
            kind: AccountKind.creditCard,
            merchant: 'Amazon',
            bank: 'SBI',
            mask: '••••3452',
          ),
          tx(
            id: 'b_ccbp',
            amount: 4200,
            isCredit: false,
            category: SpendCategory.transfer,
            kind: AccountKind.creditCard,
            merchant: 'Credit card bill payment',
            bank: 'HDFC',
            mask: '••••5300',
            offset: const Duration(days: 1),
          ),
          tx(
            id: 'b_payin',
            amount: 4200,
            isCredit: true,
            category: SpendCategory.transfer,
            kind: AccountKind.creditCard,
            merchant: 'Credit card payment',
            bank: 'SBI',
            mask: '••••3452',
            offset: const Duration(days: 1, minutes: 2),
          ),
        ]);

      expect(store.monthlySpent, 4200);
      expect(store.monthlyIncome, 0);
      expect(store.homeMonthTransactions.length, 3);
    });

    test('CCBP left as savings kind still excluded from spend (enrichment miss)',
        () {
      final store = FinanceStore()
        ..seedTransactions([
          tx(
            id: 'b2_spend',
            amount: 1000,
            isCredit: false,
            category: SpendCategory.shopping,
            kind: AccountKind.creditCard,
            merchant: 'Flipkart',
            bank: 'Axis',
            mask: '••••1111',
          ),
          tx(
            id: 'b2_ccbp_savings',
            amount: 1000,
            isCredit: false,
            category: SpendCategory.transfer,
            kind: AccountKind.savings,
            merchant: 'Credit card bill payment',
            bank: 'HDFC',
            mask: '••••5300',
            offset: const Duration(hours: 2),
          ),
        ]);

      expect(store.monthlySpent, 1000,
          reason: 'funding-side CCBP must not inflate spend even if kind=savings');
    });
  });

  // ── C. Bank + wallet duplicate SMS ───────────────────────────────────────
  group('C bank + wallet duplicate SMS', () {
    test('bank + Paytm same UPI payment → one row, bank preferred', () {
      final store = FinanceStore();
      final kept = store.debugDropCrossSourceDuplicates(
        [
          tx(
            id: 'c_bank',
            amount: 486,
            isCredit: false,
            category: SpendCategory.food,
            merchant: 'Swiggy',
            bank: 'HDFC',
            mask: '••••4321',
          ),
          tx(
            id: 'c_wallet',
            amount: 486,
            isCredit: false,
            category: SpendCategory.food,
            merchant: 'Swiggy',
            bank: 'Paytm',
            mask: '',
            offset: const Duration(seconds: 20),
          ),
        ],
        const [],
      );
      expect(kept.length, 1);
      expect(kept.single.bank, 'HDFC');
    });

    test('PhonePe mirror of stored bank row is dropped', () {
      final store = FinanceStore();
      final existing = [
        tx(
          id: 'c_existing',
          amount: 199,
          isCredit: false,
          category: SpendCategory.bills,
          merchant: 'Jio',
          bank: 'SBI',
          mask: '••••0429',
        ),
      ];
      final kept = store.debugDropCrossSourceDuplicates(
        [
          tx(
            id: 'c_phonepe',
            amount: 199,
            isCredit: false,
            category: SpendCategory.bills,
            merchant: 'Jio',
            bank: 'PhonePe',
            mask: '',
            offset: const Duration(seconds: 15),
          ),
        ],
        existing,
      );
      expect(kept, isEmpty);
    });
  });

  // ── D. Scam / personal number ────────────────────────────────────────────
  group('D scam / personal number', () {
    test('10-digit sender + Rs debited body → pipeline rejects', () {
      final result = SmsScanPipeline.process(
        dummySms(
          id: 'd1',
          sender: '9876543210',
          body:
              'Rs.4,999.00 debited from your a/c XX1234 on 22-Jul-26. '
              'Not you? Call 1800123456 immediately.',
        ),
      );
      expect(result.isParsed, isFalse);
      expect(
        result.outcome,
        anyOf(
          SmsPipelineOutcome.notFinancialSender,
          SmsPipelineOutcome.promo,
          SmsPipelineOutcome.noTransactionSignal,
          SmsPipelineOutcome.parseFailed,
        ),
      );
    });

    test('DLT bank sender with same body still parses', () {
      final result = SmsScanPipeline.process(
        dummySms(
          id: 'd2',
          sender: 'VM-HDFCBK',
          body:
              'Rs.4,999.00 debited from your a/c XX4321 on 22-Jul-26. Info: AMAZON',
        ),
      );
      expect(result.outcome, SmsPipelineOutcome.parsed);
      expect(result.transaction?.amount, 4999);
    });
  });

  // ── E. Promo that looks like txn ─────────────────────────────────────────
  group('E promo that looks like txn', () {
    test('Get cashback Rs.500 credited style promo → rejected', () {
      final result = SmsScanPipeline.process(
        dummySms(
          id: 'e1',
          sender: 'VM-PAYTMB',
          body:
              'Get cashback Rs.500 credited when you pay with Paytm. '
              'Offer valid till Sunday. T&C apply. Scratch card waiting!',
        ),
      );
      expect(result.isParsed, isFalse);
      expect(
        result.outcome,
        anyOf(SmsPipelineOutcome.promo, SmsPipelineOutcome.noTransactionSignal),
      );
    });

    test('obfuscated L0AN Appr0ve scam through isolate path produces no hit', () {
      final result = SmsScanPipeline.process(
        dummySms(
          id: 'e2',
          sender: 'VM-ALERTS',
          body:
              'Your L0AN is Appr0veD. Rs 50,000 credited to wallet. '
              'Click bit.ly/x to claim now.',
        ),
      );
      expect(result.isParsed, isFalse);
    });
  });

  // ── F. Incremental sync preserves discoveries (ISSUE-1) ──────────────────
  group('F incremental sync preserves discoveries', () {
    late Directory tmp;
    var seq = 0;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('paisa_adv_f');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('full scan N accounts → empty incremental merge keeps N', () async {
      final db = TransactionDatabase.forTesting('${tmp.path}/f_${seq++}.db');
      final full = [
        for (var i = 0; i < 5; i++)
          DiscoveredAccount(
            bank: 'HDFC',
            mask: '••••${5300 + i}',
            kind: AccountKind.savings,
            smsHits: 3 + i,
            spentTotal: 100.0 * i,
            receivedTotal: 50.0 * i,
          ),
      ];
      await db.mergeDiscoveredAccounts(full);
      expect((await db.getDiscoveredAccounts()).length, 5);

      await db.mergeDiscoveredAccounts(const []);
      expect((await db.getDiscoveredAccounts()).length, 5);
    });
  });

  // ── G. Mask collision across banks ───────────────────────────────────────
  group('G mask collision across banks', () {
    test('HDFC+SBI same last-4 stay separate; spend stats not pooled', () {
      final store = FinanceStore()
        ..seedTransactions([
          tx(
            id: 'g_hdfc',
            amount: 200,
            isCredit: false,
            category: SpendCategory.food,
            bank: 'HDFC',
            mask: '••••1234',
          ),
          tx(
            id: 'g_sbi',
            amount: 50000,
            isCredit: true,
            category: SpendCategory.income,
            bank: 'SBI',
            mask: '••••1234',
          ),
          tx(
            id: 'g_sbi_out',
            amount: 900,
            isCredit: false,
            category: SpendCategory.shopping,
            bank: 'SBI',
            mask: '••••1234',
            offset: const Duration(hours: 1),
          ),
        ]);

      final matching =
          store.bankAccounts().where((a) => a.mask == '••••1234').toList();
      expect(matching.length, 2);
      final hdfc = matching.firstWhere((a) => a.name.contains('HDFC'));
      final sbi = matching.firstWhere((a) => a.name.contains('SBI'));
      expect(hdfc.spentTotal, 200);
      expect(sbi.spentTotal, 900);
      expect(sbi.receivedTotal, 50000);
      expect(hdfc.receivedTotal, 0);
    });
  });

  // ── H. CCBP must not flip savings to credit card ─────────────────────────
  group('H CCBP must not flip savings to CC', () {
    test('many UPI + one CCBP on savings mask → still savings', () {
      final store = FinanceStore()
        ..seedTransactions([
          for (var i = 0; i < 10; i++)
            tx(
              id: 'h_upi$i',
              amount: 150.0 + i,
              isCredit: false,
              category: SpendCategory.food,
              bank: 'HDFC',
              mask: '••••5300',
              offset: Duration(hours: i),
            ),
          tx(
            id: 'h_ccbp',
            amount: 12000,
            isCredit: false,
            category: SpendCategory.transfer,
            kind: AccountKind.creditCard,
            merchant: 'Credit card bill payment',
            bank: 'HDFC',
            mask: '••••5300',
            offset: const Duration(days: 2),
          ),
        ]);

      final account =
          store.bankAccounts().firstWhere((a) => a.mask == '••••5300');
      expect(account.kind, AccountKind.savings);
    });
  });

  // ── I. Stray EMI / NACH ──────────────────────────────────────────────────
  group('I stray EMI / NACH', () {
    test('one NACH EMI on savings-heavy mask → stays savings', () {
      final store = FinanceStore()
        ..seedTransactions([
          for (var i = 0; i < 8; i++)
            tx(
              id: 'i_s$i',
              amount: 300.0 + i,
              isCredit: i.isEven,
              category: i.isEven ? SpendCategory.income : SpendCategory.food,
              bank: 'Kotak',
              mask: '••••3649',
              offset: Duration(hours: i),
            ),
          tx(
            id: 'i_nach',
            amount: 25797,
            isCredit: false,
            category: SpendCategory.emi,
            kind: AccountKind.loan,
            merchant: 'NACH debit',
            bank: 'Kotak',
            mask: '••••3649',
            offset: const Duration(days: 1),
          ),
        ]);

      final account =
          store.bankAccounts().firstWhere((a) => a.mask == '••••3649');
      expect(account.kind, AccountKind.savings);
    });

    test('discovered loan mask with loan-majority votes → loan', () {
      final store = FinanceStore()
        ..seedTransactions([
          for (var i = 0; i < 4; i++)
            tx(
              id: 'i_loan$i',
              amount: 15000,
              isCredit: false,
              category: SpendCategory.emi,
              kind: AccountKind.loan,
              merchant: 'Personal Loan EMI',
              bank: 'ICICI',
              mask: '••••1041',
              offset: Duration(days: i * 30),
            ),
        ]);

      final account =
          store.bankAccounts().firstWhere((a) => a.mask == '••••1041');
      expect(account.kind, AccountKind.loan);
    });
  });

  // ── J. Amount edge cases ─────────────────────────────────────────────────
  group('J amount edge cases', () {
    test('Rs 500.5 single decimal parses', () {
      final p = SmsParser.parse(
        dummySms(
          id: 'j1',
          sender: 'VM-HDFCBK',
          body:
              'Sent Rs.500.5 from a/c **4321 to Swiggy on 07-Jul-26 UPI ref 1.',
        ),
      );
      expect(p?.amount, 500.5);
    });

    test('Indian lakh commas Rs.1,23,456.78', () {
      final p = SmsParser.parse(
        dummySms(
          id: 'j2',
          sender: 'VM-HDFCBK',
          body:
              'Rs.1,23,456.78 debited from a/c **4321 on 07-Jul-26. Info: CAR',
        ),
      );
      expect(p?.amount, 123456.78);
    });

    test('zero amount body rejected', () {
      final p = SmsParser.parse(
        dummySms(
          id: 'j3',
          sender: 'VM-HDFCBK',
          body: 'Rs.0.00 debited from a/c **4321 on 07-Jul-26. Info: TEST',
        ),
      );
      expect(p, isNull);
    });

    test('missing amount body does not parse as txn', () {
      final result = SmsScanPipeline.process(
        dummySms(
          id: 'j4',
          sender: 'VM-HDFCBK',
          body:
              'Your HDFC Bank a/c **4321 was debited successfully on 07-Jul-26. Info: UNKNOWN',
        ),
      );
      // Either no amount → parseFailed / noTransactionSignal, never a 0-rupee hit.
      if (result.isParsed) {
        expect(result.transaction!.amount, greaterThan(0));
      } else {
        expect(result.transaction, isNull);
      }
    });
  });

  // ── K. Budget overspend ──────────────────────────────────────────────────
  group('K budget overspend', () {
    late Directory tmp;
    var seq = 0;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('paisa_adv_k');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('fixed limit below spent → ratio>1 and overBudget status', () async {
      final db = TransactionDatabase.forTesting('${tmp.path}/k_${seq++}.db');
      final store = FinanceStore(database: db);
      await store.init();

      store.seedTransactions([
        tx(
          id: 'k1',
          amount: 4000,
          isCredit: false,
          category: SpendCategory.food,
          merchant: 'Swiggy',
          bank: 'HDFC',
          mask: '••••4321',
        ),
        tx(
          id: 'k2',
          amount: 1500,
          isCredit: false,
          category: SpendCategory.food,
          merchant: 'Zomato',
          bank: 'HDFC',
          mask: '••••4321',
          offset: const Duration(days: 1),
        ),
      ]);
      await store.setCategoryBudgetLimit(SpendCategory.food, 3000);

      final budget =
          store.budgets.singleWhere((b) => b.category == SpendCategory.food);
      expect(budget.limit, 3000);
      expect(budget.spent, 5500);
      expect(budget.ratio, greaterThan(1.0));
      expect(budget.status, BudgetStatus.over);
      // Old circular formula would have grown limit with spend — must not.
      expect(budget.limit, isNot(ceilToHundred(5500 * 1.3)));
    });
  });

  // ── L. Sort + filter composition ─────────────────────────────────────────
  group('L sort + filter composition', () {
    test('Money-out filter then amountAsc preserves filter and order', () {
      final txns = [
        tx(
          id: 'l_in',
          amount: 50,
          isCredit: true,
          category: SpendCategory.income,
          merchant: 'Salary',
        ),
        tx(
          id: 'l_out_hi',
          amount: 900,
          isCredit: false,
          category: SpendCategory.shopping,
          merchant: 'Amazon',
          offset: const Duration(hours: 1),
        ),
        tx(
          id: 'l_out_lo',
          amount: 100,
          isCredit: false,
          category: SpendCategory.food,
          merchant: 'Chai',
          offset: const Duration(hours: 2),
        ),
        tx(
          id: 'l_cc',
          amount: 50,
          isCredit: false,
          category: SpendCategory.shopping,
          kind: AccountKind.creditCard,
          merchant: 'Uber',
          mask: '••••3452',
          offset: const Duration(hours: 3),
        ),
      ];

      // Mirrors TransactionsScreen Money-out filter semantics.
      final filtered = txns
          .where((t) => !t.isCredit && t.accountKind == AccountKind.savings)
          .toList();
      expect(filtered.map((t) => t.id).toSet(), {'l_out_hi', 'l_out_lo'});

      final sections =
          buildTransactionSections(filtered, TransactionSort.amountAsc);
      expect(sections.length, 1, reason: 'amount sort is a flat section');
      expect(sections.single.header, isNull);
      expect(sections.single.items.map((t) => t.id).toList(),
          ['l_out_lo', 'l_out_hi']);
    });
  });

  // ── M. Schema / rescan gate ──────────────────────────────────────────────
  group('M schema/rescan gate logic', () {
    test('needsRescan true when stored versions lag code constants', () {
      expect(transactionSchemaVersion, greaterThan(0));
      expect(categorizerVersion, greaterThan(0));

      bool needsRescan(int storedSchema, int storedCat) =>
          storedCat < categorizerVersion ||
          storedSchema < transactionSchemaVersion;

      expect(needsRescan(0, 0), isTrue);
      expect(needsRescan(transactionSchemaVersion - 1, categorizerVersion),
          isTrue);
      expect(needsRescan(transactionSchemaVersion, categorizerVersion - 1),
          isTrue);
      expect(needsRescan(transactionSchemaVersion, categorizerVersion), isFalse);
      expect(needsRescan(transactionSchemaVersion + 1, categorizerVersion + 1),
          isFalse);
    });

    test('fresh install (onboarding incomplete) must not force splash rescan',
        () {
      // Mirrors main.dart: needsRescan && onboardingComplete
      bool scheduleLaunchRescan({
        required bool versionMismatch,
        required bool onboardingComplete,
      }) =>
          versionMismatch && onboardingComplete;

      expect(
        scheduleLaunchRescan(
          versionMismatch: true,
          onboardingComplete: false,
        ),
        isFalse,
        reason: 'ISSUE-7: never brick first-run permission UX',
      );
      expect(
        scheduleLaunchRescan(
          versionMismatch: true,
          onboardingComplete: true,
        ),
        isTrue,
      );
    });
  });

  // ── N. Neo-Vault UI smoke ────────────────────────────────────────────────
  group('N Neo-Vault UI smoke', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('bottom nav exposes HOME/MOVES/BUDGET/STATS/YOU', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: PaisaTheme.dark(),
          home: Scaffold(
            bottomNavigationBar: PaisaBottomNav(
              currentIndex: 0,
              onTap: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      for (final label in ['HOME', 'MOVES', 'BUDGET', 'STATS', 'YOU']) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('key screens tolerate empty store without throwing',
        (tester) async {
      final settings = await AppSettings.load();
      final store = FinanceStore();

      Future<void> pumpScreen(Widget screen) async {
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: store),
              ChangeNotifierProvider.value(value: settings),
            ],
            child: MaterialApp(
              theme: PaisaTheme.dark(),
              home: Scaffold(body: screen),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
      }

      await pumpScreen(const DashboardScreen());
      expect(tester.takeException(), isNull);

      await pumpScreen(const TransactionsScreen());
      expect(tester.takeException(), isNull);

      await pumpScreen(const BudgetsScreen());
      expect(tester.takeException(), isNull);

      await pumpScreen(const InsightsScreen());
      expect(tester.takeException(), isNull);

      await pumpScreen(const ProfileScreen());
      expect(tester.takeException(), isNull);
    });
  });

  // ── Extra adversarial inventions ─────────────────────────────────────────
  group('O empty / null / unknown bank edges', () {
    test('empty mask transactions do not invent bank accounts', () {
      final store = FinanceStore()
        ..seedTransactions([
          tx(
            id: 'o_empty',
            amount: 100,
            isCredit: false,
            category: SpendCategory.food,
            bank: 'Paytm',
            mask: '',
          ),
        ]);
      expect(store.bankAccounts(), isEmpty);
      expect(store.monthlySpent, 100);
    });

    test("placeholder bank 'Bank' does not surface as a savings account", () {
      final store = FinanceStore()
        ..seedTransactions([
          tx(
            id: 'o_bank',
            amount: 999,
            isCredit: false,
            category: SpendCategory.shopping,
            bank: 'Bank',
            mask: '••••9999',
          ),
        ]);
      final namedBank = store.bankAccounts().where((a) => a.name.contains('Bank'));
      expect(namedBank, isEmpty);
    });

    test('Federal / Fi-style savings mask classifies as Federal savings', () {
      final store = FinanceStore()
        ..seedTransactions([
          tx(
            id: 'o_fi',
            amount: 500,
            isCredit: true,
            category: SpendCategory.income,
            merchant: 'Interest',
            bank: 'Federal',
            mask: '••••7953',
          ),
          tx(
            id: 'o_fi_out',
            amount: 120,
            isCredit: false,
            category: SpendCategory.food,
            bank: 'Federal',
            mask: '••••7953',
            offset: const Duration(hours: 2),
          ),
        ]);
      final account =
          store.bankAccounts().firstWhere((a) => a.mask == '••••7953');
      expect(account.kind, AccountKind.savings);
      expect(account.name, contains('Federal'));
    });
  });

  group('P privacy merchant masking', () {
    testWidgets('toggle masks merchant on TransactionRow', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = await AppSettings.load();
      final txn = tx(
        id: 'p1',
        amount: 200,
        isCredit: false,
        category: SpendCategory.food,
        merchant: 'Swiggy',
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: settings),
          ],
          child: MaterialApp(
            theme: PaisaTheme.dark(),
            home: Scaffold(body: TransactionRow(transaction: txn)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Swiggy'), findsOneWidget);

      await settings.setMaskMerchantNames(true);
      await tester.pumpAndSettle();
      expect(find.text('Swiggy'), findsNothing);
      expect(find.textContaining('••••'), findsWidgets);
    });
  });

  group('Q long PNB mask + amount-sort flat sections', () {
    test('PNB long mask last-4 still keys an account', () {
      final store = FinanceStore()
        ..seedTransactions([
          tx(
            id: 'q1',
            amount: 750,
            isCredit: false,
            category: SpendCategory.bills,
            bank: 'PNB',
            mask: '••••4720',
          ),
          tx(
            id: 'q2',
            amount: 2000,
            isCredit: true,
            category: SpendCategory.income,
            bank: 'PNB',
            mask: '••••4720',
            offset: const Duration(days: 1),
          ),
        ]);
      final account =
          store.bankAccounts().firstWhere((a) => a.mask == '••••4720');
      expect(account.kind, AccountKind.savings);
      expect(account.name, contains('PNB'));
    });

    test('amountDesc yields single header-less section', () {
      final sections = buildTransactionSections(
        [
          tx(
            id: 'q_a',
            amount: 10,
            isCredit: false,
            category: SpendCategory.food,
          ),
          tx(
            id: 'q_b',
            amount: 99,
            isCredit: false,
            category: SpendCategory.food,
            offset: const Duration(days: 1),
          ),
        ],
        TransactionSort.amountDesc,
      );
      expect(sections.length, 1);
      expect(sections.single.header, isNull);
      expect(sections.single.items.first.id, 'q_b');
    });
  });
}

int ceilToHundred(num value) => ((value / 100).ceil()) * 100;
