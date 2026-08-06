// ignore_for_file: avoid_print

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Offline analysis DB path (personal SMS — never commit).
String defaultSmsAnalysisDbPath() {
  final home = Platform.environment['HOME'] ?? '.';
  return p.join(home, 'Downloads', 'paisa_sms_analysis.db');
}

Future<Database> openSmsAnalysisDb({String? path}) async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final dbPath = path ?? defaultSmsAnalysisDbPath();
  return databaseFactory.openDatabase(
    dbPath,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
CREATE TABLE raw_sms (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  sms_id TEXT,
  address TEXT NOT NULL,
  body TEXT NOT NULL,
  date_ms INTEGER NOT NULL,
  imported_at INTEGER NOT NULL,
  UNIQUE(address, body, date_ms)
)
''');
        await db.execute('''
CREATE TABLE parse_result (
  raw_id INTEGER PRIMARY KEY,
  parsed INTEGER NOT NULL,
  outcome TEXT NOT NULL,
  bank TEXT,
  mask TEXT,
  amount REAL,
  is_credit INTEGER,
  account_kind TEXT,
  drop_reason TEXT,
  merchant TEXT,
  FOREIGN KEY(raw_id) REFERENCES raw_sms(id) ON DELETE CASCADE
)
''');
        await db.execute(
          'CREATE INDEX idx_raw_sms_address ON raw_sms(address)',
        );
        await db.execute(
          'CREATE INDEX idx_parse_outcome ON parse_result(outcome)',
        );
      },
    ),
  );
}

/// Redact digits and truncate for safe reporting.
String redactSmsSnippet(String text, {int max = 140}) {
  var oneLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  oneLine = oneLine.replaceAll(RegExp(r'\d'), 'X');
  if (oneLine.length <= max) return oneLine;
  return '${oneLine.substring(0, max)}…';
}

/// Normalize DLT-style sender to a short bank key for grouping.
String senderBankKey(String address) {
  final upper = address.toUpperCase();
  // Strip common DLT prefixes: XX-BANK-S / VM-BANK / AX-BANKIN
  var core = upper;
  final dash = RegExp(r'^(?:[A-Z]{2}-)?([A-Z0-9]+)').firstMatch(upper);
  if (dash != null) core = dash.group(1)!;
  // Trim trailing -P/-S/-T channel suffix already partly handled
  core = core.split('-').first;
  if (core.contains('HSBC')) return 'HSBC';
  if (core.contains('SLCE') ||
      core.contains('SLCBNK') ||
      core.contains('SLICE')) {
    return 'Slice';
  }
  if (core.contains('HDFC')) return 'HDFC';
  if (core.contains('SBI') || core == 'SBIINB' || core == 'SBICRD') return 'SBI';
  if (core.contains('ICICI') || core.contains('ICICIB')) return 'ICICI';
  if (core.contains('AXIS') || core == 'AXISBK') return 'Axis';
  if (core.contains('KOTAK') || core.contains('KOTAKB')) return 'Kotak';
  if (core.contains('IDFCF') || core.contains('IDFC')) return 'IDFC';
  if (core.contains('PNB') || core == 'PUNJAB') return 'PNB';
  if (core.contains('YESB') || core.contains('YESBK')) return 'Yes';
  if (core.contains('INDUS')) return 'IndusInd';
  if (core.contains('BOB') || core.contains('BARB') || core.contains('BOBCARD')) {
    return 'BOB';
  }
  if (core.contains('CANARA') || core.contains('CNRB')) return 'Canara';
  if (core.contains('FEDERAL') || core.contains('FEDFIB') || core == 'MYJPTR') {
    return 'Federal';
  }
  if (core.contains('UNION') || core == 'UBIN') return 'Union';
  if (core.contains('BOI') || core == 'BKID') return 'BOI';
  if (core.contains('INDIAN') && core.contains('BANK')) return 'IndianBank';
  if (core.contains('PAYTM')) return 'Paytm';
  if (core.contains('PHONEPE') || core.contains('PHONPE')) return 'PhonePe';
  if (core.contains('GPAY') || core.contains('GOOGLE')) return 'GPay';
  if (core.contains('AMAZON')) return 'AmazonPay';
  return core.length > 12 ? core.substring(0, 12) : core;
}
