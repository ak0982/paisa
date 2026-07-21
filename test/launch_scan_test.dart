import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:paisa_app/data/transaction_database.dart';
import 'package:paisa_app/providers/finance_store.dart';
import 'package:paisa_app/services/sms/account_discovery.dart';
import 'package:paisa_app/services/sms/sms_reader_service.dart';

/// ISSUE-7: the schema-bump rescan must no longer block the splash before
/// runApp. main() records the decision via [FinanceStore.configureLaunchScan]
/// and the app shell runs it after the first frame with [runLaunchScan]. These
/// tests verify that coordination:
///   * a pending rescan wipes-and-rebuilds and persists the version stamps
///     exactly once (write-after-await), and
///   * with no pending rescan (or once satisfied by onboarding) it does a
///     normal incremental sync and never re-stamps.
class _DenyPermissionReader extends SmsReaderService {
  @override
  Future<bool> hasSmsPermission() async => false;

  @override
  Future<bool> requestSmsPermission() async => false;

  @override
  Future<bool> isPermissionPermanentlyDenied() async => false;
}

void main() {
  late Directory tmp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('paisa_launch_test');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  var seq = 0;
  FinanceStore freshStore(TransactionDatabase db) => FinanceStore(
        smsReader: _DenyPermissionReader(),
        database: db,
      );

  TransactionDatabase freshDb() =>
      TransactionDatabase.forTesting('${tmp.path}/paisa_${seq++}.db');

  test('pending rescan wipes prior data and stamps versions once', () async {
    final db = freshDb();
    // Simulate accounts discovered by an earlier install/version.
    await db.mergeDiscoveredAccounts([
      DiscoveredAccount(
        bank: 'HDFC',
        mask: '••••5300',
        kind: AccountKind.savings,
        smsHits: 3,
      ),
    ]);
    expect((await db.getDiscoveredAccounts()).length, 1);

    final store = freshStore(db);
    await store.init();

    var persisted = 0;
    store.configureLaunchScan(
      needsRescan: true,
      persistVersions: () async => persisted++,
    );

    await store.runLaunchScan();

    // Full rescan cleared the stale discovered accounts (permission is denied,
    // so nothing is re-added on this host) and stamped versions after the scan.
    expect(await db.getDiscoveredAccounts(), isEmpty);
    expect(persisted, 1);

    // Running again is a normal incremental sync — no second wipe/stamp.
    await store.runLaunchScan();
    expect(persisted, 1);
  });

  test('no pending rescan does an incremental sync without stamping', () async {
    final db = freshDb();
    await db.mergeDiscoveredAccounts([
      DiscoveredAccount(
        bank: 'SBI',
        mask: '••••0429',
        kind: AccountKind.savings,
        smsHits: 2,
      ),
    ]);

    final store = freshStore(db);
    await store.init();

    var persisted = 0;
    store.configureLaunchScan(
      needsRescan: false,
      persistVersions: () async => persisted++,
    );

    await store.runLaunchScan();

    // Incremental sync must NOT wipe existing discoveries and must NOT stamp.
    expect((await db.getDiscoveredAccounts()).length, 1);
    expect(persisted, 0);
  });

  test('markLaunchScanSatisfied cancels a pending rescan (onboarding case)',
      () async {
    final db = freshDb();
    await db.mergeDiscoveredAccounts([
      DiscoveredAccount(
        bank: 'Axis',
        mask: '••••9867',
        kind: AccountKind.savings,
        smsHits: 4,
      ),
    ]);

    final store = freshStore(db);
    await store.init();

    var persisted = 0;
    store.configureLaunchScan(
      needsRescan: true,
      persistVersions: () async => persisted++,
    );
    // Onboarding already scanned the whole inbox and stamped versions itself.
    store.markLaunchScanSatisfied();

    await store.runLaunchScan();

    // No wipe, no re-stamp — the data onboarding built survives.
    expect((await db.getDiscoveredAccounts()).length, 1);
    expect(persisted, 0);
  });
}
