// ignore_for_file: avoid_print

import 'dart:io';

import 'package:paisa_app/services/sms/account_discovery.dart';
import 'package:paisa_app/services/sms/parsed_sms_transaction.dart';
import 'package:paisa_app/services/sms/sms_scan_pipeline.dart';
import 'package:paisa_app/services/sms/transaction_enrichment.dart';

import 'sms_analysis_db.dart';

Future<void> main(List<String> args) async {
  final dbPath = args.isNotEmpty ? args.first : defaultSmsAnalysisDbPath();
  final db = await openSmsAnalysisDb(path: dbPath);

  final rows = await db.query('raw_sms', orderBy: 'id ASC');
  print('Reparsing ${rows.length} raw SMS in $dbPath …');

  await db.delete('parse_result');
  final batch = db.batch();
  var parsed = 0;
  var failed = 0;

  for (final row in rows) {
    final id = row['id'] as int;
    final address = row['address'] as String;
    final body = row['body'] as String;
    final dateMs = row['date_ms'] as int;

    final input = SmsMessageInput(
      id: (row['sms_id'] as String?) ?? '$id',
      sender: address,
      body: body,
      timestamp: DateTime.fromMillisecondsSinceEpoch(dateMs),
    );

    final discovered = AccountDiscovery.discover(
      sender: address,
      body: body,
    );
    final discoveries =
        discovered == null ? const <DiscoveredAccount>[] : [discovered];

    final result = SmsScanPipeline.process(input);
    String? bank;
    String? mask;
    double? amount;
    int? isCredit;
    String? accountKind;
    String? merchant;
    String? dropReason;

    if (result.isParsed) {
      parsed++;
      final txn = result.transaction!;
      final kind = TransactionEnrichment.resolveAccountKind(
        bank: txn.bank,
        mask: txn.maskedAccount,
        body: body,
        discoveries: discoveries,
      );
      bank = txn.bank;
      mask = txn.maskedAccount;
      amount = txn.amount;
      isCredit = txn.isCredit ? 1 : 0;
      accountKind = kind.name;
      merchant = txn.merchant;
    } else {
      failed++;
      dropReason = result.outcome.name;
      if (discovered != null) {
        bank = discovered.bank;
        mask = discovered.mask;
        accountKind = discovered.kind.name;
      }
    }

    batch.insert('parse_result', {
      'raw_id': id,
      'parsed': result.isParsed ? 1 : 0,
      'outcome': result.outcome.name,
      'bank': bank,
      'mask': mask,
      'amount': amount,
      'is_credit': isCredit,
      'account_kind': accountKind,
      'drop_reason': dropReason,
      'merchant': merchant,
    });
  }

  await batch.commit(noResult: true);
  await db.close();
  print('Done. parsed=$parsed  non_parsed=$failed');
}
