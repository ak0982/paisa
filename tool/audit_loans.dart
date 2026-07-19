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
  final messages = parseAdbSmsExport(File(path).readAsStringSync());
  final registry = AccountBankRegistry();
  final discoveries = <DiscoveredAccount>[];

  for (final m in messages) {
    registry.learn(m.sender, m.body);
    final d = AccountDiscovery.discover(sender: m.sender, body: m.body);
    if (d != null) discoveries.add(d);
  }

  var loanKind = 0;
  var emiCatSavings = 0;
  var nachDebits = 0;
  var nachLoanMissed = <String>[];

  for (final msg in messages) {
    final input = SmsMessageInput(
      id: '${msg.row}',
      sender: msg.sender,
      body: msg.body,
      timestamp: DateTime.fromMillisecondsSinceEpoch(msg.dateMs),
    );
    if (!SmsScanPipeline.process(input).isParsed) continue;
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
    final cat = MerchantCategorizer.categorize(
      merchant: parsed.merchant,
      smsBody: msg.body,
      isCredit: parsed.isCredit,
    );

    final lower = msg.body.toLowerCase();
    final isNachDebit = lower.contains('nach-10-') && lower.contains('debited');
    if (isNachDebit) {
      nachDebits++;
      if (kind != AccountKind.loan) {
        nachLoanMissed.add(
          'Row ${msg.row}: ${parsed.amount} ${parsed.bank} kind=$kind cat=$cat merchant=${parsed.merchant}',
        );
      }
    }

    if (kind == AccountKind.loan) loanKind++;
    if (cat == SpendCategory.emi && kind == AccountKind.savings) {
      emiCatSavings++;
      if (isNachDebit) {
        // already in nachLoanMissed
      }
    }
  }

  print('loan accountKind: $loanKind');
  print('emi category but savings kind: $emiCatSavings');
  print('NACH-10 debits: $nachDebits');
  print('NACH debits missed as loan: ${nachLoanMissed.length}');
  for (final line in nachLoanMissed.take(5)) {
    print('  $line');
  }
}
