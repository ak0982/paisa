import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/data/transaction_database.dart';
import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/models/manual_transaction.dart';
import 'package:paisa_app/models/transaction.dart' as models;
import 'package:paisa_app/providers/finance_store.dart';
import 'package:paisa_app/services/sms/account_discovery.dart';
import 'package:paisa_app/services/sms/original_sms_lookup.dart';
import 'package:paisa_app/utils/formatters.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Edge cases, KPIs, filters, validation, ordering, and survival for mint.
void main() {
  late Directory tmp;
  var seq = 0;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('paisa_mint_edges');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  TransactionDatabase freshDb() => TransactionDatabase.forTesting(
        '${tmp.path}/paisa_${seq++}.db',
      );

  FinanceStore freshStore(TransactionDatabase db) => FinanceStore(database: db);

  models.Transaction smsTxn({
    required String id,
    required double amount,
    required DateTime timestamp,
    String merchant = 'SMS Merchant',
    SpendCategory category = SpendCategory.other,
    bool isCredit = false,
    AccountKind kind = AccountKind.savings,
  }) {
    return models.Transaction(
      id: id,
      smsId: id,
      merchant: merchant,
      bank: 'HDFC',
      maskedAccount: '••••1234',
      category: category,
      amount: amount,
      isCredit: isCredit,
      timestamp: timestamp,
      accountKind: kind,
    );
  }

  // Mirrors Transactions screen flow predicates (private enum in transactions_screen).
  bool matchesIn(models.Transaction t) =>
      t.isCredit && t.accountKind == AccountKind.savings;
  bool matchesOut(models.Transaction t) =>
      !t.isCredit && t.accountKind == AccountKind.savings;
  bool isCc(models.Transaction t) {
    if (t.accountKind == AccountKind.creditCard) return true;
    final m = t.merchant.toLowerCase();
    return m.contains('ccbp') ||
        m.contains('credit card bill') ||
        m.contains('credit card payment') ||
        m.contains('bobcard');
  }

  bool isLoan(models.Transaction t) =>
      t.accountKind == AccountKind.loan ||
      (t.category == SpendCategory.emi && !t.isCredit);

  group('validateManualAmount matrix', () {
    final rejects = <(String, double?)>[
      ('null', null),
      ('zero', 0),
      ('negative int', -1),
      ('negative decimal', -0.01),
      ('NaN', double.nan),
      ('+Infinity', double.infinity),
      ('-Infinity', double.negativeInfinity),
      ('tiny rounds to zero', 0.001),
      ('0.004 rounds down to 0', 0.004),
    ];

    for (final (label, amount) in rejects) {
      test('rejects $label', () {
        expect(validateManualAmount(amount), isNotNull);
      });
    }

    final accepts = <(String, double)>[
      ('one paise', 0.01),
      ('half rupee', 0.5),
      ('chai 20', 20),
      ('two decimals', 99.99),
      ('three decimals rounds', 10.125),
      ('lakh', 100000),
      ('10 lakh', 1000000),
      ('1 crore', 10000000),
      ('huge but finite', 999999999.99),
    ];

    for (final (label, amount) in accepts) {
      test('accepts $label ($amount)', () {
        expect(validateManualAmount(amount), isNull);
      });
    }
  });

  group('roundManualAmount', () {
    final cases = <(double, double)>[
      (10.125, 10.13),
      (10.124, 10.12),
      (0.015, 0.02),
      (0.014, 0.01),
      (99.999, 100.0),
      (1.01, 1.01),
      (20, 20),
    ];
    for (final (raw, expected) in cases) {
      test('rounds $raw → $expected', () {
        expect(roundManualAmount(raw), expected);
      });
    }
  });

  group('clampManualDay / manualTimestampForDay matrix', () {
    final now = DateTime(2026, 8, 27, 18, 5, 30);

    final clamps = <(String, DateTime, DateTime)>[
      ('tomorrow', DateTime(2026, 8, 28), DateTime(2026, 8, 27)),
      ('next month', DateTime(2026, 9, 1), DateTime(2026, 8, 27)),
      ('far future', DateTime(2030, 1, 1), DateTime(2026, 8, 27)),
      ('today stays', DateTime(2026, 8, 27), DateTime(2026, 8, 27)),
      ('yesterday', DateTime(2026, 8, 26), DateTime(2026, 8, 26)),
      ('month start', DateTime(2026, 8, 1), DateTime(2026, 8, 1)),
      ('prev month end', DateTime(2026, 7, 31), DateTime(2026, 7, 31)),
      ('year boundary', DateTime(2025, 12, 31), DateTime(2025, 12, 31)),
      ('leap day past', DateTime(2024, 2, 29), DateTime(2024, 2, 29)),
      ('future leap day clamps', DateTime(2028, 2, 29), DateTime(2026, 8, 27)),
    ];

    for (final (label, day, expected) in clamps) {
      test('clamp $label', () {
        expect(clampManualDay(day, now: now), expected);
      });
    }

    test('timestamp today uses wall clock', () {
      expect(
        manualTimestampForDay(DateTime(2026, 8, 27), now: now),
        now,
      );
    });

    test('timestamp past day uses noon', () {
      expect(
        manualTimestampForDay(DateTime(2026, 8, 12), now: now),
        DateTime(2026, 8, 12, 12),
      );
    });

    test('timestamp future day clamps then uses clock (today)', () {
      expect(
        manualTimestampForDay(DateTime(2026, 9, 5), now: now),
        now,
      );
    });
  });

  group('defaultManualMessage + direction for every category', () {
    for (final category in SpendCategory.values) {
      test('$category default message non-empty', () {
        expect(defaultManualMessage(category), isNotEmpty);
      });

      test('$category default isCredit only for income', () {
        expect(
          defaultManualIsCredit(category),
          category == SpendCategory.income,
        );
      });
    }

    test('income forces In semantics for mint defaults', () {
      expect(defaultManualIsCredit(SpendCategory.income), isTrue);
      expect(defaultManualMessage(SpendCategory.income), 'Cash received');
    });

    test('switching food→income flips default direction', () {
      expect(defaultManualIsCredit(SpendCategory.food), isFalse);
      expect(defaultManualIsCredit(SpendCategory.income), isTrue);
    });
  });

  group('newManualTransactionId', () {
    test('prefix manual_ and unique across 50 draws', () {
      final ids = {
        for (var i = 0; i < 50; i++) newManualTransactionId(random: Random(i)),
      };
      expect(ids.length, 50);
      for (final id in ids) {
        expect(id.startsWith('manual_'), isTrue);
        expect(id.startsWith('sms_'), isFalse);
        expect(id.contains('manual_'), isTrue);
      }
    });
  });

  group('empty / whitespace merchant fallback', () {
    final blanks = ['', '   ', '\t', '\n', '  \n  '];
    for (final blank in blanks) {
      test('blank ${blank.length} chars → category default', () async {
        final store = freshStore(freshDb());
        await store.init();
        final tx = await store.addManualTransaction(
          amount: 10,
          date: DateTime(2026, 8, 12),
          category: SpendCategory.food,
          message: blank,
          isCredit: false,
          now: DateTime(2026, 8, 27),
        );
        expect(tx.merchant, defaultManualMessage(SpendCategory.food));
      });
    }

    test('user-edited message preserved (not overwritten by default)', () async {
      final store = freshStore(freshDb());
      await store.init();
      final tx = await store.addManualTransaction(
        amount: 20,
        date: DateTime(2026, 8, 12),
        category: SpendCategory.food,
        message: 'Cutting chai at corner',
        isCredit: false,
        now: DateTime(2026, 8, 27),
      );
      expect(tx.merchant, 'Cutting chai at corner');
      expect(tx.merchant, isNot(defaultManualMessage(SpendCategory.food)));
    });

    test('trims surrounding whitespace on message', () async {
      final store = freshStore(freshDb());
      await store.init();
      final tx = await store.addManualTransaction(
        amount: 20,
        date: DateTime(2026, 8, 12),
        category: SpendCategory.travel,
        message: '  Auto rickshaw  ',
        isCredit: false,
        now: DateTime(2026, 8, 27),
      );
      expect(tx.merchant, 'Auto rickshaw');
    });
  });

  group('amount edge persistence', () {
    final amounts = <(String, double, double)>[
      ('paise', 0.01, 0.01),
      ('rounds 10.125', 10.125, 10.13),
      ('many decimals', 12.3456, 12.35),
      ('lakh', 125000, 125000),
      ('crore-ish', 15000000, 15000000),
    ];

    for (final (label, raw, expected) in amounts) {
      test('persists $label as $expected', () async {
        final store = freshStore(freshDb());
        await store.init();
        final tx = await store.addManualTransaction(
          amount: raw,
          date: DateTime(2026, 8, 12),
          category: SpendCategory.other,
          message: 'Cash spend',
          isCredit: false,
          now: DateTime(2026, 8, 27),
        );
        expect(tx.amount, expected);
      });
    }

    test('store rejects zero', () async {
      final store = freshStore(freshDb());
      await store.init();
      expect(
        () => store.addManualTransaction(
          amount: 0,
          date: DateTime(2026, 8, 12),
          category: SpendCategory.food,
          message: 'x',
          isCredit: false,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('store rejects negative', () async {
      final store = freshStore(freshDb());
      await store.init();
      expect(
        () => store.addManualTransaction(
          amount: -50,
          date: DateTime(2026, 8, 12),
          category: SpendCategory.food,
          message: 'x',
          isCredit: false,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('date edges via store', () {
    test('future date clamped to today clock', () async {
      final now = DateTime(2026, 8, 27, 11, 22);
      final store = freshStore(freshDb());
      await store.init();
      final tx = await store.addManualTransaction(
        amount: 10,
        date: DateTime(2026, 12, 25),
        category: SpendCategory.shopping,
        message: 'Future gift attempt',
        isCredit: false,
        now: now,
      );
      expect(tx.timestamp, now);
    });

    test('month boundary Jul 31 noon', () async {
      final now = DateTime(2026, 8, 27);
      final store = freshStore(freshDb());
      await store.init();
      final tx = await store.addManualTransaction(
        amount: 100,
        date: DateTime(2026, 7, 31),
        category: SpendCategory.bills,
        message: 'July bill',
        isCredit: false,
        now: now,
      );
      expect(tx.timestamp, DateTime(2026, 7, 31, 12));
      expect(store.transactionsForDay(DateTime(2026, 7, 31)).length, 1);
      expect(store.transactionsForDay(DateTime(2026, 8, 1)), isEmpty);
    });

    test('leap day 2024 lands on Feb 29', () async {
      final store = freshStore(freshDb());
      await store.init();
      final tx = await store.addManualTransaction(
        amount: 50,
        date: DateTime(2024, 2, 29),
        category: SpendCategory.health,
        message: 'Leap day',
        isCredit: false,
        now: DateTime(2026, 8, 27),
      );
      expect(tx.timestamp.year, 2024);
      expect(tx.timestamp.month, 2);
      expect(tx.timestamp.day, 29);
    });

    test('yesterday vs today vs last week buckets', () async {
      final now = DateTime(2026, 8, 27, 16);
      final store = freshStore(freshDb());
      await store.init();

      await store.addManualTransaction(
        amount: 1,
        date: now,
        category: SpendCategory.food,
        message: 'Today',
        isCredit: false,
        now: now,
      );
      await store.addManualTransaction(
        amount: 2,
        date: DateTime(2026, 8, 26),
        category: SpendCategory.food,
        message: 'Yesterday',
        isCredit: false,
        now: now,
      );
      await store.addManualTransaction(
        amount: 3,
        date: DateTime(2026, 8, 20),
        category: SpendCategory.food,
        message: 'Last week',
        isCredit: false,
        now: now,
      );

      expect(store.transactionsForDay(now).single.merchant, 'Today');
      expect(
        store.transactionsForDay(DateTime(2026, 8, 26)).single.merchant,
        'Yesterday',
      );
      expect(
        store.transactionsForDay(DateTime(2026, 8, 20)).single.merchant,
        'Last week',
      );
    });
  });

  group('manual + SMS coexistence ordering', () {
    test('SMS morning, manual noon, SMS evening same day', () async {
      final day = DateTime(2026, 8, 15);
      final db = freshDb();
      await db.upsertAll([
        smsTxn(
          id: 'sms_am',
          amount: 10,
          timestamp: DateTime(2026, 8, 15, 8, 0),
          merchant: 'SMS Morning',
        ),
        smsTxn(
          id: 'sms_pm',
          amount: 30,
          timestamp: DateTime(2026, 8, 15, 20, 0),
          merchant: 'SMS Evening',
        ),
      ]);
      final store = freshStore(db);
      await store.init();

      await store.addManualTransaction(
        amount: 20,
        date: day,
        category: SpendCategory.food,
        message: 'Cash lunch',
        isCredit: false,
        now: DateTime(2026, 8, 27),
      );

      final ordered = store.transactionsForDay(day);
      expect(ordered.map((t) => t.merchant).toList(), [
        'SMS Morning',
        'Cash lunch',
        'SMS Evening',
      ]);
    });

    test('multiple manuals same backdated day share noon — stable by insert',
        () async {
      final day = DateTime(2026, 8, 10);
      final now = DateTime(2026, 8, 27);
      final store = freshStore(freshDb());
      await store.init();

      final a = await store.addManualTransaction(
        amount: 10,
        date: day,
        category: SpendCategory.food,
        message: 'First',
        isCredit: false,
        now: now,
      );
      final b = await store.addManualTransaction(
        amount: 20,
        date: day,
        category: SpendCategory.travel,
        message: 'Second',
        isCredit: false,
        now: now,
      );

      final dayList = store.transactionsForDay(day);
      expect(dayList.length, 2);
      // Same noon timestamp; both present.
      expect(dayList.map((t) => t.id).toSet(), {a.id, b.id});
      expect(a.timestamp, b.timestamp);
    });
  });

  group('KPIs — monthly + day + category', () {
    test('manual Out counts in monthlySpent for current month', () async {
      final now = DateTime.now();
      final store = freshStore(freshDb());
      await store.init();
      await store.addManualTransaction(
        amount: 250,
        date: now,
        category: SpendCategory.food,
        message: 'Chai KPI',
        isCredit: false,
        now: now,
      );
      expect(store.monthlySpent, closeTo(250, 0.001));
      expect(store.monthlyIncome, 0);
    });

    test('manual In counts in monthlyIncome', () async {
      final now = DateTime.now();
      final store = freshStore(freshDb());
      await store.init();
      await store.addManualTransaction(
        amount: 2100,
        date: now,
        category: SpendCategory.income,
        message: 'Wedding gift',
        isCredit: true,
        now: now,
      );
      expect(store.monthlyIncome, closeTo(2100, 0.001));
      expect(store.monthlySpent, 0);
    });

    test('day OUT/IN KPIs for manual stack', () async {
      final now = DateTime.now();
      final day = DateTime(now.year, now.month, now.day);
      final store = freshStore(freshDb());
      await store.init();
      await store.addManualTransaction(
        amount: 80,
        date: day,
        category: SpendCategory.travel,
        message: 'Auto',
        isCredit: false,
        now: now,
      );
      await store.addManualTransaction(
        amount: 500,
        date: day,
        category: SpendCategory.income,
        message: 'Cash in',
        isCredit: true,
        now: now.add(const Duration(minutes: 1)),
      );
      expect(store.daySpend(day), 80);
      expect(store.dayIncome(day), 500);
      expect(store.dayNet(day), 420);
    });

    test('categorySpending includes manual food', () async {
      final now = DateTime.now();
      final store = freshStore(freshDb());
      await store.init();
      await store.addManualTransaction(
        amount: 120,
        date: now,
        category: SpendCategory.food,
        message: 'Dosa',
        isCredit: false,
        now: now,
      );
      expect(store.categorySpending[SpendCategory.food], closeTo(120, 0.001));
    });

    test('budgets spent reflects manual category after setBudgetLimit', () async {
      final now = DateTime.now();
      final store = freshStore(freshDb());
      await store.init();
      await store.setCategoryBudgetLimit(SpendCategory.food, 1000);
      await store.addManualTransaction(
        amount: 300,
        date: now,
        category: SpendCategory.food,
        message: 'Street food',
        isCredit: false,
        now: now,
      );
      final foodBudget =
          store.budgets.where((b) => b.category == SpendCategory.food).single;
      expect(foodBudget.spent, closeTo(300, 0.001));
    });

    test('prior-month manual excluded from monthlySpent', () async {
      final now = DateTime.now();
      final prior = DateTime(now.year, now.month - 1, 15);
      final store = freshStore(freshDb());
      await store.init();
      await store.addManualTransaction(
        amount: 999,
        date: prior,
        category: SpendCategory.shopping,
        message: 'Old shopping',
        isCredit: false,
        now: now,
      );
      expect(store.monthlySpent, 0);
    });
  });

  group('Transactions filters + search', () {
    late FinanceStore store;
    late models.Transaction cashOut;
    late models.Transaction cashIn;
    late models.Transaction smsCc;
    late models.Transaction smsLoan;

    setUp(() async {
      final db = freshDb();
      await db.upsertAll([
        smsTxn(
          id: 'sms_cc',
          amount: 400,
          timestamp: DateTime(2026, 8, 10, 12),
          merchant: 'Credit card bill payment',
          kind: AccountKind.creditCard,
        ),
        smsTxn(
          id: 'sms_loan',
          amount: 5000,
          timestamp: DateTime(2026, 8, 11, 12),
          merchant: 'Home loan EMI',
          category: SpendCategory.emi,
          kind: AccountKind.loan,
        ),
      ]);
      store = freshStore(db);
      await store.init();
      cashOut = await store.addManualTransaction(
        amount: 80,
        date: DateTime(2026, 8, 12),
        category: SpendCategory.travel,
        message: 'Auto rickshaw',
        isCredit: false,
        now: DateTime(2026, 8, 27),
      );
      cashIn = await store.addManualTransaction(
        amount: 2100,
        date: DateTime(2026, 8, 13),
        category: SpendCategory.income,
        message: 'Wedding gift cash',
        isCredit: true,
        now: DateTime(2026, 8, 27),
      );
      smsCc = store.transactions.firstWhere((t) => t.id == 'sms_cc');
      smsLoan = store.transactions.firstWhere((t) => t.id == 'sms_loan');
    });

    test('manual Out matches outgoing filter', () {
      expect(matchesOut(cashOut), isTrue);
      expect(matchesIn(cashOut), isFalse);
    });

    test('manual In matches incoming filter', () {
      expect(matchesIn(cashIn), isTrue);
      expect(matchesOut(cashIn), isFalse);
    });

    test('manual not in credit-card filter', () {
      expect(isCc(cashOut), isFalse);
      expect(isCc(cashIn), isFalse);
      expect(isCc(smsCc), isTrue);
    });

    test('manual food/travel not in loan filter; cash EMI is loan-like',
        () async {
      expect(isLoan(cashOut), isFalse);
      expect(isLoan(smsLoan), isTrue);

      final emi = await store.addManualTransaction(
        amount: 3500,
        date: DateTime(2026, 8, 14),
        category: SpendCategory.emi,
        message: 'Cash EMI',
        isCredit: false,
        now: DateTime(2026, 8, 27),
      );
      // Same heuristic as Transactions: EMI debit counts as loan filter.
      expect(isLoan(emi), isTrue);
    });

    test('search finds manual by merchant', () {
      final q = 'wedding';
      final hits = store.transactions.where((t) {
        return t.merchant.toLowerCase().contains(q) ||
            t.amount.toString().contains(q);
      }).toList();
      expect(hits.map((t) => t.id), contains(cashIn.id));
    });

    test('search finds manual by amount fragment', () {
      final hits = store.transactions
          .where((t) => t.amount.toString().contains('80'))
          .toList();
      expect(hits.any((t) => t.id == cashOut.id), isTrue);
    });

    test('search finds Hindi merchant', () async {
      final tx = await store.addManualTransaction(
        amount: 25,
        date: DateTime(2026, 8, 12),
        category: SpendCategory.food,
        message: 'चाय की दुकान',
        isCredit: false,
        now: DateTime(2026, 8, 27),
      );
      final hits = store.transactions
          .where((t) => t.merchant.contains('चाय'))
          .toList();
      expect(hits.single.id, tx.id);
    });
  });

  group('You / bankAccounts exclusion', () {
    test('Cash manuals never appear in bankAccounts', () async {
      final store = freshStore(freshDb());
      await store.init();
      for (final cat in SpendCategory.values) {
        await store.addManualTransaction(
          amount: 11,
          date: DateTime(2026, 8, 12),
          category: cat,
          message: defaultManualMessage(cat),
          isCredit: defaultManualIsCredit(cat),
          now: DateTime(2026, 8, 27),
        );
      }
      expect(store.transactions.length, SpendCategory.values.length);
      expect(store.bankAccounts(), isEmpty);
    });
  });

  group('mask merchant display', () {
    final samples = [
      'Cutting chai',
      'Auto rickshaw',
      'Wedding gift cash',
      'चाय',
      '🛕 Temple',
      'AB',
      'A',
    ];

    for (final merchant in samples) {
      test('mask "$merchant"', () {
        final masked = maskedMerchantLabel(merchant, true);
        final plain = maskedMerchantLabel(merchant, false);
        expect(plain, merchant);
        if (merchant.length <= 2) {
          expect(masked, merchant);
        } else {
          expect(masked, isNot(merchant));
          expect(masked.contains('•'), isTrue);
        }
      });
    }
  });

  group('deleteManualTransaction edges', () {
    test('cannot delete SMS via deleteManual', () async {
      final db = freshDb();
      await db.upsertAll([
        smsTxn(
          id: 'sms_keep',
          amount: 5,
          timestamp: DateTime(2026, 8, 10),
        ),
      ]);
      final store = freshStore(db);
      await store.init();
      expect(await store.deleteManualTransaction('sms_keep'), isFalse);
      expect(store.transactions.length, 1);
    });

    test('cannot delete missing id', () async {
      final store = freshStore(freshDb());
      await store.init();
      expect(await store.deleteManualTransaction('manual_missing'), isFalse);
    });

    test('cannot delete paste via deleteManual', () async {
      final db = freshDb();
      await db.upsertAll([
        models.Transaction(
          id: 'paste_1',
          smsId: null,
          merchant: 'Pasted',
          bank: 'Cash',
          maskedAccount: '',
          category: SpendCategory.other,
          amount: 5,
          isCredit: false,
          timestamp: DateTime(2026, 8, 10, 12),
          source: kPasteSource,
        ),
      ]);
      final store = freshStore(db);
      await store.init();
      expect(await store.deleteManualTransaction('paste_1'), isFalse);
      expect(store.transactions.length, 1);
    });

    test('deletes only the targeted manual among peers', () async {
      final store = freshStore(freshDb());
      await store.init();
      final a = await store.addManualTransaction(
        amount: 10,
        date: DateTime(2026, 8, 12),
        category: SpendCategory.food,
        message: 'A',
        isCredit: false,
        now: DateTime(2026, 8, 27),
      );
      final b = await store.addManualTransaction(
        amount: 20,
        date: DateTime(2026, 8, 12),
        category: SpendCategory.food,
        message: 'B',
        isCredit: false,
        now: DateTime(2026, 8, 27),
      );
      expect(await store.deleteManualTransaction(a.id), isTrue);
      expect(store.transactions.single.id, b.id);
    });
  });

  group('rescan preserve / clear wipe / reload survival', () {
    test('clearSmsDerivedData keeps manuals', () async {
      final db = freshDb();
      final store = freshStore(db);
      await store.init();
      final manual = await store.addManualTransaction(
        amount: 77,
        date: DateTime(2026, 8, 12),
        category: SpendCategory.health,
        message: 'Medicine',
        isCredit: false,
        now: DateTime(2026, 8, 27),
      );
      await db.upsertAll([
        smsTxn(id: 'sms_gone', amount: 3, timestamp: DateTime(2026, 8, 5)),
      ]);
      await db.clearSmsDerivedData();
      final left = await db.getAll();
      expect(left.single.id, manual.id);
    });

    test('isPreservedAcrossSmsRescan true for manual', () {
      expect(isPreservedAcrossSmsRescan(kManualSource), isTrue);
      expect(isPreservedAcrossSmsRescan('SMS'), isFalse);
    });

    test('clearAllData removes manuals', () async {
      final store = freshStore(freshDb());
      await store.init();
      await store.addManualTransaction(
        amount: 15,
        date: DateTime(2026, 8, 12),
        category: SpendCategory.other,
        message: 'Tip',
        isCredit: false,
        now: DateTime(2026, 8, 27),
      );
      await store.clearAllData();
      expect(store.transactions, isEmpty);
    });

    test('mint during reload survival — re-getAll still has row', () async {
      final db = freshDb();
      final store = freshStore(db);
      await store.init();
      final tx = await store.addManualTransaction(
        amount: 42,
        date: DateTime(2026, 8, 12),
        category: SpendCategory.food,
        message: 'Survive reload',
        isCredit: false,
        now: DateTime(2026, 8, 27),
      );
      // Simulate sync final getAll()
      store.seedTransactions(await db.getAll());
      expect(store.transactions.any((t) => t.id == tx.id), isTrue);
      expect(store.transactions.single.source, kManualSource);
    });

    test('double rapid adds create two distinct rows', () async {
      final store = freshStore(freshDb());
      await store.init();
      final now = DateTime(2026, 8, 27, 10);
      final futures = [
        store.addManualTransaction(
          amount: 20,
          date: now,
          category: SpendCategory.food,
          message: 'Rapid A',
          isCredit: false,
          now: now,
        ),
        store.addManualTransaction(
          amount: 20,
          date: now,
          category: SpendCategory.food,
          message: 'Rapid B',
          isCredit: false,
          now: now.add(const Duration(milliseconds: 1)),
        ),
      ];
      final results = await Future.wait(futures);
      expect(results[0].id, isNot(results[1].id));
      expect(store.transactions.length, 2);
    });
  });

  group('Coin Flip / Manual identity', () {
    test('manual has null smsId → OriginalSmsStatus.noSmsId path', () async {
      final store = freshStore(freshDb());
      await store.init();
      final tx = await store.addManualTransaction(
        amount: 20,
        date: DateTime(2026, 8, 12),
        category: SpendCategory.food,
        message: 'Chai',
        isCredit: false,
        now: DateTime(2026, 8, 27),
      );
      expect(tx.smsId, isNull);
      expect(tx.isManual, isTrue);
      // Lookup miss reason used by coin flip reverse face.
      expect(OriginalSmsStatus.noSmsId, isNotNull);
      final title = switch (OriginalSmsStatus.noSmsId) {
        OriginalSmsStatus.noSmsId => 'Minted by you',
        _ => 'other',
      };
      expect(title, 'Minted by you');
    });

    test('accountLine / flowLabel usable for search on manuals', () async {
      final store = freshStore(freshDb());
      await store.init();
      final out = await store.addManualTransaction(
        amount: 80,
        date: DateTime(2026, 8, 12),
        category: SpendCategory.travel,
        message: 'Auto',
        isCredit: false,
        now: DateTime(2026, 8, 27),
      );
      final inn = await store.addManualTransaction(
        amount: 100,
        date: DateTime(2026, 8, 12),
        category: SpendCategory.income,
        message: 'Gift',
        isCredit: true,
        now: DateTime(2026, 8, 27),
      );
      expect(out.flowLabel.toLowerCase(), contains('out'));
      expect(inn.flowLabel.toLowerCase(), contains('in'));
      expect(out.bank, 'Cash');
    });
  });

  group('income type forces In; category switch semantics', () {
    test('mint income with isCredit true', () async {
      final store = freshStore(freshDb());
      await store.init();
      final tx = await store.addManualTransaction(
        amount: 500,
        date: DateTime(2026, 8, 12),
        category: SpendCategory.income,
        message: 'Cash received',
        isCredit: true,
        now: DateTime(2026, 8, 27),
      );
      expect(tx.isCredit, isTrue);
      expect(tx.countsTowardIncome, isTrue);
      expect(tx.countsTowardSpend, isFalse);
    });

    test('user can mint food as In if they force credit (gift food cash)',
        () async {
      final store = freshStore(freshDb());
      await store.init();
      final tx = await store.addManualTransaction(
        amount: 200,
        date: DateTime(2026, 8, 12),
        category: SpendCategory.food,
        message: 'Cash for lunch from mom',
        isCredit: true,
        now: DateTime(2026, 8, 27),
      );
      expect(tx.category, SpendCategory.food);
      expect(tx.isCredit, isTrue);
    });

    test('user can mint income category as Out if forced (rare)', () async {
      final store = freshStore(freshDb());
      await store.init();
      final tx = await store.addManualTransaction(
        amount: 50,
        date: DateTime(2026, 8, 12),
        category: SpendCategory.income,
        message: 'Correction',
        isCredit: false,
        now: DateTime(2026, 8, 27),
      );
      expect(tx.isCredit, isFalse);
      expect(tx.countsTowardSpend, isTrue);
    });
  });
}
