// ignore_for_file: avoid_print

import 'dart:io';

import 'package:paisa_app/services/sms/account_bank_registry.dart';
import 'package:paisa_app/services/sms/parsed_sms_transaction.dart';
import 'package:paisa_app/services/sms/sms_parser.dart';

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

  print('Learned account → bank mappings:');
  for (final last4 in ['0429', '4321', '5300', '505']) {
    print('  ••••$last4 → ${registry.lookup(last4) ?? 'unknown'}');
  }

  var iciciLenDen = 0;
  var iciciLenDenSbi = 0;

  for (final msg in messages) {
    if (!msg.sender.toUpperCase().contains('ICICI')) continue;
    if (!msg.body.toLowerCase().contains('lendenclub borrower repayment')) {
      continue;
    }
    if (!msg.body.toLowerCase().contains('has been credited with amount')) {
      continue;
    }

    final parsed = SmsParser.parseTransaction(
      SmsMessageInput(
        id: '${msg.row}',
        sender: msg.sender,
        body: msg.body,
        timestamp: DateTime.fromMillisecondsSinceEpoch(msg.dateMs),
      ),
      registry: registry,
    );
    if (parsed == null) continue;

    iciciLenDen++;
    if (parsed.bank == 'SBI') iciciLenDenSbi++;
  }

  print('\nICICI LenDenClub repayment credits: $iciciLenDen');
  print('Resolved as SBI: $iciciLenDenSbi');
}
