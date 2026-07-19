// ignore_for_file: avoid_print

import 'dart:io';

import 'package:paisa_app/services/sms/parsed_sms_transaction.dart';
import 'package:paisa_app/services/sms/account_discovery.dart';
import 'package:paisa_app/services/sms/account_bank_registry.dart';
import 'package:paisa_app/services/sms/sms_parser.dart';
import 'package:paisa_app/services/sms/sms_scan_pipeline.dart';

import 'analyze_sms_export.dart' show parseAdbSmsExport;

void main(List<String> args) {
  final path = args.isNotEmpty
      ? args.first
      : '${Platform.environment['HOME']}/Downloads/my_sms.txt';
  final profileName = args.length > 1 ? args[1] : 'Amar Kumar';

  final messages = parseAdbSmsExport(File(path).readAsStringSync());
  final registry = AccountBankRegistry();
  for (final msg in messages) {
    registry.learn(msg.sender, msg.body);
  }

  final discoveries = <DiscoveredAccount>[];
  final savingsStats = <String, ({String bank, int activity, double received, double spent})>{};

  for (final msg in messages) {
    final found = AccountDiscovery.discover(sender: msg.sender, body: msg.body);
    if (found != null) discoveries.add(found);

    final input = SmsMessageInput(
      id: '${msg.row}',
      sender: msg.sender,
      body: msg.body,
      timestamp: DateTime.fromMillisecondsSinceEpoch(msg.dateMs),
    );
    final result = SmsScanPipeline.process(input);
    if (!result.isParsed) continue;
    final txn = SmsParser.parseTransaction(input, registry: registry);
    if (txn == null) continue;
    if (!RegExp(r'••••\d{4}$').hasMatch(txn.maskedAccount)) continue;

    final mask = txn.maskedAccount;
    final existing = savingsStats[mask];
    savingsStats[mask] = (
      bank: txn.bank,
      activity: (existing?.activity ?? 0) + 1,
      received: (existing?.received ?? 0) + (txn.isCredit ? txn.amount : 0),
      spent: (existing?.spent ?? 0) + (txn.isCredit ? 0 : txn.amount),
    );
  }

  final merged = mergeDiscoveries(discoveries);
  print('merged credit cards: ${merged.values.where((d) => d.kind == AccountKind.creditCard).length}');
  print('3452=${merged["creditCard|SBI|••••3452"]?.smsHits}');
  print('=== DISCOVERED ACCOUNTS (profile: $profileName) ===\n');

  print('-- Savings (from transactions, min 2 txns, exclude LenDen/other owners) --');
  for (final e in savingsStats.entries) {
    if (e.value.activity < 2) continue;
    final owner = merged.values
        .where((d) => d.mask == e.key && d.kind == AccountKind.savings)
        .map((d) => d.ownerName)
        .whereType<String>()
        .firstOrNull;
    if (AccountDiscovery.ownerConflictsWithProfile(owner, profileName)) {
      print('SKIP ${e.value.bank} ${e.key} owner=$owner');
      continue;
    }
    print('${e.value.bank} ${e.key} activity=${e.value.activity} received=${e.value.received.toStringAsFixed(0)}');
  }

  print('\n-- Credit cards (from SMS discovery) --');
  final cards = merged.values.where((d) => d.kind == AccountKind.creditCard).toList()
    ..sort((a, b) => b.smsHits.compareTo(a.smsHits));
  for (final card in cards) {
    if (AccountDiscovery.ownerConflictsWithProfile(card.ownerName, profileName)) {
      continue;
    }
    print('${card.bank} ${card.mask} hits=${card.smsHits} owner=${card.ownerName ?? "?"}');
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}
