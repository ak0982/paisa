import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../models/category_info.dart';
import '../models/transaction.dart' as models;
import '../services/sms/account_discovery.dart';
import 'sms_scan_state.dart';

class TransactionDatabase {
  TransactionDatabase._({String? dbPathOverride})
      : _dbPathOverride = dbPathOverride;
  static final TransactionDatabase instance = TransactionDatabase._();

  /// Creates an isolated instance backed by [dbPath] (e.g.
  /// `inMemoryDatabasePath`) for unit tests. Never used in production.
  @visibleForTesting
  factory TransactionDatabase.forTesting(String dbPath) =>
      TransactionDatabase._(dbPathOverride: dbPath);

  final String? _dbPathOverride;
  Database? _db;
  static const _dbVersion = 5;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final path =
        _dbPathOverride ?? join(await getDatabasesPath(), 'paisa_transactions.db');
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await _createV1Tables(db);
        await _createScanStateTable(db);
        await _createDiscoveredAccountsTable(db);
        await _createCategoryBudgetsTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createScanStateTable(db);
        }
        if (oldVersion < 3) {
          await _createDiscoveredAccountsTable(db);
        }
        if (oldVersion < 4) {
          await db.execute(
            "ALTER TABLE transactions ADD COLUMN account_kind TEXT NOT NULL DEFAULT 'savings'",
          );
        }
        if (oldVersion < 5) {
          await _createCategoryBudgetsTable(db);
        }
      },
    );
  }

  Future<void> _createV1Tables(Database db) async {
    await db.execute('''
      CREATE TABLE transactions (
        id TEXT PRIMARY KEY,
        sms_id TEXT UNIQUE,
        merchant TEXT NOT NULL,
        bank TEXT NOT NULL,
        masked_account TEXT NOT NULL,
        category TEXT NOT NULL,
        amount REAL NOT NULL,
        is_credit INTEGER NOT NULL,
        timestamp INTEGER NOT NULL,
        source TEXT NOT NULL,
        account_kind TEXT NOT NULL DEFAULT 'savings'
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_transactions_timestamp ON transactions(timestamp)',
    );
  }

  Future<void> _createScanStateTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS scan_state (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        full_scan_complete INTEGER NOT NULL DEFAULT 0,
        resume_offset INTEGER NOT NULL DEFAULT 0,
        last_scan_at INTEGER,
        scan_since_ms INTEGER
      )
    ''');
    await db.insert(
      'scan_state',
      {'id': 1, 'full_scan_complete': 0, 'resume_offset': 0},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> _createDiscoveredAccountsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS discovered_accounts (
        account_key TEXT PRIMARY KEY,
        bank TEXT NOT NULL,
        mask TEXT NOT NULL,
        kind TEXT NOT NULL,
        account_label TEXT,
        sms_hits INTEGER NOT NULL DEFAULT 1,
        spent_total REAL NOT NULL DEFAULT 0,
        received_total REAL NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<void> _createCategoryBudgetsTable(Database db) async {
    // User-set monthly spending limits per category (ISSUE-5). Absent rows fall
    // back to an auto-suggested limit computed by FinanceStore; a present row is
    // the user's explicit intent. `limit` is a SQL keyword, hence limit_amount.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS category_budgets (
        category TEXT PRIMARY KEY,
        limit_amount REAL NOT NULL
      )
    ''');
  }

  /// Returns the user-set monthly limit per category (category name -> amount).
  Future<Map<String, double>> getCategoryBudgets() async {
    final db = await database;
    final rows = await db.query('category_budgets');
    return {
      for (final row in rows)
        row['category'] as String: (row['limit_amount'] as num).toDouble(),
    };
  }

  Future<void> setCategoryBudget(String category, double limit) async {
    final db = await database;
    await db.insert(
      'category_budgets',
      {'category': category, 'limit_amount': limit},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteCategoryBudget(String category) async {
    final db = await database;
    await db.delete(
      'category_budgets',
      where: 'category = ?',
      whereArgs: [category],
    );
  }

  Future<void> clearCategoryBudgets() async {
    final db = await database;
    await db.delete('category_budgets');
  }

  Future<void> upsert(models.Transaction tx) async {
    final db = await database;
    await db.insert(
      'transactions',
      _toRow(tx),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> upsertAll(List<models.Transaction> items) async {
    final db = await database;
    final batch = db.batch();
    for (final tx in items) {
      batch.insert(
        'transactions',
        _toRow(tx),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<models.Transaction>> getAll() async {
    final db = await database;
    final rows = await db.query(
      'transactions',
      orderBy: 'timestamp DESC',
    );
    return rows.map(_fromRow).toList();
  }

  Future<Set<String>> getExistingSmsIds() async {
    final db = await database;
    final rows = await db.query('transactions', columns: ['sms_id']);
    return rows
        .map((r) => r['sms_id'] as String?)
        .whereType<String>()
        .toSet();
  }

  /// Destructive replace of the discovered-accounts table.
  ///
  /// Only safe to call when [items] is the authoritative FULL set (e.g. a full
  /// rescan). Incremental syncs must use [mergeDiscoveredAccounts] instead, or
  /// accounts discovered in earlier scans would be wiped when a routine
  /// incremental scan returns few/no discoveries. See ISSUE-1.
  Future<void> saveDiscoveredAccounts(List<DiscoveredAccount> items) async {
    final db = await database;
    await db.delete('discovered_accounts');
    if (items.isEmpty) return;
    final batch = db.batch();
    for (final item in items) {
      batch.insert(
        'discovered_accounts',
        {
          'account_key': item.key,
          'bank': item.bank,
          'mask': item.mask,
          'kind': item.kind.name,
          'account_label': item.accountLabel,
          'sms_hits': item.smsHits,
          'spent_total': item.spentTotal,
          'received_total': item.receivedTotal,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Non-destructive upsert used by every sync (full and incremental).
  ///
  /// Newly discovered accounts are inserted; accounts already present keep
  /// their counters (incremental 1h overlap would otherwise inflate sms_hits
  /// on every sync — R2-6). Crucially, accounts that are NOT in [items]
  /// (e.g. because an incremental scan only read the last hour of messages) are
  /// left untouched instead of being deleted. A full rescan clears the table
  /// first (via [clearAll]) so this merges into an empty table and rebuilds the
  /// authoritative set.
  Future<void> mergeDiscoveredAccounts(List<DiscoveredAccount> items) async {
    if (items.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final item in items) {
      batch.rawInsert(
        '''
        INSERT INTO discovered_accounts
          (account_key, bank, mask, kind, account_label,
           sms_hits, spent_total, received_total)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(account_key) DO UPDATE SET
          account_label =
            COALESCE(discovered_accounts.account_label, excluded.account_label)
        ''',
        [
          item.key,
          item.bank,
          item.mask,
          item.kind.name,
          item.accountLabel,
          item.smsHits,
          item.spentTotal,
          item.receivedTotal,
        ],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<DiscoveredAccount>> getDiscoveredAccounts() async {
    final db = await database;
    final rows = await db.query('discovered_accounts');
    return rows.map((row) {
      return DiscoveredAccount(
        bank: row['bank'] as String,
        mask: row['mask'] as String,
        kind: AccountKind.values.byName(row['kind'] as String),
        accountLabel: row['account_label'] as String?,
        smsHits: row['sms_hits'] as int? ?? 1,
        spentTotal: (row['spent_total'] as num?)?.toDouble() ?? 0,
        receivedTotal: (row['received_total'] as num?)?.toDouble() ?? 0,
      );
    }).toList();
  }

  Future<void> clearAll() async {
    final db = await database;
    await db.delete('transactions');
    await db.delete('discovered_accounts');
  }

  Future<void> resetScanState() async {
    final db = await database;
    await db.update(
      'scan_state',
      {
        'full_scan_complete': 0,
        'resume_offset': 0,
        'last_scan_at': null,
        'scan_since_ms': null,
      },
      where: 'id = 1',
    );
  }

  Future<SmsScanState> getScanState() async {
    final db = await database;
    final rows = await db.query('scan_state', where: 'id = 1', limit: 1);
    if (rows.isEmpty) return const SmsScanState();

    final row = rows.first;
    return SmsScanState(
      fullScanComplete: (row['full_scan_complete'] as int? ?? 0) == 1,
      resumeOffset: row['resume_offset'] as int? ?? 0,
      lastScanAt: row['last_scan_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(row['last_scan_at'] as int)
          : null,
      scanSinceMs: row['scan_since_ms'] as int?,
    );
  }

  Future<void> saveScanState(SmsScanState state) async {
    final db = await database;
    await db.update(
      'scan_state',
      {
        'full_scan_complete': state.fullScanComplete ? 1 : 0,
        'resume_offset': state.resumeOffset,
        'last_scan_at': state.lastScanAt?.millisecondsSinceEpoch,
        'scan_since_ms': state.scanSinceMs,
      },
      where: 'id = 1',
    );
  }

  Map<String, Object?> _toRow(models.Transaction tx) => {
        'id': tx.id,
        'sms_id': tx.smsId,
        'merchant': tx.merchant,
        'bank': tx.bank,
        'masked_account': tx.maskedAccount,
        'category': tx.category.name,
        'amount': tx.amount,
        'is_credit': tx.isCredit ? 1 : 0,
        'timestamp': tx.timestamp.millisecondsSinceEpoch,
        'source': tx.source,
        'account_kind': tx.accountKind.name,
      };

  models.Transaction _fromRow(Map<String, Object?> row) {
    final kindRaw = row['account_kind'] as String?;
    final accountKind = kindRaw == null
        ? AccountKind.savings
        : AccountKind.values.byName(kindRaw);

    return models.Transaction(
      id: row['id'] as String,
      smsId: row['sms_id'] as String?,
      merchant: row['merchant'] as String,
      bank: row['bank'] as String,
      maskedAccount: _cleanMask(row['masked_account'] as String),
      category: SpendCategory.values.byName(row['category'] as String),
      amount: (row['amount'] as num).toDouble(),
      isCredit: (row['is_credit'] as int) == 1,
      timestamp: DateTime.fromMillisecondsSinceEpoch(row['timestamp'] as int),
      source: row['source'] as String,
      accountKind: accountKind,
    );
  }

  String _cleanMask(String mask) {
    if (mask.contains('????')) return '';
    return mask;
  }
}
