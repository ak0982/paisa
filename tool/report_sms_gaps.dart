// ignore_for_file: avoid_print

import 'dart:io';

import 'sms_analysis_db.dart';

Future<void> main(List<String> args) async {
  final dbPath = args.isNotEmpty ? args.first : defaultSmsAnalysisDbPath();
  final outPath = args.length > 1
      ? args[1]
      : '${Platform.environment['HOME']}/Downloads/paisa_sms_gap_report.md';

  final db = await openSmsAnalysisDb(path: dbPath);
  final buf = StringBuffer();
  buf.writeln('# Paisa SMS gap report');
  buf.writeln();
  buf.writeln('Generated: ${DateTime.now().toIso8601String()}');
  buf.writeln('DB: `$dbPath`');
  buf.writeln();

  final total =
      ((await db.rawQuery('SELECT COUNT(*) AS c FROM raw_sms')).first['c']
              as int?) ??
          0;
  final parsedCount = ((await db.rawQuery(
            'SELECT COUNT(*) AS c FROM parse_result WHERE parsed = 1',
          ))
              .first['c'] as int?) ??
      0;

  buf.writeln('## Summary');
  buf.writeln();
  buf.writeln('| Metric | Count |');
  buf.writeln('| --- | ---: |');
  buf.writeln('| Raw SMS | $total |');
  buf.writeln('| Parsed transactions | $parsedCount |');
  buf.writeln(
    '| Parse rate | ${total == 0 ? 0 : (100 * parsedCount / total).toStringAsFixed(1)}% |',
  );
  buf.writeln();

  buf.writeln('## Outcomes');
  buf.writeln();
  buf.writeln('| Outcome | Count |');
  buf.writeln('| --- | ---: |');
  final outcomes = await db.rawQuery('''
SELECT outcome, COUNT(*) AS c FROM parse_result
GROUP BY outcome ORDER BY c DESC
''');
  for (final row in outcomes) {
    buf.writeln('| ${row['outcome']} | ${row['c']} |');
  }
  buf.writeln();

  buf.writeln('## By sender bank key (top 40)');
  buf.writeln();
  buf.writeln('| Bank key | Total | Parsed | ParseFailed | Parse% |');
  buf.writeln('| --- | ---: | ---: | ---: | ---: |');

  final allRaw = await db.rawQuery('''
SELECT r.address, p.parsed, p.outcome
FROM raw_sms r
JOIN parse_result p ON p.raw_id = r.id
''');

  final stats = <String, _BankStat>{};
  for (final row in allRaw) {
    final key = senderBankKey(row['address'] as String);
    final s = stats.putIfAbsent(key, _BankStat.new);
    s.total++;
    if ((row['parsed'] as int) == 1) s.parsed++;
    if (row['outcome'] == 'parseFailed') s.parseFailed++;
  }

  final ranked = stats.entries.toList()
    ..sort((a, b) => b.value.total.compareTo(a.value.total));
  for (final e in ranked.take(40)) {
    final s = e.value;
    final pct = s.total == 0 ? 0.0 : 100 * s.parsed / s.total;
    buf.writeln(
      '| ${e.key} | ${s.total} | ${s.parsed} | ${s.parseFailed} | ${pct.toStringAsFixed(1)}% |',
    );
  }
  buf.writeln();

  buf.writeln('## Ranked gaps (volume × parseFailed)');
  buf.writeln();
  buf.writeln(
    'Banks with the most `parseFailed` (bank-like but regex miss) first:',
  );
  buf.writeln();
  final gaps = ranked.where((e) => e.value.parseFailed > 0).toList()
    ..sort((a, b) => b.value.parseFailed.compareTo(a.value.parseFailed));
  buf.writeln('| Bank key | parseFailed | total |');
  buf.writeln('| --- | ---: | ---: |');
  for (final e in gaps.take(25)) {
    buf.writeln('| ${e.key} | ${e.value.parseFailed} | ${e.value.total} |');
  }
  buf.writeln();

  // HSBC section
  buf.writeln('## HSBC');
  buf.writeln();
  final hsbcRows = await db.rawQuery('''
SELECT r.address, r.body, p.outcome, p.parsed, p.bank, p.mask, p.amount
FROM raw_sms r
JOIN parse_result p ON p.raw_id = r.id
WHERE UPPER(r.address) LIKE '%HSBC%'
ORDER BY r.date_ms DESC
''');
  buf.writeln('HSBC-addressed SMS: **${hsbcRows.length}**');
  buf.writeln();
  if (hsbcRows.isEmpty) {
    buf.writeln('No HSBC sender SMS in this dump.');
  } else {
    var hsbcParsed = 0;
    var looksTxn = 0;
    buf.writeln('| Outcome | Redacted snippet |');
    buf.writeln('| --- | --- |');
    for (final row in hsbcRows) {
      if ((row['parsed'] as int) == 1) hsbcParsed++;
      final body = row['body'] as String;
      final lower = body.toLowerCase();
      if (lower.contains('debited') ||
          lower.contains('credited') ||
          lower.contains('spent') ||
          lower.contains('paid from') ||
          lower.contains('inr ') ||
          lower.contains('rs.') ||
          lower.contains('rs ')) {
        looksTxn++;
      }
      buf.writeln(
        '| ${row['outcome']} | ${redactSmsSnippet(body)} |',
      );
    }
    buf.writeln();
    buf.writeln('- Parsed as transactions: **$hsbcParsed**');
    buf.writeln('- Bodies with amount-like / txn wording: **$looksTxn**');
    if (hsbcParsed == 0 && looksTxn == 0) {
      buf.writeln();
      buf.writeln(
        '> No live HSBC savings/CC spend templates in inbox — OTP/promo only.',
      );
    }
  }
  buf.writeln();

  buf.writeln('## Top parseFailed samples (redacted, max 3 per sender)');
  buf.writeln();
  final failed = await db.rawQuery('''
SELECT r.address, r.body
FROM raw_sms r
JOIN parse_result p ON p.raw_id = r.id
WHERE p.outcome = 'parseFailed'
ORDER BY r.date_ms DESC
LIMIT 500
''');
  final perSender = <String, List<String>>{};
  for (final row in failed) {
    final addr = row['address'] as String;
    final list = perSender.putIfAbsent(addr, () => []);
    if (list.length >= 3) continue;
    list.add(redactSmsSnippet(row['body'] as String));
  }
  final senders = perSender.entries.toList()
    ..sort((a, b) => b.value.length.compareTo(a.value.length));
  for (final e in senders.take(30)) {
    buf.writeln('### `${e.key}`');
    for (final s in e.value) {
      buf.writeln('- $s');
    }
    buf.writeln();
  }

  await db.close();

  final out = File(outPath);
  out.writeAsStringSync(buf.toString());
  print('Wrote $outPath');
  // Also print summary to stdout (no bodies)
  print('total=$total parsed=$parsedCount hsbc=${hsbcRows.length}');
}

class _BankStat {
  int total = 0;
  int parsed = 0;
  int parseFailed = 0;
}
