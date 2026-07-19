// ignore_for_file: avoid_print

import 'dart:io';

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

  final combos = <String, ({int count, int credits, String sample})>{};

  for (final msg in messages) {
    final result = SmsScanPipeline.process(
      SmsMessageInput(
        id: '${msg.row}',
        sender: msg.sender,
        body: msg.body,
        timestamp: DateTime.fromMillisecondsSinceEpoch(msg.dateMs),
      ),
    );
    if (!result.isParsed) continue;

    final txn = SmsParser.parseTransaction(
      SmsMessageInput(
        id: '${msg.row}',
        sender: msg.sender,
        body: msg.body,
        timestamp: DateTime.fromMillisecondsSinceEpoch(msg.dateMs),
      ),
      registry: registry,
    );
    if (txn == null) continue;

    final key = '${txn.bank}|${txn.maskedAccount}';
    final existing = combos[key];
    combos[key] = (
      count: (existing?.count ?? 0) + 1,
      credits: (existing?.credits ?? 0) + (txn.isCredit ? 1 : 0),
      sample: existing?.sample ??
          (msg.body.length > 120
              ? '${msg.body.replaceAll(RegExp(r'\s+'), ' ').substring(0, 120)}…'
              : msg.body.replaceAll(RegExp(r'\s+'), ' ')),
    );
  }

  print('=== ALL PARSED BANK+ACCOUNT COMBOS ===');
  final sorted = combos.entries.toList()
    ..sort((a, b) => b.value.count.compareTo(a.value.count));

  for (final e in sorted) {
    print('${e.value.count.toString().padLeft(4)} txns (${e.value.credits} credits)  ${e.key}');
  }

  print('\n=== HDFC ONLY ===');
  for (final e in sorted) {
    if (!e.key.startsWith('HDFC|')) continue;
    print('     ${e.value.sample}…');
    print('');
  }

  print('\n=== PROFILE-STYLE ACCOUNTS (credits received only) ===');
  final receivedByMask = <String, ({String bank, double received})>{};
  for (final e in sorted) {
    final parts = e.key.split('|');
    if (parts.length != 2) continue;
    final bank = parts[0];
    final mask = parts[1];
    if (e.value.credits == 0) continue;
    if (!RegExp(r'••••\d{4}$').hasMatch(mask)) continue;
    final last4 = int.tryParse(mask.substring(4));
    if (last4 != null && last4 >= 2015 && last4 <= 2035) continue;

    final existing = receivedByMask[mask];
    receivedByMask[mask] = (
      bank: existing?.bank ?? bank,
      received: (existing?.received ?? 0) + 0, // count only for listing
    );
  }

  // Recompute received amounts from credits in combos
  receivedByMask.clear();
  for (final e in sorted) {
    final parts = e.key.split('|');
    if (parts.length != 2 || e.value.credits == 0) continue;
    final mask = parts[1];
    if (!RegExp(r'••••\d{4}$').hasMatch(mask)) continue;
    final last4 = int.tryParse(mask.substring(4));
    if (last4 != null && last4 >= 2015 && last4 <= 2035) continue;
    // approximate: listed in output only
    print('${parts[0]} $mask — ${e.value.credits} credit txns');
  }

  print('\n=== HDFC UNIQUE MASKS (all) ===');
  final hdfcMasks = <String, int>{};
  for (final e in sorted) {
    if (!e.key.startsWith('HDFC|')) continue;
    final mask = e.key.split('|').last;
    hdfcMasks[mask] = (hdfcMasks[mask] ?? 0) + e.value.count;
  }
  for (final e in hdfcMasks.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value))) {
    print('${e.value.toString().padLeft(4)}  ${e.key}');
  }
}
