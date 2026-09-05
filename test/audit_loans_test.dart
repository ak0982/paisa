// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/services/sms/account_bank_registry.dart';
import 'package:paisa_app/services/sms/account_discovery.dart';
import 'package:paisa_app/services/sms/merchant_categorizer.dart';
import 'package:paisa_app/services/sms/parsed_sms_transaction.dart';
import 'package:paisa_app/services/sms/sms_parser.dart';
import 'package:paisa_app/services/sms/sms_scan_pipeline.dart';
import 'package:paisa_app/services/sms/transaction_enrichment.dart';

import '../tool/analyze_sms_export.dart' show parseAdbSmsExport;

void main() {
  test('audit loan classification on real SMS', () {
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
    var nachLoanMissed = 0;
    final emiSavingsSamples = <String>[];
    final unparsedLoanSms = <String>[];

    for (final msg in messages) {
      final lower = msg.body.toLowerCase();
      final looksLikeLoanTxn = (lower.contains('loan ac') ||
              lower.contains('loan a/c') ||
              lower.contains('nach-10-')) &&
          !lower.contains('not deposited') &&
          (lower.contains('debited') ||
              lower.contains('depositing') ||
              lower.contains('deposited'));

      final input = SmsMessageInput(
        id: '${msg.row}',
        sender: msg.sender,
        body: msg.body,
        timestamp: DateTime.fromMillisecondsSinceEpoch(msg.dateMs),
      );
      final pipeline = SmsScanPipeline.process(input);
      if (!pipeline.isParsed) {
        if (looksLikeLoanTxn) {
          unparsedLoanSms.add('Row ${msg.row}: ${msg.body.substring(0, 80)}...');
        }
        continue;
      }
      final parsed = SmsParser.parseTransaction(input, registry: registry);
      if (parsed == null) {
        if (looksLikeLoanTxn) {
          unparsedLoanSms.add('Row ${msg.row}: parse null');
        }
        continue;
      }

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

      final isNachDebit =
          lower.contains('nach-10-') && lower.contains('debited');
      if (isNachDebit) {
        nachDebits++;
        // R2-2 / schema 38: NACH that associates to a discovered loan must be
        // loan-kind, while display identity stays on the funding account.
        final associated = TransactionEnrichment.resolveAssociatedLoanProduct(
          body: msg.body,
          discoveries: discoveries,
        );
        if (associated != null && kind != AccountKind.loan) nachLoanMissed++;
      }

      if (kind == AccountKind.loan) loanKind++;
      if (cat == SpendCategory.emi && kind == AccountKind.savings) {
        emiCatSavings++;
        if (emiSavingsSamples.length < 15) {
          emiSavingsSamples.add(
            'Row ${msg.row}: ${parsed.amount} ${parsed.isCredit ? "CR" : "DR"} '
            '${parsed.merchant} | ${msg.body.substring(0, 70)}',
          );
        }
      }
    }

    print('loan accountKind: $loanKind');
    print('emi category but savings kind: $emiCatSavings');
    print('NACH-10 debits: $nachDebits');
    print('NACH debits missed as loan: $nachLoanMissed');
    print('unparsed loan-like SMS: ${unparsedLoanSms.length}');
    for (final s in unparsedLoanSms.take(10)) print('  $s');
    for (final s in emiSavingsSamples) print('  emi+savings: $s');

    expect(nachLoanMissed, 0,
        reason: 'NACH associated to a discovered loan must be loan-kind');
    expect(unparsedLoanSms.length, 0,
        reason: 'PNB and other loan payment SMS should parse');
    // R2-2: bare NACH/SIP is not loan-kind, so this is no longer 60+ NACH rows.
    // Floor covers PNB loan deposits + remapped EMI/NACH product payments.
    expect(loanKind, greaterThan(20),
        reason: 'Should detect PNB loan payments and remapped EMI/NACH');
  });
}
