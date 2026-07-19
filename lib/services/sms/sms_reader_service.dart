import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../data/sms_scan_state.dart';
import 'account_bank_registry.dart';
import 'account_discovery.dart';
import 'parsed_sms_transaction.dart';
import 'sms_parse_isolate.dart';

/// A bank SMS that passed all pipeline stages and was parsed.
class SmsScanHit {
  const SmsScanHit({required this.message, required this.transaction});

  final SmsMessageInput message;
  final ParsedSmsTransaction transaction;
}

/// Progress update while scanning a large SMS inbox.
class SmsScanProgress {
  const SmsScanProgress({
    required this.scanned,
    required this.total,
    required this.bankCandidates,
    required this.parsed,
    required this.done,
    this.isIncremental = false,
  });

  final int scanned;
  final int total;
  final int bankCandidates;
  final int parsed;
  final bool done;
  final bool isIncremental;

  double get fraction => total > 0 ? scanned / total : 0;
}

/// Configuration for a full or incremental inbox scan.
class SmsScanOptions {
  const SmsScanOptions({
    this.batchSize = 500,
    this.sinceMs,
    this.resumeOffset = 0,
    this.incremental = false,
    this.defaultHistoryMonths = 24,
  });

  final int batchSize;
  final int? sinceMs;
  final int resumeOffset;
  final bool incremental;
  final int defaultHistoryMonths;

  /// Relative window helper (months ago from now). The full/first scan reads
  /// the entire inbox (sinceMs == null); this is now only used as the
  /// incremental-sync fallback when there is no last-scan checkpoint.
  static int defaultSinceMs({int months = 24}) {
    final now = DateTime.now();
    return DateTime(now.year, now.month - months, now.day)
        .millisecondsSinceEpoch;
  }
}

/// Full inbox scan output: parsed transactions + discovered accounts.
class SmsInboxScanResult {
  const SmsInboxScanResult({
    required this.hits,
    required this.discoveredAccounts,
  });

  final List<SmsScanHit> hits;
  final List<DiscoveredAccount> discoveredAccounts;
}

/// Reads SMS inbox on Android via platform channel.
class SmsReaderService {
  static const _channel = MethodChannel('com.paisa.paisa_app/sms');
  static const defaultBatchSize = 500;

  Future<bool> hasSmsPermission() async {
    if (!Platform.isAndroid) return false;
    if (await Permission.sms.isGranted) return true;
    try {
      final granted = await _channel.invokeMethod<bool>('hasPermission');
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestSmsPermission() async {
    if (!Platform.isAndroid) return false;
    final status = await Permission.sms.request();
    return status.isGranted;
  }

  /// True when the user selected "Don't allow" so the system dialog will no
  /// longer appear — the only way forward is the app's system settings page.
  Future<bool> isPermissionPermanentlyDenied() async {
    if (!Platform.isAndroid) return false;
    return Permission.sms.isPermanentlyDenied;
  }

  /// Opens the OS app-settings page so the user can grant SMS access manually.
  Future<bool> openPermissionSettings() => openAppSettings();

  Future<int> getInboxCount({int? sinceMs}) async {
    if (!Platform.isAndroid || !await hasSmsPermission()) return 0;
    try {
      final count = await _channel.invokeMethod<int>(
        'getInboxCount',
        sinceMs != null ? {'sinceMs': sinceMs} : null,
      );
      return count ?? 0;
    } on PlatformException catch (_) {
      return 0;
    }
  }

  Future<
      ({
        List<SmsMessageInput> candidates,
        List<SmsMessageInput> allRows,
        int rowsRead,
        bool hasMore,
      })> fetchFilteredBatch({
    required int offset,
    int limit = defaultBatchSize,
    int? sinceMs,
  }) async {
    if (!Platform.isAndroid || !await hasSmsPermission()) {
      return (
        candidates: <SmsMessageInput>[],
        allRows: <SmsMessageInput>[],
        rowsRead: 0,
        hasMore: false,
      );
    }

    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'scanInboxBatch',
        {
          'offset': offset,
          'limit': limit,
          if (sinceMs != null) 'sinceMs': sinceMs,
        },
      );
      if (raw == null) {
        return (
          candidates: <SmsMessageInput>[],
          allRows: <SmsMessageInput>[],
          rowsRead: 0,
          hasMore: false,
        );
      }

      List<SmsMessageInput> parseRows(String key) {
        final list = raw[key] as List<dynamic>? ?? [];
        return list.map((item) {
          final map = Map<String, dynamic>.from(item as Map);
          return SmsMessageInput(
            id: map['id']?.toString() ?? '',
            sender: map['sender']?.toString() ?? '',
            body: map['body']?.toString() ?? '',
            timestamp: DateTime.fromMillisecondsSinceEpoch(
              (map['timestamp'] as num?)?.toInt() ?? 0,
            ),
          );
        }).toList();
      }

      final candidates = parseRows('candidates');
      final allRows = parseRows('allRows');

      return (
        candidates: candidates,
        allRows: allRows.isNotEmpty ? allRows : candidates,
        rowsRead: raw['rowsRead'] as int? ?? 0,
        hasMore: raw['hasMore'] as bool? ?? false,
      );
    } on PlatformException catch (_) {
      return (
        candidates: <SmsMessageInput>[],
        allRows: <SmsMessageInput>[],
        rowsRead: 0,
        hasMore: false,
      );
    }
  }

