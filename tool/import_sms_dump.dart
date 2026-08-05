// ignore_for_file: avoid_print

import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'analyze_sms_export.dart' show parseAdbSmsExport;
import 'sms_analysis_db.dart';

Future<void> main(List<String> args) async {
  final dumpPath = args.isNotEmpty
      ? args.first
      : '${Platform.environment['HOME']}/Downloads/my_sms_live.txt';
  final dbPath = args.length > 1 ? args[1] : defaultSmsAnalysisDbPath();

  final file = File(dumpPath);
  if (!file.existsSync()) {
    stderr.writeln('Dump not found: $dumpPath');
    exit(1);
  }

  print('Reading $dumpPath …');
  final messages = parseAdbSmsExport(file.readAsStringSync());
  print('Parsed ${messages.length} SMS rows from dump');

  final db = await openSmsAnalysisDb(path: dbPath);
  await db.delete('parse_result');
  await db.delete('raw_sms');

  final now = DateTime.now().millisecondsSinceEpoch;
  var inserted = 0;

  final batch = db.batch();
  for (final msg in messages) {
    batch.insert(
      'raw_sms',
      {
        'sms_id': msg.smsId,
        'address': msg.sender,
        'body': msg.body,
        'date_ms': msg.dateMs,
        'imported_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
  final results = await batch.commit(noResult: false);
  for (final r in results) {
    if (r is int && r > 0) inserted++;
  }

  final countRows = await db.rawQuery('SELECT COUNT(*) AS c FROM raw_sms');
  final total = (countRows.first['c'] as int?) ?? 0;
  await db.close();

  print('DB: $dbPath');
  print('Inserted: $inserted  total_rows: $total');
}
