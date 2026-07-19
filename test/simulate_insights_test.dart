// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/models/transaction.dart';
import 'package:paisa_app/services/sms/account_bank_registry.dart';
import 'package:paisa_app/services/sms/merchant_categorizer.dart';
import 'package:paisa_app/services/sms/parsed_sms_transaction.dart';
import 'package:paisa_app/services/sms/sms_parser.dart';
import 'package:paisa_app/services/sms/sms_scan_pipeline.dart';

import '../tool/analyze_sms_export.dart' show parseAdbSmsExport;

void main() {
  test('simulate insights from real SMS export', () {
    final path = '${Platform.environment['HOME']}/Downloads/my_sms.txt';
    final messages = parseAdbSmsExport(File(path).readAsStringSync());
    final registry = AccountBankRegistry();
    for (final m in messages) registry.learn(m.sender, m.body);

    final txns = <Transaction>[];
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
      final cat = MerchantCategorizer.categorize(
        merchant: parsed.merchant,
        smsBody: msg.body,
        isCredit: parsed.isCredit,
      );
      txns.add(Transaction(
        id: 'sms_${msg.row}',
        merchant: parsed.merchant,
        bank: parsed.bank,
        maskedAccount: parsed.maskedAccount,
        category: cat,
        amount: parsed.amount,
        isCredit: parsed.isCredit,
        timestamp: parsed.timestamp,
      ));
    }

    print('total parsed txns: ${txns.length}');

    final now = DateTime(2026, 7, 9);
    final current = DateTime(now.year, now.month);
    DateTime activeMonth = current;
    if (txns.isNotEmpty) {
      final hasCurrent = txns.any(
        (t) => t.timestamp.year == current.year && t.timestamp.month == current.month,
      );
      if (!hasCurrent) {
        final latest = txns.map((t) => t.timestamp).reduce((a, b) => a.isAfter(b) ? a : b);
        activeMonth = DateTime(latest.year, latest.month);
      }
    }
    print('activeMonth (old logic): ${activeMonth.year}-${activeMonth.month}');

    // New logic: latest month with actual spending
    DateTime insightsMonth = current;
    if (txns.isNotEmpty) {
      double monthSpend(int y, int m) => txns
          .where((t) =>
              t.timestamp.year == y &&
              t.timestamp.month == m &&
              !t.isCredit)
          .fold(0.0, (s, t) => s + t.amount);

      if (monthSpend(current.year, current.month) > 0) {
        insightsMonth = current;
      } else {
        final latest = txns.map((t) => t.timestamp).reduce(
              (a, b) => a.isAfter(b) ? a : b,
            );
        var probe = DateTime(latest.year, latest.month);
        while (probe.year >= latest.year - 2) {
          if (monthSpend(probe.year, probe.month) > 0) {
            insightsMonth = probe;
            break;
          }
          probe = DateTime(probe.year, probe.month - 1);
        }
      }
    }
    activeMonth = insightsMonth;
    print('activeMonth (latest spending month): ${activeMonth.year}-${activeMonth.month}');

    final monthTxns = txns.where((t) =>
        t.timestamp.year == activeMonth.year &&
        t.timestamp.month == activeMonth.month);
    final dashboard = monthTxns;
    final debits = dashboard.where((t) => !t.isCredit);
    final spent = debits.fold(0.0, (s, t) => s + t.amount);

    final byCat = <SpendCategory, double>{};
    for (final t in debits) {
      byCat[t.category] = (byCat[t.category] ?? 0) + t.amount;
    }

    print('month txns: ${monthTxns.length}');
    print('debits (incl transfers): ${debits.length}');
    print('monthlySpent: ${spent.toStringAsFixed(0)}');
    print('categories:');
    final sorted = byCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in sorted) {
      print('  ${e.key.name}: ${e.value.toStringAsFixed(0)}');
    }

    final allDebits = txns.where((t) => !t.isCredit);
    final allCats = <SpendCategory, int>{};
    for (final t in allDebits) {
      allCats[t.category] = (allCats[t.category] ?? 0) + 1;
    }
    final cutoff = now.subtract(const Duration(days: 365));
    final window = txns.where((t) =>
        t.timestamp.isAfter(cutoff) && !t.isCredit);
    final windowSpend = window.fold(0.0, (s, t) => s + t.amount);
    print('last 12 months spent: ${windowSpend.toStringAsFixed(0)} debits=${window.length}');
    for (final e in allCats.entries) {
      print('  ${e.key.name}: ${e.value}');
    }
  });
}
