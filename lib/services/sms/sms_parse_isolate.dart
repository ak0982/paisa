import 'package:flutter/foundation.dart';

import 'account_bank_registry.dart';
import 'account_discovery.dart';
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

/// ISSUE-10: discovery + registry learning off the UI isolate.
///
/// [payload] keys:
///   - `allRows`: SMS rows for AccountDiscovery (one batch; do not send the
///     whole inbox — R2-5)
///   - `candidates`: bank-like candidates (for AccountBankRegistry.learn)
///   - `seedVotes` (optional): prior votes from stored transactions (ISSUE-12)
///   - `priorDiscoveries` (optional): discoveries from earlier batches so
///     registry seeding still runs before learn when discovery is chunked
Future<Pass1IsolateResult> discoverAndLearnInIsolate(
  Map<String, dynamic> payload,
) {
  return compute(_discoverAndLearn, payload);
}

class Pass1IsolateResult {
  const Pass1IsolateResult({
    required this.discoveries,
    required this.votes,
  });

  final List<DiscoveredAccount> discoveries;
  final Map<String, Map<String, int>> votes;
}

Pass1IsolateResult _discoverAndLearn(Map<String, dynamic> payload) {
  final allRows = (payload['allRows'] as List).cast<Map>();
  final candidates = (payload['candidates'] as List).cast<Map>();
  final seedRaw = payload['seedVotes'];
  final priorRaw = payload['priorDiscoveries'];

  final registry = AccountBankRegistry();
  if (seedRaw is Map) {
    final seed = <String, Map<String, int>>{};
    for (final entry in seedRaw.entries) {
      final inner = entry.value;
      if (inner is! Map) continue;
      seed[entry.key.toString()] = {
        for (final v in inner.entries)
          v.key.toString(): (v.value as num).toInt(),
      };
    }
    registry.seedVotes(seed);
  }

  final discoveries = <DiscoveredAccount>[];
  for (final raw in allRows) {
    final found = AccountDiscovery.discover(
      sender: raw['sender'] as String? ?? '',
      body: raw['body'] as String? ?? '',
    );
    if (found != null) discoveries.add(found);
  }

  final priorSeeds = <({String bank, String mask, int smsHits})>[];
  if (priorRaw is List) {
    for (final raw in priorRaw) {
      if (raw is! Map) continue;
      priorSeeds.add(
        (
          bank: raw['bank'] as String? ?? '',
          mask: raw['mask'] as String? ?? '',
          smsHits: (raw['smsHits'] as num?)?.toInt() ?? 1,
        ),
      );
    }
  }

  // Seed ownership from discoveries before learning from candidates so
  // beneficiary last-4s (e.g. Slice) beat ICICI relay senders.
  registry.seedFromDiscoveries([
    ...priorSeeds,
    ...discoveries.map(
      (d) => (bank: d.bank, mask: d.mask, smsHits: d.smsHits),
    ),
  ]);

  for (final raw in candidates) {
    registry.learn(
      raw['sender'] as String? ?? '',
      raw['body'] as String? ?? '',
    );
  }

  return Pass1IsolateResult(
    discoveries: discoveries,
    votes: registry.exportVotes(),
  );
}

