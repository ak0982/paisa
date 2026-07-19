// ignore_for_file: avoid_print
import 'dart:io';

import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/services/sms/account_bank_registry.dart';
import 'package:paisa_app/services/sms/account_discovery.dart';
import 'package:paisa_app/services/sms/merchant_categorizer.dart';
import 'package:paisa_app/services/sms/parsed_sms_transaction.dart';
import 'package:paisa_app/services/sms/sms_parser.dart';
import 'package:paisa_app/services/sms/sms_scan_pipeline.dart';
import 'package:paisa_app/services/sms/transaction_enrichment.dart';

import 'analyze_sms_export.dart' show parseAdbSmsExport;

void main() {
  final path = '${Platform.environment['HOME']}/Downloads/my_sms.txt';
  final rows = parseAdbSmsExport(File(path).readAsStringSync());
  final registry = AccountBankRegistry();
  final discoveries = <DiscoveredAccount>[];

  for (final r in rows) {
    registry.learn(r.sender, r.body);
    final d = AccountDiscovery.discover(sender: r.sender, body: r.body);
    if (d != null) discoveries.add(d);
  }

  var moneyIn = 0.0;
  var moneyOut = 0.0;
  var ccIn = 0.0;
  var ccOut = 0.0;
  var ccBill = 0.0;
  var loan = 0.0;
  final topCredits = <({double amt, String merchant, String body, int row})>[];
  final suspicious = <String>[];

  for (final r in rows) {
    final input = SmsMessageInput(
      id: '${r.row}',
      sender: r.sender,
      body: r.body,
      timestamp: DateTime.fromMillisecondsSinceEpoch(r.dateMs),
    );
    if (!SmsScanPipeline.process(input).isParsed) continue;
    final parsed = SmsParser.parseTransaction(input, registry: registry);
    if (parsed == null) continue;

    final mask = TransactionEnrichment.resolveMaskedAccount(
      parsedMask: parsed.maskedAccount,
      sender: r.sender,
      body: r.body,
    );
    final kind = TransactionEnrichment.resolveAccountKind(
      bank: parsed.bank,
      mask: mask,
      body: r.body,
      discoveries: discoveries,
    );
    final merchant = TransactionEnrichment.improveMerchant(
      merchant: parsed.merchant,
      body: r.body,
      isCredit: parsed.isCredit,
      accountKind: kind,
    );
    final lower = r.body.toLowerCase();

    final isCc = kind == AccountKind.creditCard ||
        merchant.toLowerCase().contains('ccbp') ||
        merchant.toLowerCase().contains('credit card');
    final isLoan = kind == AccountKind.loan ||
        (MerchantCategorizer.categorize(
              merchant: merchant,
              smsBody: r.body,
              isCredit: parsed.isCredit,
            ) ==
            SpendCategory.emi &&
            !parsed.isCredit);

    if (parsed.isCredit && parsed.amount > 10000) {
      topCredits.add((
        amt: parsed.amount,
        merchant: merchant,
        body: r.body,
        row: r.row,
      ));
    }

    if (!SmsParser.hasCompletedTransactionSignal(r.body) &&
        !lower.contains('debited') &&
        !lower.contains('credited to') &&
        !lower.contains('received on your')) {
      suspicious.add(
        'WEAK Row ${r.row} ${parsed.amount} CR=${parsed.isCredit}: '
        '${r.body.replaceAll(RegExp(r'\s+'), ' ').substring(0, 100)}',
      );
    }

    if (isCc) {
      if (parsed.isCredit) {
        ccIn += parsed.amount;
      } else if (merchant.toLowerCase().contains('bill')) {
        ccBill += parsed.amount;
      } else {
        ccOut += parsed.amount;
      }
    } else if (isLoan) {
      if (!parsed.isCredit) loan += parsed.amount;
    } else if (kind == AccountKind.savings) {
      if (parsed.isCredit) {
        moneyIn += parsed.amount;
      } else {
        moneyOut += parsed.amount;
      }
    }
  }

  topCredits.sort((a, b) => b.amt.compareTo(a.amt));
  print('SUMMARY TOTALS (all time):');
  print('  moneyIn: $moneyIn');
  print('  moneyOut: $moneyOut');
  print('  ccIn: $ccIn');
  print('  ccOut: $ccOut');
  print('  ccBill: $ccBill');
  print('  loan: $loan');
  print('\nTOP 20 CREDITS >10k:');
  for (final t in topCredits.take(20)) {
    print('  ${t.amt} row ${t.row} ${t.merchant}');
    print('    ${t.body.replaceAll(RegExp(r'\s+'), ' ').substring(0, 120)}');
  }
  print('\nWEAK SIGNAL PARSED (${suspicious.length}):');
  for (final s in suspicious.take(25)) print('  $s');
}
