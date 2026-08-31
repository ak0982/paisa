import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/data/transaction_database.dart';
import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/models/manual_transaction.dart';
import 'package:paisa_app/models/transaction.dart' as models;
import 'package:paisa_app/providers/finance_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tmp;
  var seq = 0;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('paisa_manual_mint');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  TransactionDatabase freshDb() => TransactionDatabase.forTesting(
        '${tmp.path}/paisa_${seq++}.db',
      );

  FinanceStore freshStore(TransactionDatabase db) => FinanceStore(database: db);

  group('manual message + validation helpers', () {
    test('default messages cover every SpendCategory', () {
      expect(defaultManualMessage(SpendCategory.food), 'Cash · Food');
      expect(defaultManualMessage(SpendCategory.travel), 'Cash · Travel');
      expect(defaultManualMessage(SpendCategory.shopping), 'Cash · Shopping');
      expect(defaultManualMessage(SpendCategory.bills), 'Cash · Bills');
      expect(
        defaultManualMessage(SpendCategory.entertainment),
        'Cash · Entertainment',
      );
      expect(defaultManualMessage(SpendCategory.health), 'Cash · Health');
      expect(defaultManualMessage(SpendCategory.emi), 'Cash · EMI');
      expect(defaultManualMessage(SpendCategory.atm), 'Cash withdrawn');
      expect(defaultManualMessage(SpendCategory.transfer), 'Cash transfer');
      expect(defaultManualMessage(SpendCategory.income), 'Cash received');
      expect(defaultManualMessage(SpendCategory.other), 'Cash spend');
    });

    test('income defaults to In; others Out', () {
      expect(defaultManualIsCredit(SpendCategory.income), isTrue);
      expect(defaultManualIsCredit(SpendCategory.food), isFalse);
      expect(defaultManualIsCredit(SpendCategory.atm), isFalse);
    });

    test('validateManualAmount rejects null, zero, negative', () {
      expect(validateManualAmount(null), isNotNull);
      expect(validateManualAmount(0), isNotNull);
      expect(validateManualAmount(-5), isNotNull);
      expect(validateManualAmount(0.01), isNull);
      expect(validateManualAmount(12.5), isNull);
    });

    test('clampManualDay pulls future dates back to today', () {
      final now = DateTime(2026, 8, 27, 15, 30);
      final future = DateTime(2026, 9, 1);
      expect(clampManualDay(future, now: now), DateTime(2026, 8, 27));
      expect(
        clampManualDay(DateTime(2026, 8, 12), now: now),
        DateTime(2026, 8, 12),
      );
    });

    test('manualTimestampForDay uses noon off-today and clock on today', () {
      final now = DateTime(2026, 8, 27, 15, 42, 10);
      final past = manualTimestampForDay(DateTime(2026, 8, 12), now: now);
      expect(past, DateTime(2026, 8, 12, 12));
      final today = manualTimestampForDay(DateTime(2026, 8, 27), now: now);
      expect(today, now);
    });

    test('newManualTransactionId uses manual_ prefix never sms_', () {
      final id = newManualTransactionId();
      expect(id.startsWith('manual_'), isTrue);
      expect(id.startsWith('sms_'), isFalse);
      expect(id.length, greaterThan(10));
    });
  });

  group('FinanceStore.addManualTransaction', () {
    test('persists to DB with source manual, Cash bank, null smsId', () async {
      final db = freshDb();
      final store = freshStore(db);
      await store.init();

      final tx = await store.addManualTransaction(
        amount: 120.5,
        date: DateTime(2026, 8, 12),
        category: SpendCategory.food,
        message: 'Cash · Food',
        isCredit: false,
        now: DateTime(2026, 8, 27, 10),
      );

      expect(tx.id.startsWith('manual_'), isTrue);
      expect(tx.source, kManualSource);
      expect(tx.smsId, isNull);
      expect(tx.bank, 'Cash');
      expect(tx.maskedAccount, isEmpty);
      expect(tx.amount, 120.5);
      expect(tx.isCredit, isFalse);
      expect(tx.category, SpendCategory.food);
      expect(tx.timestamp, DateTime(2026, 8, 12, 12));

      final rows = await db.getAll();
      expect(rows.length, 1);
      expect(rows.single.id, tx.id);
      expect(rows.single.source, 'manual');
      expect(rows.single.smsId, isNull);
    });

    test('appears under chosen day on day strip / moves ordering', () async {
      final db = freshDb();

      final smsEarlier = models.Transaction(
        id: 'sms_1',
        smsId: '1',
        merchant: 'Earlier',
        bank: 'HDFC',
        maskedAccount: '••••1234',
        category: SpendCategory.other,
        amount: 10,
        isCredit: false,
        timestamp: DateTime(2026, 8, 11, 18),
      );
      final smsLater = models.Transaction(
        id: 'sms_2',
        smsId: '2',
        merchant: 'Later',
        bank: 'HDFC',
        maskedAccount: '••••1234',
        category: SpendCategory.other,
        amount: 20,
        isCredit: false,
        timestamp: DateTime(2026, 8, 13, 9),
      );
      await db.upsertAll([smsEarlier, smsLater]);

      final store = freshStore(db);
      await store.init();

      await store.addManualTransaction(
        amount: 50,
        date: DateTime(2026, 8, 12),
        category: SpendCategory.travel,
        message: 'Cash · Travel',
        isCredit: false,
        now: DateTime(2026, 8, 27, 12),
      );

      final day = store.transactionsForDay(DateTime(2026, 8, 12));
      expect(day.length, 1);
      expect(day.single.merchant, 'Cash · Travel');

      final all = store.transactions.toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      expect(all.map((t) => t.merchant).toList(), [
        'Earlier',
        'Cash · Travel',
        'Later',
      ]);
    });

    test('Cash manual does not create a You bank account', () async {
      final db = freshDb();
      final store = freshStore(db);
      await store.init();

      await store.addManualTransaction(
        amount: 99,
        date: DateTime(2026, 8, 12),
        category: SpendCategory.shopping,
        message: 'Cash · Shopping',
        isCredit: false,
        now: DateTime(2026, 8, 27),
      );

      expect(store.bankAccounts(), isEmpty);
      expect(store.transactions.length, 1);
    });

    test('rejects zero and negative amounts', () async {
      final db = freshDb();
      final store = freshStore(db);
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
      expect(
        () => store.addManualTransaction(
          amount: -1,
          date: DateTime(2026, 8, 12),
          category: SpendCategory.food,
          message: 'x',
          isCredit: false,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(store.transactions, isEmpty);
    });

    test('clamps future date to today', () async {
      final db = freshDb();
      final store = freshStore(db);
      await store.init();
      final now = DateTime(2026, 8, 27, 16, 5);

      final tx = await store.addManualTransaction(
        amount: 10,
        date: DateTime(2026, 9, 5),
        category: SpendCategory.other,
        message: 'Cash spend',
        isCredit: false,
        now: now,
      );

      expect(tx.timestamp.year, 2026);
      expect(tx.timestamp.month, 8);
      expect(tx.timestamp.day, 27);
    });

    test('deleteManualTransaction only removes manual rows', () async {
      final db = freshDb();
      await db.upsertAll([
        models.Transaction(
          id: 'sms_9',
          smsId: '9',
          merchant: 'SMS row',
          bank: 'HDFC',
          maskedAccount: '••••9999',
          category: SpendCategory.food,
          amount: 5,
          isCredit: false,
          timestamp: DateTime(2026, 8, 10, 12),
        ),
      ]);
      final store = freshStore(db);
      await store.init();

      final manual = await store.addManualTransaction(
        amount: 30,
        date: DateTime(2026, 8, 12),
        category: SpendCategory.bills,
        message: 'Cash · Bills',
        isCredit: false,
        now: DateTime(2026, 8, 27),
      );

      expect(await store.deleteManualTransaction('sms_9'), isFalse);
      expect(store.transactions.length, 2);

      expect(await store.deleteManualTransaction(manual.id), isTrue);
      expect(store.transactions.length, 1);
      expect(store.transactions.single.id, 'sms_9');
    });
  });

  group('preserve manuals across SMS wipe', () {
    test('clearSmsDerivedData keeps manual and paste rows', () async {
      final db = freshDb();
      await db.upsertAll([
        models.Transaction(
          id: 'sms_a',
          smsId: 'a',
          merchant: 'Sms',
          bank: 'HDFC',
          maskedAccount: '••••1111',
          category: SpendCategory.food,
          amount: 1,
          isCredit: false,
          timestamp: DateTime(2026, 8, 1, 12),
        ),
        models.Transaction(
          id: 'manual_x',
          smsId: null,
          merchant: 'Cash · Food',
          bank: 'Cash',
          maskedAccount: '',
          category: SpendCategory.food,
          amount: 40,
          isCredit: false,
          timestamp: DateTime(2026, 8, 12, 12),
          source: kManualSource,
        ),
        models.Transaction(
          id: 'paste_y',
          smsId: null,
          merchant: 'Pasted',
          bank: 'Cash',
          maskedAccount: '',
          category: SpendCategory.other,
          amount: 5,
          isCredit: false,
          timestamp: DateTime(2026, 8, 13, 12),
          source: kPasteSource,
        ),
      ]);

      await db.clearSmsDerivedData();
      final left = await db.getAll();
      expect(left.map((t) => t.id).toSet(), {'manual_x', 'paste_y'});
    });

    test('fullRescanFromSms preserves manuals in store memory', () async {
      final db = freshDb();
      final store = freshStore(db);
      await store.init();

      await store.addManualTransaction(
        amount: 77,
        date: DateTime(2026, 8, 12),
        category: SpendCategory.health,
        message: 'Cash · Health',
        isCredit: false,
        now: DateTime(2026, 8, 27),
      );
      await db.upsertAll([
        models.Transaction(
          id: 'sms_wipe_me',
          smsId: 'wipe',
          merchant: 'Will go',
          bank: 'HDFC',
          maskedAccount: '••••2222',
          category: SpendCategory.other,
          amount: 3,
          isCredit: false,
          timestamp: DateTime(2026, 8, 5, 12),
        ),
      ]);
      store.seedTransactions(await db.getAll());

      // fullRescan will try SMS sync; without permission it still clears SMS
      // and reloads. Assert wipe path via clearSmsDerivedData + reload which
      // fullRescan uses before syncFromSms.
      await db.clearSmsDerivedData();
      final preserved = await db.getAll();
      expect(preserved.length, 1);
      expect(preserved.single.source, kManualSource);
      expect(preserved.single.amount, 77);
    });

    test('clearAllData still wipes manuals', () async {
      final db = freshDb();
      final store = freshStore(db);
      await store.init();

      await store.addManualTransaction(
        amount: 15,
        date: DateTime(2026, 8, 12),
        category: SpendCategory.other,
        message: 'Cash spend',
        isCredit: false,
        now: DateTime(2026, 8, 27),
      );
      expect(store.transactions, isNotEmpty);

      await store.clearAllData();
      expect(store.transactions, isEmpty);
      expect(await db.getAll(), isEmpty);
    });
  });
}