  /// Scans inbox with native pre-filter, isolate parsing, and checkpoint support.
  Future<SmsInboxScanResult> scanInbox({
    SmsScanOptions options = const SmsScanOptions(),
    void Function(SmsScanProgress progress)? onProgress,
    void Function(int offset)? onCheckpoint,
  }) async {
    if (!Platform.isAndroid || !await hasSmsPermission()) {
      return const SmsInboxScanResult(hits: [], discoveredAccounts: []);
    }

    // Full scan (non-incremental): sinceMs == null reads the ENTIRE inbox with
    // no lower bound, so years of history are covered. Incremental sync still
    // fetches only messages since the last scan (falling back to a 1-month
    // window if we somehow have no checkpoint timestamp).
    final sinceMs = options.incremental
        ? (options.sinceMs ?? SmsScanOptions.defaultSinceMs(months: 1))
        : options.sinceMs;

    final total = await getInboxCount(sinceMs: sinceMs);
    if (total == 0) {
      onProgress?.call(
        SmsScanProgress(
          scanned: 0,
          total: 0,
          bankCandidates: 0,
          parsed: 0,
          done: true,
          isIncremental: options.incremental,
        ),
      );
      return const SmsInboxScanResult(hits: [], discoveredAccounts: []);
    }

    final hits = <SmsScanHit>[];
    final discoveries = <DiscoveredAccount>[];
    var offset = options.resumeOffset;
    var bankCandidates = 0;
    var scanned = offset;
    final allCandidates = <SmsMessageInput>[];

    // Pass 1 — collect bank-like SMS so we can learn which bank owns each
    // account suffix (e.g. 0429 = SBI even when ICICI sends the alert).
    while (scanned < total) {
      final batch = await fetchFilteredBatch(
        offset: offset,
        limit: options.batchSize,
        sinceMs: sinceMs,
      );

      if (batch.rowsRead == 0) break;

      bankCandidates += batch.candidates.length;
      allCandidates.addAll(batch.candidates);

      for (final message in batch.allRows) {
        final found = AccountDiscovery.discover(
          sender: message.sender,
          body: message.body,
        );
        if (found != null) discoveries.add(found);
      }

      offset += batch.rowsRead;
      scanned = offset;
      onCheckpoint?.call(offset);

      onProgress?.call(
        SmsScanProgress(
          scanned: scanned.clamp(0, total),
          total: total,
          bankCandidates: bankCandidates,
          parsed: hits.length,
          done: false,
          isIncremental: options.incremental,
        ),
      );

      if (!batch.hasMore) break;
    }

    final registry = AccountBankRegistry();
    for (final message in allCandidates) {
      registry.learn(message.sender, message.body);
    }

    // Pass 2 — parse and attach the correct owning bank per account.
    for (var i = 0; i < allCandidates.length; i += options.batchSize) {
      final end = (i + options.batchSize).clamp(0, allCandidates.length);
      final chunk = allCandidates.sublist(i, end);

      final serializable = chunk
          .map(
            (m) => {
              'id': m.id,
              'sender': m.sender,
              'body': m.body,
              'timestampMs': m.timestamp.millisecondsSinceEpoch,
            },
          )
          .toList();

      final parsed = await parseCandidatesInIsolate(serializable);
      for (final hit in parsed) {
        final txn = hit.toTransaction();
        final last4 = AccountBankRegistry.last4FromMask(txn.maskedAccount);
        final bank = registry.resolveBank(
          sender: hit.sender,
          body: hit.body,
          accountLast4: last4,
          parsedBank: txn.bank,
        );

        hits.add(
          SmsScanHit(
            message: hit.toMessage(),
            transaction: ParsedSmsTransaction(
              amount: txn.amount,
              isCredit: txn.isCredit,
              merchant: txn.merchant,
              bank: bank,
              maskedAccount: txn.maskedAccount,
              timestamp: txn.timestamp,
            ),
          ),
        );
      }

      onProgress?.call(
        SmsScanProgress(
          scanned: total,
          total: total,
          bankCandidates: bankCandidates,
          parsed: hits.length,
          done: false,
          isIncremental: options.incremental,
        ),
      );
    }

    onProgress?.call(
      SmsScanProgress(
        scanned: total,
        total: total,
        bankCandidates: bankCandidates,
        parsed: hits.length,
        done: true,
        isIncremental: options.incremental,
      ),
    );

    return SmsInboxScanResult(
      hits: hits,
      discoveredAccounts: mergeDiscoveries(discoveries).values.toList(),
    );
  }

  /// Builds scan options from persisted state.
  SmsScanOptions optionsFromState(SmsScanState state) {
    if (state.fullScanComplete && state.resumeOffset == 0) {
      final since = state.lastScanAt?.subtract(const Duration(hours: 1));
      return SmsScanOptions(
        sinceMs: since?.millisecondsSinceEpoch ??
            SmsScanOptions.defaultSinceMs(months: 1),
        incremental: true,
      );
    }

    // First / full rescan: no lower bound so the whole SMS history is read.
    return SmsScanOptions(
      sinceMs: null,
      resumeOffset: state.resumeOffset,
      incremental: false,
    );
  }
}
