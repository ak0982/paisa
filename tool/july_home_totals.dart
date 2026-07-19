// ignore_for_file: avoid_print

import 'dart:io';

import 'package:paisa_app/services/sms/parsed_sms_transaction.dart';
import 'package:paisa_app/services/sms/sms_scan_pipeline.dart';

List<(String sender, String body, int dateMs)> parseExport(String raw) {
  final out = <(String, String, int)>[];
  for (final block in raw.split(RegExp(r'(?=^Row: )', multiLine: true))) {
    final t = block.trim();
    if (!t.startsWith('Row: ')) continue;
    final h = RegExp(r'^Row: (\d+) address=([^,]+), body=').firstMatch(t);
    if (h == null) continue;
    final d = RegExp(r', date=(\d+)\s*$', multiLine: true).firstMatch(t);
    if (d == null) continue;
    out.add((
      h.group(2)!,
      t.substring(h.end, d.start).trim(),
      int.parse(d.group(1)!),
    ));
  }
  return out;
}

void main(List<String> args) {
  final path = args.isNotEmpty
      ? args.first
      : '${Platform.environment['HOME']}/Downloads/my_sms.txt';
  final msgs = parseExport(File(path).readAsStringSync());

  final byMonth = <String, int>{};
  final money = <String, ({double dr, double cr, int drN, int crN})>{};

  DateTime? newest;
  for (final m in msgs) {
    final ts = DateTime.fromMillisecondsSinceEpoch(m.$3);
    if (newest == null || ts.isAfter(newest)) newest = ts;
    final key = '${ts.year}-${ts.month.toString().padLeft(2, '0')}';
    byMonth[key] = (byMonth[key] ?? 0) + 1;

    final r = SmsScanPipeline.process(
      SmsMessageInput(
        id: 'x',
        sender: m.$1,
        body: m.$2,
        timestamp: ts,
      ),
    );
    if (!r.isParsed) continue;
    final p = r.transaction!;
    final prev = money[key] ?? (dr: 0.0, cr: 0.0, drN: 0, crN: 0);
    if (p.isCredit) {
      money[key] = (
        dr: prev.dr,
        cr: prev.cr + p.amount,
        drN: prev.drN,
        crN: prev.crN + 1,
      );
    } else {
      money[key] = (
        dr: prev.dr + p.amount,
        cr: prev.cr,
        drN: prev.drN + 1,
        crN: prev.crN,
      );
    }
  }

  print('SMS rows: ${msgs.length}');
  print('Newest SMS timestamp: $newest');
  print('\nLatest months:');
  final months = byMonth.keys.toList()..sort();
  for (final m in months.reversed.take(6)) {
    final bag = money[m];
    print(
      '  $m  sms=${byMonth[m]}  '
      'spent=₹${(bag?.dr ?? 0).toStringAsFixed(0)} (${bag?.drN ?? 0})  '
      'income=₹${(bag?.cr ?? 0).toStringAsFixed(0)} (${bag?.crN ?? 0})',
    );
  }

  // July 2026 explicit (Home current month if device clock is Jul 2026)
  const jul = '2026-07';
  final j = money[jul];
  print('\nJULY 2026 Home expected (count-everything):');
  if (j == null) {
    print('  spent  = ₹0.00  (0 debits)');
    print('  income = ₹0.00  (0 credits)');
    print('  Note: dump has ${byMonth[jul] ?? 0} July SMS, none are bank txn alerts.');
  } else {
    print('  spent  = ₹${j.dr.toStringAsFixed(2)}  (${j.drN} debits)');
    print('  income = ₹${j.cr.toStringAsFixed(2)}  (${j.crN} credits)');
  }

  const jun = '2026-06';
  final ju = money[jun];
  if (ju != null) {
    print('\nJUNE 2026 (last month with bank activity in dump):');
    print('  spent  = ₹${ju.dr.toStringAsFixed(2)}  (${ju.drN} debits)');
    print('  income = ₹${ju.cr.toStringAsFixed(2)}  (${ju.crN} credits)');
  }
}
