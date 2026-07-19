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
  test('audit transaction summary totals', () {
    final path = '${Platform.environment['HOME']}/Downloads/my_sms.txt';
    final rows = parseAdbSmsExport(File(path).readAsStringSync());
    final registry = AccountBankRegistry();
    final discoveries = <DiscoveredAccount>[];

    for (final r in rows) {
      registry.learn(r.sender, r.body);
      final d = AccountDiscovery.discover(sender: r.sender, body: r.body);
      if (d != null) discoveries.add(d);
    }

    var lendenIn = 0.0;
    var lendenCount = 0;
    var moneyIn = 0.0;
    var moneyOut = 0.0;
    var ccIn = 0.0;
    var ccOut = 0.0;
    var ccBill = 0.0;
    var loan = 0.0;
    final topCredits = <({double amt, String merchant, String body, int row})>[];
    final weakParsed = <String>[];

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

      if (r.sender.contains('LENDEN') && parsed.isCredit) {
        lendenIn += parsed.amount;
        lendenCount++;
      }

      if (parsed.isCredit && parsed.amount > 10000) {
        topCredits.add((
          amt: parsed.amount,
          merchant: merchant,
          body: r.body,
          row: r.row,
        ));
      }

      final category = MerchantCategorizer.categorize(
        merchant: merchant,
        smsBody: r.body,
        isCredit: parsed.isCredit,
      );

      if (!SmsParser.hasCompletedTransactionSignal(r.body)) {
        weakParsed.add(
          'Row ${r.row} ${parsed.amount} CR=${parsed.isCredit} $merchant | '
          '${r.body.replaceAll(RegExp(r'\s+'), ' ').substring(0, 100)}',
        );
      }

      if (category == SpendCategory.transfer && !isCc && !isLoan) {
        // Transfers count toward money in/out (user wants every txn tracked).
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
    print('SUMMARY TOTALS:');
    print('  moneyIn: $moneyIn moneyOut: $moneyOut');
    print('  lendenIn: $lendenIn count=$lendenCount');
    print('TOP CREDITS:');
    for (final t in topCredits.take(15)) {
      print('  ${t.amt} row ${t.row} ${t.merchant}');
    }
    print('WEAK PARSED (${weakParsed.length}):');
    for (final s in weakParsed.take(20)) print('  $s');

    final bySender = <String, int>{};
    for (final r in rows) {
      final input = SmsMessageInput(
        id: '${r.row}',
        sender: r.sender,
        body: r.body,
        timestamp: DateTime.fromMillisecondsSinceEpoch(r.dateMs),
      );
      if (!SmsScanPipeline.process(input).isParsed) continue;
      if (SmsParser.hasCompletedTransactionSignal(r.body)) continue;
      bySender[r.sender] = (bySender[r.sender] ?? 0) + 1;
    }
    print('WEAK BY SENDER:');
    final sorted = bySender.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    for (final e in sorted.take(15)) print('  ${e.key}: ${e.value}');

    print('SBICRD WEAK SAMPLES:');
    var n = 0;
    for (final r in rows) {
      if (!r.sender.contains('SBICRD')) continue;
      final input = SmsMessageInput(
        id: '${r.row}', sender: r.sender, body: r.body,
        timestamp: DateTime.fromMillisecondsSinceEpoch(r.dateMs),
      );
      if (!SmsScanPipeline.process(input).isParsed) continue;
      if (SmsParser.hasCompletedTransactionSignal(r.body)) continue;
      print('  Row ${r.row}: ${r.body.replaceAll(RegExp(r'\s+'), ' ').substring(0, 110)}');
      if (++n >= 8) break;
    }

    print('IDFCFB WEAK SAMPLES:');
    n = 0;
    for (final r in rows) {
      if (!r.sender.contains('IDFCFB')) continue;
      final input = SmsMessageInput(
        id: '${r.row}', sender: r.sender, body: r.body,
        timestamp: DateTime.fromMillisecondsSinceEpoch(r.dateMs),
      );
      if (!SmsScanPipeline.process(input).isParsed) continue;
      if (SmsParser.hasCompletedTransactionSignal(r.body)) continue;
      print('  Row ${r.row}: ${r.body.replaceAll(RegExp(r'\s+'), ' ').substring(0, 110)}');
      if (++n >= 5) break;
    }

    expect(lendenCount, greaterThan(0),
        reason: 'Platform wallet top-ups are tracked transactions');
    expect(weakParsed.length, lessThan(500));
  });
}
