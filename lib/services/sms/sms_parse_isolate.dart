import 'package:flutter/foundation.dart';

import 'parsed_sms_transaction.dart';
import 'sms_scan_pipeline.dart';

/// Parsed SMS hit returned from a background isolate.
class SmsParseHit {
  const SmsParseHit({
    required this.messageId,
    required this.sender,
    required this.body,
    required this.timestampMs,
    required this.amount,
    required this.isCredit,
    required this.merchant,
    required this.bank,
    required this.maskedAccount,
  });

  final String messageId;
  final String sender;
  final String body;
  final int timestampMs;
  final double amount;
  final bool isCredit;
  final String merchant;
  final String bank;
  final String maskedAccount;

  SmsMessageInput toMessage() => SmsMessageInput(
        id: messageId,
        sender: sender,
        body: body,
        timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMs),
      );

  ParsedSmsTransaction toTransaction() => ParsedSmsTransaction(
        amount: amount,
        isCredit: isCredit,
        merchant: merchant,
        bank: bank,
        maskedAccount: maskedAccount,
        timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMs),
      );
}

/// Runs stage-5 regex parsing off the UI thread.
Future<List<SmsParseHit>> parseCandidatesInIsolate(
  List<Map<String, dynamic>> candidates,
) {
  return compute(_parseCandidates, candidates);
}

List<SmsParseHit> _parseCandidates(List<Map<String, dynamic>> candidates) {
  final hits = <SmsParseHit>[];

  for (final raw in candidates) {
    final message = SmsMessageInput(
      id: raw['id'] as String,
      sender: raw['sender'] as String,
      body: raw['body'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(raw['timestampMs'] as int),
    );

    // Run the FULL staged Dart gate (OTP / promo / scam / transaction-signal)
    // before parsing. The native pre-filter is only a coarse thinner now, so
    // this isolate is the single source of truth for what becomes a
    // transaction on-device — matching what the test suite validates. See
    // ISSUE-2. Cheap: candidates are already pre-thinned natively.
    final result = SmsScanPipeline.process(message);
    if (!result.isParsed) continue;
    final parsed = result.transaction!;

    hits.add(
      SmsParseHit(
        messageId: message.id,
        sender: message.sender,
        body: message.body,
        timestampMs: message.timestamp.millisecondsSinceEpoch,
        amount: parsed.amount,
        isCredit: parsed.isCredit,
        merchant: parsed.merchant,
        bank: parsed.bank,
        maskedAccount: parsed.maskedAccount,
      ),
    );
  }

  return hits;
}
