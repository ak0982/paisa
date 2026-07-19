// ignore_for_file: avoid_print

import 'dart:io';

import 'package:paisa_app/services/sms/account_discovery.dart';
import 'package:paisa_app/services/sms/account_bank_registry.dart';
import 'package:paisa_app/services/sms/parsed_sms_transaction.dart';
import 'package:paisa_app/services/sms/sms_parser.dart';
import 'package:paisa_app/services/sms/sms_scan_pipeline.dart';

import 'analyze_sms_export.dart' show parseAdbSmsExport;

void main(List<String> args) {
  final path = args.isNotEmpty
      ? args.first
      : '${Platform.environment['HOME']}/Downloads/my_sms.txt';
  final messages = parseAdbSmsExport(File(path).readAsStringSync());
  final registry = AccountBankRegistry();
  for (final msg in messages) {
    registry.learn(msg.sender, msg.body);
  }

  final merged = mergeDiscoveries(
    messages
        .map((m) => AccountDiscovery.discover(sender: m.sender, body: m.body))
        .whereType<DiscoveredAccount>(),
  );

  for (final mask in ['6675', '3649', '9757', '7550', '5300', '0429', '0855', '1041']) {
    print('--- $mask discovery ---');
    for (final h in merged.values.where((d) => d.mask.contains(mask))) {
      print('  ${h.kind.name} ${h.bank} ${h.mask} hits=${h.smsHits}');
    }
  }

  // Mirror finance_store.bankAccounts()
  final creditCardKeys = <String>{
    for (final d in merged.values)
      if (d.kind == AccountKind.creditCard) '${d.bank}|${d.mask}',
  };
  final creditCardMasks = <String>{
    for (final d in merged.values)
      if (d.kind == AccountKind.creditCard) d.mask,
  };

  final accounts = <String, ({String name, String kind, int n, double in_, double out})>{};

  for (final msg in messages) {
    final input = SmsMessageInput(
      id: '${msg.row}',
      sender: msg.sender,
      body: msg.body,
      timestamp: DateTime.fromMillisecondsSinceEpoch(msg.dateMs),
    );
    if (!SmsScanPipeline.process(input).isParsed) continue;
    final txn = SmsParser.parseTransaction(input, registry: registry);
    if (txn == null || !RegExp(r'••••\d{4}$').hasMatch(txn.maskedAccount)) {
      continue;
    }

    final cardLookup = '${txn.bank}|${txn.maskedAccount}';
    final isCc = creditCardKeys.contains(cardLookup) ||
        creditCardMasks.contains(txn.maskedAccount);
    final kind = isCc ? 'creditCard' : 'savings';
    final key = '$kind|${txn.bank}|${txn.maskedAccount}';
    final e = accounts[key];
    accounts[key] = (
      name: isCc ? '${txn.bank} Credit Card' : '${txn.bank} Savings',
      kind: kind,
      n: (e?.n ?? 0) + 1,
      in_: (e?.in_ ?? 0) + (txn.isCredit ? txn.amount : 0),
      out: (e?.out ?? 0) + (txn.isCredit ? 0 : txn.amount),
    );
  }

  for (final d in merged.values) {
    if (d.kind == AccountKind.savings && d.smsHits >= 2) {
      final key = 'savings|${d.bank}|${d.mask}';
      if (!accounts.containsKey(key) && !creditCardMasks.contains(d.mask)) {
        accounts[key] = (
          name: '${d.bank} Savings',
          kind: 'savings',
          n: d.smsHits,
          in_: d.receivedTotal,
          out: d.spentTotal,
        );
      }
    }
    if (d.kind == AccountKind.creditCard && d.smsHits >= 2) {
      final key = 'creditCard|${d.bank}|${d.mask}';
      final e = accounts[key];
      accounts[key] = (
        name: '${d.bank} Credit Card',
        kind: 'creditCard',
        n: (e?.n ?? 0) + d.smsHits,
        in_: (e?.in_ ?? 0) + d.receivedTotal,
        out: (e?.out ?? 0) + d.spentTotal,
      );
    }
    if (d.kind == AccountKind.loan && d.smsHits >= 1) {
      final key = 'loan|${d.bank}|${d.mask}';
      accounts[key] = (
        name: '${d.bank} ${d.accountLabel ?? "Loan"}',
        kind: 'loan',
        n: d.smsHits,
        in_: d.receivedTotal,
        out: d.spentTotal,
      );
    }
  }

  print('\n=== PROFILE ACCOUNTS (${accounts.length}) ===');
  final sorted = accounts.entries.toList()
    ..sort((a, b) => b.value.n.compareTo(a.value.n));
  for (final e in sorted) {
    print('${e.value.kind.padRight(11)} ${e.key} n=${e.value.n} in=${e.value.in_.toStringAsFixed(0)} out=${e.value.out.toStringAsFixed(0)}');
  }

  const expected = [
    'savings|HDFC|••••5300',
    'savings|SBI|••••0429',
    'savings|SBI|••••6675',
    'savings|Kotak|••••3649',
    'creditCard|SBI|••••3452',
    'creditCard|ICICI|••••2009',
    'creditCard|IDFC|••••7424',
    'creditCard|Axis|••••8341',
    'creditCard|Axis|••••8422',
    'creditCard|Axis|••••9867',
    'creditCard|HDFC|••••7550',
    'creditCard|Yes Bank|••••9757',
    'loan|ICICI|••••1041',
    'loan|HDFC|••••0855',
  ];

  print('\n=== MISSING EXPECTED ===');
  for (final key in expected) {
    if (!accounts.containsKey(key)) print('MISSING $key');
  }
}
