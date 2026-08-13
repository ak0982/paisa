import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:paisa_app/data/transaction_database.dart';
import 'package:paisa_app/services/sms/account_discovery.dart';

/// ISSUE-1: an incremental sync that returns few/no discoveries must NOT wipe
/// accounts discovered by an earlier full scan.
void main() {
  late Directory tmp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('paisa_db_test');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  var seq = 0;
  TransactionDatabase freshDb() => TransactionDatabase.forTesting(
        '${tmp.path}/paisa_${seq++}.db',
      );

  DiscoveredAccount account(
    String bank,
    String mask, {
    AccountKind kind = AccountKind.savings,
    int hits = 3,
    double spent = 0,
    double received = 0,
  }) =>
      DiscoveredAccount(
        bank: bank,
        mask: mask,
        kind: kind,
        smsHits: hits,
        spentTotal: spent,
        receivedTotal: received,
      );

  test('merge preserves accounts when an incremental scan finds none', () async {
    final db = freshDb();

    final full = [
      account('Federal', '••••7953', received: 1200),
      account('PNB', '••••4720', spent: 500),
      account('HDFC', '••••5300', received: 9000, spent: 2000),
    ];
    await db.mergeDiscoveredAccounts(full);

    expect((await db.getDiscoveredAccounts()).length, 3);

    // Incremental scan with zero new discoveries.
    await db.mergeDiscoveredAccounts(const []);

    final after = await db.getDiscoveredAccounts();
    expect(after.length, 3,
        reason: 'accounts from the full scan must survive an empty incremental');
  });

  test('merge does not re-add counters for a re-seen account (R2-6)', () async {
    final db = freshDb();

    await db.mergeDiscoveredAccounts([
      account('HDFC', '••••5300', hits: 2, spent: 100, received: 900),
    ]);
    await db.mergeDiscoveredAccounts([
      account('HDFC', '••••5300', hits: 1, spent: 50, received: 0),
    ]);

    final rows = await db.getDiscoveredAccounts();
    expect(rows.length, 1);
    expect(rows.single.smsHits, 2);
    expect(rows.single.spentTotal, 100);
    expect(rows.single.receivedTotal, 900);
  });

  test('a new incremental account is added alongside existing ones', () async {
    final db = freshDb();

    await db.mergeDiscoveredAccounts([account('Federal', '••••7953')]);
    await db.mergeDiscoveredAccounts([account('SBI', '••••0429')]);

    final rows = await db.getDiscoveredAccounts();
    expect(rows.length, 2);
    expect(rows.map((a) => a.mask).toSet(), {'••••7953', '••••0429'});
  });
}
