// ignore_for_file: avoid_print

import 'dart:io';

import 'package:paisa_app/services/sms/account_bank_registry.dart';
import 'package:paisa_app/services/sms/account_discovery.dart';
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

  const realBanks = {
    'HDFC', 'SBI', 'ICICI', 'Axis', 'Kotak', 'Yes Bank', 'IndusInd',
    'PNB', 'Canara', 'Bank of Baroda', 'IDFC',
  };

  bool isReal(String bank, String mask) {
    if (!realBanks.contains(bank)) return false;
    if (!RegExp(r'••••\d{4}$').hasMatch(mask)) return false;
    final last4 = int.tryParse(mask.substring(4));
    if (last4 != null && last4 >= 2015 && last4 <= 2035) return false;
    return true;
  }

  final discoveries = <DiscoveredAccount>[];
  final savingsFromTxn = <String, ({String bank, int n, double in_, double out})>{};

  for (final msg in messages) {
    final d = AccountDiscovery.discover(sender: msg.sender, body: msg.body);
    if (d != null) discoveries.add(d);

    final input = SmsMessageInput(
      id: '${msg.row}',
      sender: msg.sender,
      body: msg.body,
      timestamp: DateTime.fromMillisecondsSinceEpoch(msg.dateMs),
    );
    if (!SmsScanPipeline.process(input).isParsed) continue;
    final txn = SmsParser.parseTransaction(input, registry: registry);
    if (txn == null || !isReal(txn.bank, txn.maskedAccount)) continue;
    final k = '${txn.bank}|${txn.maskedAccount}';
    final e = savingsFromTxn[k];
    savingsFromTxn[k] = (
      bank: txn.bank,
      n: (e?.n ?? 0) + 1,
      in_: (e?.in_ ?? 0) + (txn.isCredit ? txn.amount : 0),
      out: (e?.out ?? 0) + (txn.isCredit ? 0 : txn.amount),
    );
  }

  final merged = mergeDiscoveries(discoveries);

  print('=== SAVINGS FROM TRANSACTIONS (${savingsFromTxn.length}) ===');
  final savingsSorted = savingsFromTxn.entries.toList()
    ..sort((a, b) => b.value.n.compareTo(a.value.n));
  for (final e in savingsSorted) {
    print('${e.value.n.toString().padLeft(4)}  ${e.key}  in=${e.value.in_.toStringAsFixed(0)} out=${e.value.out.toStringAsFixed(0)}');
  }

  print('\n=== CREDIT CARDS DISCOVERED ===');
  final cards = merged.values.where((d) => d.kind == AccountKind.creditCard).toList()
    ..sort((a, b) => b.smsHits.compareTo(a.smsHits));
  for (final c in cards) {
    if (c.smsHits < 3) continue;
    print('${c.smsHits.toString().padLeft(4)}  ${c.bank} ${c.mask}');
  }

  print('\n=== LOANS DISCOVERED ===');
  final loans = merged.values.where((d) => d.kind == AccountKind.loan).toList()
    ..sort((a, b) => b.smsHits.compareTo(a.smsHits));
  for (final l in loans) {
    print('${l.smsHits.toString().padLeft(4)}  ${l.bank} ${l.mask} ${l.accountLabel}');
  }

  print('\n=== SAVINGS DISCOVERED (not in txn?) ===');
  for (final d in merged.values.where((d) => d.kind == AccountKind.savings)) {
    if (d.smsHits < 2) continue;
    final k = '${d.bank}|${d.mask}';
    if (savingsFromTxn.containsKey(k)) continue;
    print('${d.smsHits.toString().padLeft(4)}  $k');
  }

  print('\n=== MISSED CREDIT CARD SMS (sample) ===');
  var missed = 0;
  for (final msg in messages) {
    final b = msg.body.toLowerCase();
    if (!b.contains('credit card') && !b.contains('card ending')) continue;
    if (AccountDiscovery.discover(sender: msg.sender, body: msg.body) != null) {
      continue;
    }
    if (b.contains('offer') || b.contains('apply now') || b.contains('eligible')) {
      continue;
    }
    if (++missed <= 15) {
      print(msg.body.replaceAll(RegExp(r'\s+'), ' ').substring(0, 120.clamp(0, msg.body.length)));
    }
  }
  print('total missed credit-card-like SMS: $missed');

  print('\n=== MISSED LOAN/EMI SMS (sample) ===');
  missed = 0;
  for (final msg in messages) {
    final b = msg.body.toLowerCase();
    if (!RegExp(r'\b(emi|loan a/c|personal loan|home loan)\b').hasMatch(b)) {
      continue;
    }
    if (AccountDiscovery.discover(sender: msg.sender, body: msg.body) != null) {
      continue;
    }
    if (b.contains('offer') || b.contains('apply') || b.contains('eligible')) {
      continue;
    }
    if (++missed <= 15) {
      print(msg.body.replaceAll(RegExp(r'\s+'), ' ').substring(0, 120.clamp(0, msg.body.length)));
    }
  }
  print('total missed loan-like SMS: $missed');
}

extension on int {
  int clamp(int min, int max) => this < min ? min : (this > max ? max : this);
}
