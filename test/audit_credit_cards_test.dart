// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/services/sms/account_bank_registry.dart';
import 'package:paisa_app/services/sms/account_discovery.dart';
import 'package:paisa_app/services/sms/parsed_sms_transaction.dart';
import 'package:paisa_app/services/sms/sms_parser.dart';
import 'package:paisa_app/services/sms/sms_scan_pipeline.dart';
import 'package:paisa_app/services/sms/transaction_enrichment.dart';

import '../tool/analyze_sms_export.dart' show parseAdbSmsExport;

void main() {
  test('audit credit card classification on real SMS', () {
    final path = '${Platform.environment['HOME']}/Downloads/my_sms.txt';
    final messages = parseAdbSmsExport(File(path).readAsStringSync());
    final registry = AccountBankRegistry();
    final discoveries = <DiscoveredAccount>[];

    for (final m in messages) {
      registry.learn(m.sender, m.body);
      final d = AccountDiscovery.discover(sender: m.sender, body: m.body);
      if (d != null) discoveries.add(d);
    }

    var ccKind = 0;
    var ccBodyButSavings = 0;
    var ccMissedSamples = <String>[];
    var savingsButCcBody = <String>[];

    for (final msg in messages) {
      final lower = msg.body.toLowerCase();
      final looksLikeCcTxn = _looksLikeCcTransaction(lower);

      final input = SmsMessageInput(
        id: '${msg.row}',
        sender: msg.sender,
        body: msg.body,
        timestamp: DateTime.fromMillisecondsSinceEpoch(msg.dateMs),
      );
      if (!SmsScanPipeline.process(input).isParsed) {
        if (looksLikeCcTxn) {
          ccMissedSamples.add('UNPARSED Row ${msg.row}: ${_short(msg.body, 90)}');
        }
        continue;
      }
      final parsed = SmsParser.parseTransaction(input, registry: registry);
      if (parsed == null) continue;

      final mask = TransactionEnrichment.resolveMaskedAccount(
        parsedMask: parsed.maskedAccount,
        sender: msg.sender,
        body: msg.body,
      );
      final kind = TransactionEnrichment.resolveAccountKind(
        bank: parsed.bank,
        mask: mask,
        body: msg.body,
        discoveries: discoveries,
      );

      if (kind == AccountKind.creditCard) ccKind++;
      if (looksLikeCcTxn && kind != AccountKind.creditCard) {
        ccBodyButSavings++;
        if (ccMissedSamples.length < 15) {
          ccMissedSamples.add(
            'Row ${msg.row}: ${parsed.amount} ${parsed.isCredit ? "CR" : "DR"} '
            'kind=$kind bank=${parsed.bank} mask=$mask | ${_short(msg.body, 80)}',
          );
        }
      }
      if (!looksLikeCcTxn &&
          kind == AccountKind.creditCard &&
          savingsButCcBody.length < 8) {
        savingsButCcBody.add('Row ${msg.row}: ${_short(msg.body, 80)}');
      }
    }

    print('credit card accountKind: $ccKind');
    print('CC-like SMS classified as non-CC: $ccBodyButSavings');
    print('non-CC classified as CC: ${savingsButCcBody.length}');
    for (final s in ccMissedSamples.take(12)) print('  missed: $s');
    for (final s in savingsButCcBody) print('  false CC: $s');

    expect(ccBodyButSavings, 0,
        reason: 'CC spends/payments should classify as creditCard');
    expect(savingsButCcBody.length, lessThan(10),
        reason: 'CCBP/reversal CC credits may classify as CC without CC-like body');
    expect(ccKind, greaterThan(50),
        reason: 'Should detect substantial CC activity');
  });
}

String _short(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max)}...';

bool _looksLikeCcTransaction(String lower) {
  if (lower.contains('otp') && lower.contains('credit card')) return false;
  if (lower.contains('statement for your') && lower.contains('credit card')) {
    return false;
  }
  if (lower.contains('pre-approved') || lower.contains('apply now')) {
    return false;
  }
  if (lower.contains('is due on') ||
      lower.contains('due on ') ||
      lower.contains('minimum due') ||
      lower.contains('min due')) {
    return false;
  }
  if (lower.contains('reminder:') && lower.contains('due')) return false;
  if (lower.contains('outstanding of') && lower.contains('due')) return false;
  if (lower.contains('cashback') && lower.contains('credited')) return false;
  if (lower.contains('congratulations!') || lower.contains('congrats!')) {
    return false;
  }
  if (lower.contains('done via credit card')) return false;
  if (lower.contains('via credit card has failed')) return false;
  if (lower.contains('break down your') && lower.contains('credit card')) {
    return false;
  }

  if (lower.contains('ccbp') || lower.contains('mbk ccbp')) return true;
  if (lower.contains('is spent on your bobcard')) return true;
  if (lower.contains('reversal') && lower.contains('credit card')) return true;

  return (lower.contains('credit card') ||
          lower.contains('yes bank card') ||
          lower.contains('bobcard') ||
          lower.contains('sbicard')) &&
      (lower.contains('spent') ||
          lower.contains('delicious purchase') ||
          lower.contains('debited for') ||
          (lower.contains('payment of') &&
              !lower.contains('is due') &&
              !lower.contains('due on')) ||
          lower.contains('paid') ||
          lower.contains('received on your') ||
          (lower.contains('credited to') && lower.contains('credit card')) ||
          (lower.contains('credited towards your') &&
              lower.contains('credit card')) ||
          (lower.contains('reversal') && lower.contains('credit card')) ||
          (lower.contains('received payment') && lower.contains('bbps')));
}
