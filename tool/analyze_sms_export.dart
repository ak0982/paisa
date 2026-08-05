// ignore_for_file: avoid_print

import 'dart:io';

import 'package:paisa_app/services/sms/parsed_sms_transaction.dart';
import 'package:paisa_app/services/sms/sms_scan_pipeline.dart';

/// One SMS row from an `adb shell content query …/sms/inbox` export.
class AdbExportedSms {
  AdbExportedSms({
    required this.row,
    required this.sender,
    required this.body,
    required this.dateMs,
    this.smsId,
  });

  final int row;
  final String sender;
  final String body;
  final int dateMs;
  /// Android Telephony `_id` when present in the export.
  final String? smsId;
}

/// Parses adb inbox exports.
///
/// Supports both:
/// - `Row: N address=…, body=…, date=…`
/// - `Row: N _id=…, address=…, body=…, date=…`
List<AdbExportedSms> parseAdbSmsExport(String raw) {
  final messages = <AdbExportedSms>[];
  final blocks = raw.split(RegExp(r'(?=^Row: )', multiLine: true));

  for (final block in blocks) {
    final trimmed = block.trim();
    if (!trimmed.startsWith('Row: ')) continue;

    final header = RegExp(
      r'^Row: (\d+)(?: _id=([^,]+),)? address=([^,]+), body=',
    ).firstMatch(trimmed);
    if (header == null) continue;

    final dateMatch =
        RegExp(r', date=(\d+)\s*$', multiLine: true).firstMatch(trimmed);
    if (dateMatch == null) continue;

    final body = trimmed.substring(header.end, dateMatch.start).trim();
    messages.add(
      AdbExportedSms(
        row: int.parse(header.group(1)!),
        smsId: header.group(2),
        sender: header.group(3)!,
        body: body,
        dateMs: int.parse(dateMatch.group(1)!),
      ),
    );
  }
  return messages;
}

String _snippet(String text, {int max = 120}) {
  final oneLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (oneLine.length <= max) return oneLine;
  return '${oneLine.substring(0, max)}…';
}

void main(List<String> args) {
  final path = args.isNotEmpty
      ? args.first
      : '${Platform.environment['HOME']}/Downloads/my_sms.txt';

  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('File not found: $path');
    exit(1);
  }

  print('Reading $path …');
  final raw = file.readAsStringSync();
  final messages = parseAdbSmsExport(raw);
  print('Parsed ${messages.length} SMS rows\n');

  final counts = <SmsPipelineOutcome, int>{};
  for (final o in SmsPipelineOutcome.values) {
    counts[o] = 0;
  }

  final parseFailedSamples = <String, List<String>>{};
  final parsedBySender = <String, int>{};
  var debits = 0;
  var credits = 0;

  for (final msg in messages) {
    final input = SmsMessageInput(
      id: msg.smsId ?? '${msg.row}',
      sender: msg.sender,
      body: msg.body,
      timestamp: DateTime.fromMillisecondsSinceEpoch(msg.dateMs),
    );

    final result = SmsScanPipeline.process(input);
    counts[result.outcome] = (counts[result.outcome] ?? 0) + 1;

    if (result.isParsed) {
      final txn = result.transaction!;
      parsedBySender[msg.sender] = (parsedBySender[msg.sender] ?? 0) + 1;
      if (txn.isCredit) {
        credits++;
      } else {
        debits++;
      }
    } else if (result.outcome == SmsPipelineOutcome.parseFailed) {
      final samples = parseFailedSamples.putIfAbsent(msg.sender, () => []);
      if (samples.length < 3) {
        samples.add(_snippet(msg.body));
      }
    }
  }

  print('=== PIPELINE SUMMARY ===');
  print('Total inbox messages     : ${messages.length}');
  print('Parsed transactions      : ${counts[SmsPipelineOutcome.parsed]}');
  print('  debits                 : $debits');
  print('  credits                : $credits');
  print('Parse failed (bank-like) : ${counts[SmsPipelineOutcome.parseFailed]}');
  print('Promo / marketing        : ${counts[SmsPipelineOutcome.promo]}');
  print('OTP only                 : ${counts[SmsPipelineOutcome.otpOnly]}');
  print('No transaction signal    : ${counts[SmsPipelineOutcome.noTransactionSignal]}');
  print('Not financial body       : ${counts[SmsPipelineOutcome.notFinancialBody]}');
  print('Not financial sender     : ${counts[SmsPipelineOutcome.notFinancialSender]}');

  final topParsed = parsedBySender.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  print('\n=== TOP PARSED SENDERS ===');
  for (final e in topParsed.take(15)) {
    print('${e.value.toString().padLeft(5)}  ${e.key}');
  }

  final topFailed = parseFailedSamples.entries.toList()
    ..sort((a, b) => b.value.length.compareTo(a.value.length));

  print('\n=== PARSE FAILED SAMPLES (need regex fixes) ===');
  var shown = 0;
  for (final e in topFailed) {
    if (shown >= 20) break;
    print('\n[$e.key]');
    for (final sample in e.value) {
      print('  • $sample');
    }
    shown++;
  }

  final reportPath = '${File(path).parent.path}/sms_analysis_report.txt';
  final report = StringBuffer()
    ..writeln('Paisa SMS bulk analysis')
    ..writeln('Source: $path')
    ..writeln('Messages: ${messages.length}')
    ..writeln('Parsed: ${counts[SmsPipelineOutcome.parsed]}')
    ..writeln('Parse failed: ${counts[SmsPipelineOutcome.parseFailed]}')
    ..writeln()
    ..writeln('Parse failed samples:');
  for (final e in topFailed.take(50)) {
    report.writeln('\n[${e.key}]');
    for (final sample in e.value) {
      report.writeln('  $sample');
    }
  }
  File(reportPath).writeAsStringSync(report.toString());
  print('\nFull report saved to: $reportPath');
}
