import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color, DateTimeRange;
import 'package:flutter/services.dart' show PlatformException;

import '../models/bank_account.dart';
import '../models/budget.dart';
import '../models/category_info.dart';
import '../models/range_report.dart';
import '../models/transaction.dart';
import '../data/transaction_database.dart';
import '../data/sms_scan_state.dart';
import '../services/sms/account_discovery.dart';
import '../services/sms/merchant_categorizer.dart';
import '../services/sms/sms_reader_service.dart';
import '../services/sms/transaction_enrichment.dart';
import '../theme/paisa_colors.dart';

class ScanResult {
  const ScanResult({
    required this.newCount,
    required this.totalCount,
    required this.accountCount,
    required this.categoryCount,
    this.scannedSms = 0,
    this.totalSms = 0,
  });

  final int newCount;
  final int totalCount;
  final int accountCount;
  final int categoryCount;
  final int scannedSms;
  final int totalSms;
}

class FinanceStore extends ChangeNotifier {
  FinanceStore({
    SmsReaderService? smsReader,
    TransactionDatabase? database,
  })  : _smsReader = smsReader ?? SmsReaderService(),
        _db = database ?? TransactionDatabase.instance;

  final SmsReaderService _smsReader;
  final TransactionDatabase _db;

  List<Transaction> _transactions = [];
  List<DiscoveredAccount> _discoveredAccounts = [];
  bool _loading = false;
  String? _error;
  DateTime? _lastSyncedAt;
  SmsScanProgress? _scanProgress;
  Future<ScanResult>? _activeSync;

  List<Transaction> get transactions => List.unmodifiable(_transactions);
  bool get isLoading => _loading;
  String? get error => _error;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  SmsScanProgress? get scanProgress => _scanProgress;
  bool get hasSmsPermission => _hasSmsPermission;
  bool _hasSmsPermission = false;

  /// True when SMS access was permanently denied and requires app settings.
  bool get permissionPermanentlyDenied => _permissionPermanentlyDenied;
  bool _permissionPermanentlyDenied = false;

  Future<void> init() async {
    _hasSmsPermission = await _smsReader.hasSmsPermission();
    _transactions = await _db.getAll();
    _discoveredAccounts = await _db.getDiscoveredAccounts();
    notifyListeners();
  }

  /// Opens the OS settings page for granting SMS access manually.
  Future<void> openPermissionSettings() =>
      _smsReader.openPermissionSettings();

  /// Seeds in-memory transactions for unit tests only.
  @visibleForTesting
  void seedTransactions(List<Transaction> items) {
    _transactions = List.from(items);
    notifyListeners();
  }

  /// Seeds in-memory discovered accounts for unit tests / diagnostics only.
  @visibleForTesting
  void seedDiscoveredAccounts(List<DiscoveredAccount> items) {
    _discoveredAccounts = List.from(items);
    notifyListeners();
  }

  /// Wipes all local transactions and scan progress.
  Future<void> clearAllData() async {
    await _db.clearAll();
    await _db.resetScanState();
    _transactions = [];
    _discoveredAccounts = [];
    _lastSyncedAt = null;
    _scanProgress = null;
    _error = null;
    _loading = false;
    notifyListeners();
  }

  /// Reads SMS inbox, parses with regex, persists new transactions.
  ///
  /// Re-entrancy guarded: if a scan is already running (e.g. the user pulls
  /// to refresh repeatedly), the in-flight scan is returned instead of
  /// starting a second overlapping scan.
  Future<ScanResult> syncFromSms() {
    return _activeSync ??= _runSync().whenComplete(() => _activeSync = null);
  }

  // --- Launch scan coordination (ISSUE-7) ---
  //
  // A schema/categorizer version bump requires a one-time full rescan. This
  // used to run in main() *before* runApp, which froze the splash for the whole
  // (multi-year) scan and, on fresh installs, popped the OS permission dialog
  // over a dead screen instead of the onboarding flow. Instead, main() records
  // the decision here and the app shell runs the scan after the first frame
  // (with the existing progress UI). Version stamps are persisted only after the
  // rescan future completes, so a process death mid-scan retries next launch.
  bool _pendingFullRescan = false;
  Future<void> Function()? _persistScanVersions;

  /// Records whether the next launch scan should be a full rescan (schema bump)
  /// and how to persist the version stamps once it completes. Called from
  /// main() before runApp.
  void configureLaunchScan({
    required bool needsRescan,
    required Future<void> Function() persistVersions,
  }) {
    _pendingFullRescan = needsRescan;
    _persistScanVersions = persistVersions;
  }

  /// Marks the pending launch rescan as already satisfied (e.g. onboarding just
  /// performed the initial full scan), so the app shell won't wipe-and-rescan
  /// again on first entry.
  void markLaunchScanSatisfied() {
    _pendingFullRescan = false;
  }

  /// Runs the appropriate scan for app launch, invoked from the shell after the
  /// first frame. Full rescan when a schema/categorizer bump is pending, else a
  /// normal incremental sync.
  Future<ScanResult> runLaunchScan() async {
    if (_pendingFullRescan) {
      _pendingFullRescan = false;
      final result = await fullRescanFromSms();
      await _persistScanVersions?.call();
      return result;
    }
    return syncFromSms();
  }

  /// Re-reads the full SMS inbox from scratch and refreshes every stored
  /// transaction (e.g. after parser improvements).
  ///
  /// Clears existing transactions first so phantom accounts from older parser
  /// versions cannot linger in Profile.
  Future<ScanResult> fullRescanFromSms() async {
    await _db.clearAll();
    _transactions = [];
    _discoveredAccounts = [];
    await _db.resetScanState();
    return syncFromSms();
  }

  Future<ScanResult> _runSync() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      _hasSmsPermission = await _smsReader.hasSmsPermission();
      if (!_hasSmsPermission) {
        _hasSmsPermission = await _smsReader.requestSmsPermission();
      }

      if (!_hasSmsPermission) {
        _permissionPermanentlyDenied =
            await _smsReader.isPermissionPermanentlyDenied();
        _error = 'SMS permission is required to read bank alerts.';
        _loading = false;
        notifyListeners();
        return ScanResult(
          newCount: 0,
          totalCount: _transactions.length,
          accountCount: bankAccounts().length,
          categoryCount: usedCategories.length,
        );
      }

      _permissionPermanentlyDenied = false;

      final scanState = await _db.getScanState();
      final scanOptions = _smsReader.optionsFromState(scanState);
      // Full scan reads the entire inbox (sinceMs == null). We persist 0
      // (epoch) as the effective "since" so it's clear the window is unbounded.
      final sinceMs = scanOptions.sinceMs ?? 0;

      final scan = await _smsReader.scanInbox(
        options: scanOptions,
        onProgress: (progress) {
          _scanProgress = progress;
          notifyListeners();
        },
        onCheckpoint: (offset) async {
          await _db.saveScanState(
            (await _db.getScanState()).copyWith(resumeOffset: offset),
          );
        },
      );
      final hits = scan.hits;
      // Merge (not replace) so accounts discovered in earlier scans survive an
      // incremental sync that returns few/no discoveries. A full rescan clears
      // the table first, so this rebuilds the authoritative set. See ISSUE-1.
      await _db.mergeDiscoveredAccounts(scan.discoveredAccounts);
      _discoveredAccounts = await _db.getDiscoveredAccounts();
      final lastProgress = _scanProgress;
      final existingSmsIds = await _db.getExistingSmsIds();
      final transactionsToSave = <Transaction>[];
      var newCount = 0;

      for (final hit in hits) {
        final message = hit.message;
        final parsed = hit.transaction;
        final isNew = !existingSmsIds.contains(message.id);
        if (isNew) newCount++;

        final category = MerchantCategorizer.categorize(
          merchant: parsed.merchant,
          smsBody: message.body,
          isCredit: parsed.isCredit,
        );

        final mask = TransactionEnrichment.resolveMaskedAccount(
          parsedMask: parsed.maskedAccount,
          sender: message.sender,
          body: message.body,
        );
        var bank = parsed.bank;
        var displayMask = mask;
        final accountKind = TransactionEnrichment.resolveAccountKind(
          bank: bank,
          mask: mask,
          body: message.body,
          discoveries: _discoveredAccounts,
        );
        if (accountKind == AccountKind.loan) {
          final loanDisplay = TransactionEnrichment.resolveLoanDisplay(
            body: message.body,
            parsedBank: bank,
            parsedMask: mask,
            discoveries: _discoveredAccounts,
          );
          bank = loanDisplay.bank;
          if (loanDisplay.mask.isNotEmpty) displayMask = loanDisplay.mask;
        } else if (accountKind == AccountKind.creditCard) {
          final ccDisplay = TransactionEnrichment.resolveCreditCardDisplay(
            body: message.body,
            parsedBank: bank,
            parsedMask: mask,
            discoveries: _discoveredAccounts,
          );
          bank = ccDisplay.bank;
          if (ccDisplay.mask.isNotEmpty) displayMask = ccDisplay.mask;
        }

        var merchant = TransactionEnrichment.improveMerchant(
          merchant: parsed.merchant,
          body: message.body,
          isCredit: parsed.isCredit,
          accountKind: accountKind,
        );
        if (category == SpendCategory.emi &&
            RegExp(r'emi|loan', caseSensitive: false).hasMatch(message.body)) {
          final emiMatch = RegExp(
            r'((?:HDFC|SBI|ICICI|Axis|Kotak)?\s*(?:Home Loan|Personal Loan|Car Loan|EMI)[A-Za-z0-9 ]*)',
            caseSensitive: false,
          ).firstMatch(message.body);
          if (emiMatch != null) {
            merchant = emiMatch.group(1)!.trim();
          } else {
            merchant = '${parsed.bank} EMI';
          }
        }

        transactionsToSave.add(
          Transaction(
            id: 'sms_${message.id}',
            smsId: message.id,
            merchant: merchant,
            bank: bank,
            maskedAccount: displayMask,
            category: category,
            amount: parsed.amount,
            isCredit: parsed.isCredit,
            timestamp: parsed.timestamp,
            source: 'SMS',
            accountKind: accountKind,
          ),
        );
      }

      if (transactionsToSave.isNotEmpty) {
        // Cross-source de-duplication: drop wallet-sourced mirrors of a
        // bank-sourced payment (one UPI payment → two SMS). See ISSUE-4.
        final deduped =
            _dropCrossSourceDuplicates(transactionsToSave, _transactions);
        await _db.upsertAll(deduped);
      }

      await _db.saveScanState(
        SmsScanState(
          fullScanComplete: true,
          resumeOffset: 0,
          lastScanAt: DateTime.now(),
          scanSinceMs: sinceMs,
        ),
      );

      _transactions = await _db.getAll();
      _lastSyncedAt = DateTime.now();
      _loading = false;
      _scanProgress = null;
      notifyListeners();

      return ScanResult(
        newCount: newCount,
        totalCount: _transactions.length,
        accountCount: bankAccounts().length,
        categoryCount: usedCategories.length,
        scannedSms: lastProgress?.scanned ?? hits.length,
        totalSms: lastProgress?.total ?? hits.length,
      );
    } catch (e, stackTrace) {
      // ISSUE-8: never surface raw PlatformException / stack internals in the
      // UI. Log the details for debugging, show a short friendly message.
      debugPrint('FinanceStore: SMS scan failed: $e');
      debugPrintStack(stackTrace: stackTrace);
      _error = friendlyScanError(e);
      _loading = false;
      _scanProgress = null;
      notifyListeners();
      return ScanResult(
        newCount: 0,
        totalCount: _transactions.length,
        accountCount: bankAccounts().length,
        categoryCount: usedCategories.length,
      );
    }
  }

  /// Maps a raw scan exception to a short, user-facing message. Never leaks
  /// PlatformException internals or stack details into the UI (ISSUE-8) — those
  /// are logged via debugPrint instead.
  @visibleForTesting
  static String friendlyScanError(Object error) {
    if (error is PlatformException) {
      return "We couldn't read your SMS inbox. Please check that SMS access "
          'is allowed and try again.';
    }
    return 'Something went wrong while scanning your messages. '
        'Please try again.';
  }

  @visibleForTesting
  List<Transaction> debugDropCrossSourceDuplicates(
    List<Transaction> candidates,
    List<Transaction> existing,
  ) =>
      _dropCrossSourceDuplicates(candidates, existing);

  /// Cross-source de-duplication (ISSUE-4).
  ///
  /// One UPI payment often produces two SMS — the bank's "debited from a/c"
  /// alert and the wallet's "Rs.X paid to Y via Paytm" alert — with different
  /// SMS ids, so both would otherwise be stored as separate transactions. Drop a
  /// candidate when an already-kept transaction (in [existing] or earlier in
  /// this scan) has the SAME direction and amount within [_selfTransferWindow]
  /// AND one side is a wallet source with a DIFFERENT bank (i.e. it is the
  /// cross-source mirror, not two distinct payments from the same source).
  ///
  /// Bank-sourced rows are preferred, so the wallet mirror is the one dropped.
  /// We intentionally do NOT dedupe purely on "same mask" (as originally
  /// proposed) because two genuine same-amount purchases from one account within
  /// three minutes would be wrongly collapsed.
  List<Transaction> _dropCrossSourceDuplicates(
    List<Transaction> candidates,
    List<Transaction> existing,
  ) {
    bool isWallet(String bank) => _walletBanks.contains(bank);

    // Process bank-sourced candidates first so a wallet mirror is dropped
    // rather than the bank row.
    final ordered = [...candidates]..sort(
        (a, b) =>
            (isWallet(a.bank) ? 1 : 0).compareTo(isWallet(b.bank) ? 1 : 0),
      );

    final keptByAmount = <(bool, double), List<Transaction>>{};
    for (final t in existing) {
      keptByAmount.putIfAbsent((t.isCredit, t.amount), () => []).add(t);
    }

    final result = <Transaction>[];
    for (final c in ordered) {
      final peers = keptByAmount[(c.isCredit, c.amount)];
      var isDuplicate = false;
      if (peers != null) {
        for (final p in peers) {
          if (c.timestamp.difference(p.timestamp).abs() > _selfTransferWindow) {
            continue;
          }
          if ((isWallet(c.bank) || isWallet(p.bank)) && c.bank != p.bank) {
            isDuplicate = true;
            break;
          }
        }
      }
      if (isDuplicate) continue;
      result.add(c);
      keptByAmount.putIfAbsent((c.isCredit, c.amount), () => []).add(c);
    }
    return result;
  }

  // --- Date range analytics ---

  /// Earliest transaction timestamp, or null when there is no data.
  DateTime? get earliestTransactionDate {
    if (_transactions.isEmpty) return null;
    return _transactions
        .map((t) => t.timestamp)
        .reduce((a, b) => a.isBefore(b) ? a : b);
  }

  List<Transaction> transactionsInRange(DateTime start, DateTime end) {
    return _transactions.where((t) {
      return !t.timestamp.isBefore(start) && !t.timestamp.isAfter(end);
    }).toList();
  }

  /// Builds a full analytics report for an inclusive [start]–[end] range.
  RangeReport buildReport(DateTime start, DateTime end) {
    final items = transactionsInRange(start, end);
    // KPIs exclude internal movement (CC bill payments, CC payment-received,
    // self-transfers). See ISSUE-4.
    final debits = _spendTxns(items);
    final credits = _incomeTxns(items);

    final spent = _sumAmount(debits);
    final income = _sumAmount(credits);

    final categoryMap = <SpendCategory, double>{};
    for (final t in debits) {
      categoryMap[t.category] = (categoryMap[t.category] ?? 0) + t.amount;
    }
    final sortedCategories = Map.fromEntries(
      categoryMap.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value)),
    );

    final merchantTotals = <String, (double count, double amount)>{};
    for (final t in debits) {
      final existing = merchantTotals[t.merchant];
      merchantTotals[t.merchant] = (
        (existing?.$1 ?? 0) + 1,
        (existing?.$2 ?? 0) + t.amount,
      );
    }
    final topMerchants = (merchantTotals.entries.toList()
          ..sort((a, b) => b.value.$2.compareTo(a.value.$2)))
        .take(5)
        .map((e) {
      final count = e.value.$1.round();
      final label = count == 1 ? '1 transaction' : '$count transactions';
      return (e.key, label, e.value.$2);
    }).toList();

    final incomeTotals = <String, double>{};
    for (final t in credits) {
      incomeTotals[t.merchant] = (incomeTotals[t.merchant] ?? 0) + t.amount;
    }
    final incomeSources = (incomeTotals.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(5)
        .map((e) => (e.key, e.value))
        .toList();

    final byDay = <String, double>{};
    for (final t in debits) {
      final key = '${t.timestamp.year}-${t.timestamp.month}-${t.timestamp.day}';
      byDay[key] = (byDay[key] ?? 0) + t.amount;
    }
    final highestDaySpend =
        byDay.isEmpty ? 0.0 : byDay.values.reduce((a, b) => a > b ? a : b);

    final report = RangeReport(
      start: start,
      end: end,
      spent: spent,
      income: income,
      transactionCount: items.length,
      categorySpending: sortedCategories,
      topMerchants: topMerchants,
      incomeSources: incomeSources,
      dailyAverage: 0,
      highestDaySpend: highestDaySpend,
      topCategory:
          sortedCategories.isEmpty ? null : sortedCategories.keys.first,
    );

    return RangeReport(
      start: report.start,
      end: report.end,
      spent: report.spent,
      income: report.income,
      transactionCount: report.transactionCount,
      categorySpending: report.categorySpending,
      topMerchants: report.topMerchants,
      incomeSources: report.incomeSources,
      dailyAverage: spent / report.dayCount,
      highestDaySpend: report.highestDaySpend,
      topCategory: report.topCategory,
    );
  }

  // --- Time filters ---

  double _monthSpending(int year, int month) {
    final inMonth = _transactions
        .where((t) => t.timestamp.year == year && t.timestamp.month == month)
        .toList();
    return _sumAmount(_spendTxns(inMonth));
  }

  /// Always the current calendar month. Home / Budgets summary metrics use this
  /// even when the month has no spending yet (zeros / empty states).
  DateTime get currentMonth {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }

  /// Latest month with debit spending. Prefer [currentMonth] for Home; this
  /// remains for callers that want a non-empty historical spending month.
  DateTime get activeMonth {
    final current = currentMonth;
    if (_transactions.isEmpty) return current;

    if (_monthSpending(current.year, current.month) > 0) return current;

    final latest =
        _transactions.map((t) => t.timestamp).reduce((a, b) => a.isAfter(b) ? a : b);
    var probe = DateTime(latest.year, latest.month);
    for (var i = 0; i < 36; i++) {
      if (_monthSpending(probe.year, probe.month) > 0) return probe;
      probe = DateTime(probe.year, probe.month - 1);
    }

    return DateTime(latest.year, latest.month);
  }

  /// Insights now span the FULL transaction history (all time) rather than a
  /// fixed rolling window. [insightsSince] is the earliest transaction date
  /// (epoch when empty) so any date-window math still has a valid lower bound.
  DateTime get insightsSince =>
      earliestTransactionDate ?? DateTime.fromMillisecondsSinceEpoch(0);

  List<Transaction> get insightsTransactions =>
      List<Transaction>.from(_transactions);

  /// Dynamic label reflecting the real data range, e.g. "Since Apr 2026",
  /// or "All time" when there are no transactions yet.
  String get insightsPeriodLabel {
    final earliest = earliestTransactionDate;
    if (earliest == null) return 'All time';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return 'Since ${months[earliest.month - 1]} ${earliest.year}';
  }

  double get insightsSpent => _sumAmount(_spendTxns(insightsTransactions));

  Map<SpendCategory, double> get insightsCategorySpending {
    final map = <SpendCategory, double>{};
    for (final t in _spendTxns(insightsTransactions)) {
      map[t.category] = (map[t.category] ?? 0) + t.amount;
    }
    return map;
  }

  List<(String name, String sub, double amount)> get insightsTopMerchants {
    final totals = <String, (double count, double amount)>{};
    for (final t in _spendTxns(insightsTransactions)) {
      if (_isGenericInsightsMerchant(t.merchant)) continue;
      final existing = totals[t.merchant];
      totals[t.merchant] = (
        (existing?.$1 ?? 0) + 1,
        (existing?.$2 ?? 0) + t.amount,
      );
    }
    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.$2.compareTo(a.value.$2));
    return sorted.take(5).map((e) {
      final count = e.value.$1.round();
      final label = count == 1 ? '1 transaction' : '$count transactions';
      return (e.key, label, e.value.$2);
    }).toList();
  }

  double get insightsDailyAverage {
    final earliest = earliestTransactionDate;
    if (earliest == null) return 0;
    // Average over the real span of history (earliest txn → today).
    final spanDays = DateTime.now().difference(earliest).inDays + 1;
    final days = spanDays.clamp(1, 1000000);
    return insightsSpent / days;
  }

  double get insightsHighestDaySpend {
    final byDay = <String, double>{};
    for (final t in _spendTxns(insightsTransactions)) {
      final key =
          '${t.timestamp.year}-${t.timestamp.month}-${t.timestamp.day}';
      byDay[key] = (byDay[key] ?? 0) + t.amount;
    }
    if (byDay.isEmpty) return 0;
    return byDay.values.reduce((a, b) => a > b ? a : b);
  }

  double? insightsFoodDelta() {
    final now = DateTime.now();
    final recentStart = now.subtract(const Duration(days: 90));
    final priorStart = now.subtract(const Duration(days: 180));

    double foodBetween(DateTime start, DateTime end) =>
        _spendTxns(insightsTransactions)
            .where(
              (t) =>
                  t.category == SpendCategory.food &&
                  t.timestamp.isAfter(start) &&
                  !t.timestamp.isAfter(end),
            )
            .fold(0.0, (sum, t) => sum + t.amount);

    // Last 90 days vs the prior 90 days (matches the Insights copy). Works
    // fine on sparse history — returns null when there's no food spend in
    // either window.
    final recent = foodBetween(recentStart, now);
    final prior = foodBetween(priorStart, recentStart);
    if (recent == 0 && prior == 0) return null;
    return recent - prior;
  }

  static bool _isGenericInsightsMerchant(String merchant) {
    final m = merchant.trim().toLowerCase();
    if (m.length < 3) return true;
    return m == 'transaction' ||
        m == 'credit received' ||
        m == 'transfer' ||
        m.startsWith('trf to ');
  }

  /// The single predicate that decides whether a transaction is shown on Home.
  ///
  /// Home's headline totals (spent / income) AND the Today / This month lists
  /// are all built from this exact predicate, so the number in the hero card can
  /// never disagree with the rows below it. Every real debit and credit counts —
  /// including self-transfer legs (e.g. SBI→Axis is one debit + one credit).
  /// OTP / promo / scam SMS are already dropped upstream in the scan pipeline,
  /// so no category is hidden here.
  bool countsOnHome(Transaction t) => t.countsTowardCashflowSummary;

  bool _inMonth(Transaction t, DateTime month) =>
      t.timestamp.year == month.year && t.timestamp.month == month.month;

  List<Transaction> get currentMonthTransactions {
    final month = currentMonth;
    return _transactions
        .where((t) => _inMonth(t, month) && countsOnHome(t))
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  /// Current-month activity for Home spend/income (includes transfers).
  List<Transaction> get homeMonthTransactions => currentMonthTransactions;

  /// Transactions dated today (local calendar day), newest first.
  List<Transaction> get todayTransactions {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    return _transactions.where((t) {
      return countsOnHome(t) &&
          !t.timestamp.isBefore(start) &&
          t.timestamp.isBefore(end);
    }).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  /// Today's cashflow activity for Home (includes transfers).
  List<Transaction> get homeTodayTransactions => todayTransactions;

  /// Current-month transactions excluding today — for the Home “This month” list.
  List<Transaction> get earlierThisMonthTransactions {
    final todayIds = todayTransactions.map((t) => t.id).toSet();
    return currentMonthTransactions
        .where((t) => !todayIds.contains(t.id))
        .toList();
  }

  /// Home “This month” list: cashflow txns earlier in the month (not today).
  List<Transaction> get earlierThisMonthHomeTransactions {
    final todayIds = homeTodayTransactions.map((t) => t.id).toSet();
    return homeMonthTransactions
        .where((t) => !todayIds.contains(t.id))
        .toList();
  }

  /// Kept for callers; transfers now count, so this is always false.
  bool get currentMonthHasOnlyTransfers => false;

  /// Latest debits outside the current calendar month — for Home when this
  /// month has no spending yet.
  List<Transaction> recentSpendingOutsideCurrentMonth({int limit = 8}) {
    final month = currentMonth;
    final list = _transactions
        .where(
          (t) =>
              !t.isCredit &&
              (t.timestamp.year != month.year ||
                  t.timestamp.month != month.month),
        )
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list.take(limit).toList();
  }

  /// Home no longer falls back to a past month; always false.
  bool get isViewingHistoricalMonth => false;

  int get activeMonthTransactionCount => homeMonthTransactions.length;

  List<Transaction> get _dashboardMonthTransactions => homeMonthTransactions;

  List<Transaction> get previousMonthTransactions {
    final month = currentMonth;
    final prev = DateTime(month.year, month.month - 1, 1);
    return _transactions.where((t) {
      return t.timestamp.year == prev.year && t.timestamp.month == prev.month;
    }).toList();
  }

  // --- Cashflow KPI helpers (ISSUE-4) ---
  //
  // Spend / income KPIs exclude INTERNAL MOVEMENT so the headline numbers
  // reflect real money in/out, while the lists still show every row:
  //   * credit-card bill payments (debits) and CC "payment received" (credits),
  //     via the per-transaction countsTowardSpend / countsTowardIncome flags;
  //   * self / account-to-account transfers between the user's OWN accounts,
  //     detected here by pairing a `transfer`-categorised debit with a
  //     same-amount credit within a short window (both legs then excluded).
  //
  // We do NOT simply exclude `category == transfer`: ordinary UPI merchant
  // purchases are frequently worded "trf to <merchant>" and categorised as
  // transfer, so a blanket exclusion would drop genuine spend. Requiring a
  // MATCHING opposite leg means only money that left one of your accounts and
  // arrived in another is netted out.
  static const Duration _selfTransferWindow = Duration(minutes: 3);

  Set<String> _selfTransferLegIds(List<Transaction> txns) {
    final debitsByAmount = <double, List<Transaction>>{};
    for (final t in txns) {
      if (!t.isCredit &&
          t.category == SpendCategory.transfer &&
          t.countsTowardSpend) {
        debitsByAmount.putIfAbsent(t.amount, () => []).add(t);
      }
    }
    if (debitsByAmount.isEmpty) return const {};

    final matched = <String>{};
    final usedDebits = <String>{};
    for (final c in txns) {
      if (!c.isCredit || !c.countsTowardIncome) continue;
      final peers = debitsByAmount[c.amount];
      if (peers == null) continue;
      for (final d in peers) {
        if (usedDebits.contains(d.id)) continue;
        if (c.timestamp.difference(d.timestamp).abs() <= _selfTransferWindow) {
          matched
            ..add(c.id)
            ..add(d.id);
          usedDebits.add(d.id);
          break;
        }
      }
    }
    return matched;
  }

  /// Debits that count toward spend KPIs (excludes CC bill payments and
  /// self-transfer legs).
  List<Transaction> _spendTxns(List<Transaction> txns) {
    final internal = _selfTransferLegIds(txns);
    return txns
        .where((t) => t.countsTowardSpend && !internal.contains(t.id))
        .toList();
  }

  /// Credits that count toward income KPIs (excludes CC payment-received and
  /// self-transfer legs).
  List<Transaction> _incomeTxns(List<Transaction> txns) {
    final internal = _selfTransferLegIds(txns);
    return txns
        .where((t) => t.countsTowardIncome && !internal.contains(t.id))
        .toList();
  }

  static double _sumAmount(Iterable<Transaction> txns) =>
      txns.fold(0.0, (sum, t) => sum + t.amount);

  // --- Derived stats ---

  double get monthlySpent => _sumAmount(_spendTxns(_dashboardMonthTransactions));

  double get monthlyIncome =>
      _sumAmount(_incomeTxns(_dashboardMonthTransactions));

  double get monthlySaved =>
      (monthlyIncome - monthlySpent).clamp(0, double.infinity);

  double get savingsRate {
    if (monthlyIncome <= 0) return 0;
    return (monthlySaved / monthlyIncome).clamp(0.0, 1.0);
  }

  Map<SpendCategory, double> get categorySpending {
    final map = <SpendCategory, double>{};
    for (final t in _spendTxns(_dashboardMonthTransactions)) {
      map[t.category] = (map[t.category] ?? 0) + t.amount;
    }
    return map;
  }

  Set<SpendCategory> get usedCategories =>
      currentMonthTransactions.map((t) => t.category).toSet();

  List<(String name, String sub, double amount)> get topMerchants {
    final totals = <String, (double count, double amount)>{};
    for (final t in _spendTxns(_dashboardMonthTransactions)) {
      final existing = totals[t.merchant];
      totals[t.merchant] = (
        (existing?.$1 ?? 0) + 1,
        (existing?.$2 ?? 0) + t.amount,
      );
    }
    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.$2.compareTo(a.value.$2));
    return sorted.take(5).map((e) {
      final count = e.value.$1.round();
      final label = count == 1 ? '1 transaction' : '$count transactions';
      return (e.key, label, e.value.$2);
    }).toList();
  }

  double get dailyAverage {
    final now = DateTime.now();
    // Average over elapsed days in the current calendar month.
    final days = now.day.clamp(1, 31);
    return monthlySpent / days;
  }

  double get highestDaySpend {
    final byDay = <String, double>{};
    for (final t in _spendTxns(_dashboardMonthTransactions)) {
      final key =
          '${t.timestamp.year}-${t.timestamp.month}-${t.timestamp.day}';
      byDay[key] = (byDay[key] ?? 0) + t.amount;
    }
    if (byDay.isEmpty) return 0;
    return byDay.values.reduce((a, b) => a > b ? a : b);
  }

  double get spentMoreThanLastMonth {
    final prev = _sumAmount(_spendTxns(previousMonthTransactions));
    return monthlySpent - prev;
  }

  double? foodDeltaVsLastMonth() {
    double sum(List<Transaction> list) => _spendTxns(list)
        .where((t) => t.category == SpendCategory.food)
        .fold(0.0, (s, t) => s + t.amount);
    final current = sum(currentMonthTransactions);
    final prev = sum(previousMonthTransactions);
    if (current == 0 && prev == 0) return null;
    return current - prev;
  }

  List<Budget> get budgets {
    final spending = categorySpending;
    if (spending.isEmpty) return [];

    return spending.entries.map((e) {
      final spent = e.value;
      // Auto budget: 30% headroom, minimum ₹1,000, rounded to ₹100
      final limit = ((spent * 1.3) / 100).ceil() * 100;
      final effectiveLimit = limit < 1000 ? 1000.0 : limit.toDouble();
      return Budget(category: e.key, spent: spent, limit: effectiveLimit);
    }).toList()
      ..sort((a, b) => b.spent.compareTo(a.spent));
  }

  double get totalBudget =>
      budgets.fold(0.0, (sum, b) => sum + b.limit);

  double get budgetSpent =>
      budgets.fold(0.0, (sum, b) => sum + b.spent);

  static const _realBanks = {
    'HDFC',
    'SBI',
    'ICICI',
    'Axis',
    'Kotak',
    'Yes Bank',
    'IndusInd',
    'PNB',
    'Canara',
    'Bank of Baroda',
    'IDFC',
    'Federal',
  };

  static bool _isRealBankAccount(String bank, String maskedAccount) {
    if (!_realBanks.contains(bank)) return false;
    return _isRealMask(maskedAccount);
  }

  static bool _isRealMask(String maskedAccount) {
    if (!RegExp(r'••••\d{4}$').hasMatch(maskedAccount)) return false;
    final last4 = int.tryParse(maskedAccount.substring(4));
    // Reject year-like suffixes pulled from dates in wallet SMS.
    if (last4 != null && last4 >= 2015 && last4 <= 2035) return false;
    return true;
  }

  /// Whether a transaction should surface as a discovered account of [kind].
  ///
  /// Savings accounts must belong to a recognised bank. Credit-card and loan
  /// accounts are allowed for any non-wallet issuer (e.g. "BOB" card) as long as
  /// the mask is a real masked last-4, so cards from smaller issuers still show.
  static bool _isAccountTransaction(String bank, String mask, AccountKind kind) {
    if (kind == AccountKind.savings) return _isRealBankAccount(bank, mask);
    if (!_isRealMask(mask)) return false;
    if (bank.isEmpty || _walletBanks.contains(bank)) return false;
    return true;
  }

  static String _kindLabel(AccountKind kind) {
    switch (kind) {
      case AccountKind.creditCard:
        return 'Credit Card';
      case AccountKind.loan:
        return 'Loan';
      case AccountKind.savings:
        return 'Savings';
    }
  }

  static String _kindBadge(AccountKind kind) {
    switch (kind) {
      case AccountKind.creditCard:
        return 'C';
      case AccountKind.loan:
        return 'L';
      case AccountKind.savings:
        return 'B';
    }
  }

  /// All savings, credit-card, and loan accounts found in SMS.
  ///
  /// Tracks money received into and sent from each account. Account-holder
  /// names are ignored — only deposit/credit and debit/spend totals matter.
  static const _walletBanks = {
    'Paytm',
    'PhonePe',
    'GPay',
    'Amazon Pay',
    'MobiKwik',
    'Freecharge',
    'Airtel Money',
    'Ola Money',
    'Jio Money',
    'PayZapp',
    'Bank',
  };

  List<BankAccount> bankAccounts({Set<String> hiddenMasks = const {}}) {
    final accountsByKey = <String, BankAccount>{};
    final merged = mergeDiscoveries(_discoveredAccounts);

    // --- Resolve the account kind for each mask from the STRONGEST signal ---
    //
    // Account discovery (regex over raw SMS) only fires on a handful of narrow
    // SMS shapes, so most credit-card / loan masks are never discovered and used
    // to fall through to "Savings". However every stored transaction already
    // carries a correctly resolved [AccountKind] (via
    // TransactionEnrichment.resolveAccountKind, which understands "spent on your
    // credit card", "BOBCARD", CCBP bill payments, EMI/loan a/c, etc.).
    //
    // We aggregate both sources per mask and classify by the DOMINANT kind
    // (balanced voting), so a savings account that occasionally pays a card bill
    // stays savings while a mask whose activity is genuinely on a card becomes a
    // card. This is fully generic — it keys on bank + masked last4 and relies
    // only on the same signals used to classify transactions, with no hardcoded
    // card numbers.
    final kinds = _AccountKindEvidence();
    for (final d in merged.values) {
      kinds.addDiscovery(d);
    }
    for (final t in _transactions) {
      kinds.addTransaction(t);
    }

    // Group transactions per mask, routed by the mask's dominant resolved kind
    // so every mask surfaces as exactly one account of its winning kind.
    final statsByMask = <String, _SavingsStats>{};
    for (final t in _transactions) {
      if (hiddenMasks.contains(t.maskedAccount)) continue;
      final kind = kinds.kindForMask(t.maskedAccount);
      if (!_isAccountTransaction(t.bank, t.maskedAccount, kind)) continue;

      final stats = statsByMask.putIfAbsent(t.maskedAccount, _SavingsStats.new);
      stats.bankVotes[t.bank] = (stats.bankVotes[t.bank] ?? 0) + 1;
      stats.activityCount++;
      if (t.isCredit) {
        stats.received += t.amount;
      } else {
        stats.spent += t.amount;
      }
    }

    for (final mask in statsByMask.keys) {
      if (hiddenMasks.contains(mask)) continue;
      final stats = statsByMask[mask]!;
      if (stats.activityCount < 1) continue;

      final kind = kinds.kindForMask(mask);
      final bank = kinds.bankForMask(mask, kind) ??
          stats.bankVotes.entries
              .reduce((a, b) => a.value >= b.value ? a : b)
              .key;
      final key = '${kind.name}|$bank|$mask';

      accountsByKey[key] = BankAccount(
        name: '$bank ${_kindLabel(kind)}',
        mask: mask,
        badge: bank.isNotEmpty ? bank[0].toUpperCase() : _kindBadge(kind),
        color: _bankColor(bank),
        receivedTotal: stats.received,
        spentTotal: stats.spent,
        kind: kind,
        activityCount: stats.activityCount,
      );
    }

    for (final d in merged.values) {
      if (hiddenMasks.contains(d.mask)) continue;
      final resolvedKind = kinds.kindForMask(d.mask);

      if (d.kind == AccountKind.savings) {
        // A discovered "savings" mask that transactions prove is a card/loan is
        // handled by the transaction loop above — skip the savings fallback.
        if (resolvedKind != AccountKind.savings) continue;
        if (!_isRealBankAccount(d.bank, d.mask)) continue;
        if (_walletBanks.contains(d.bank) && !statsByMask.containsKey(d.mask)) {
          continue;
        }
        if (d.smsHits < 2) continue;
        final key = 'savings|${d.bank}|${d.mask}';
        if (accountsByKey.containsKey(key) ||
            statsByMask.containsKey(d.mask)) {
          continue;
        }
        accountsByKey[key] = BankAccount(
          name: '${d.bank} Savings',
          mask: d.mask,
          badge: d.bank.isNotEmpty ? d.bank[0].toUpperCase() : 'B',
          color: _bankColor(d.bank),
          receivedTotal: d.receivedTotal,
          spentTotal: d.spentTotal,
          kind: AccountKind.savings,
          activityCount: d.smsHits,
        );
        continue;
      }

      if (d.kind == AccountKind.creditCard) {
        if (d.smsHits < 2) continue;
        final key = d.key;
        final existing = accountsByKey[key];
        accountsByKey[key] = BankAccount(
          name: '${d.bank} Credit Card',
          mask: d.mask,
          badge: d.bank.isNotEmpty ? d.bank[0].toUpperCase() : 'C',
          color: _bankColor(d.bank),
          spentTotal: (existing?.spentTotal ?? 0) + d.spentTotal,
          receivedTotal: (existing?.receivedTotal ?? 0) + d.receivedTotal,
          kind: AccountKind.creditCard,
          activityCount: (existing?.activityCount ?? 0) + d.smsHits,
        );
        continue;
      }

      if (d.kind == AccountKind.loan) {
        if (d.smsHits < 1) continue;
        final key = d.key;
        final label = d.accountLabel ?? 'Loan';
        accountsByKey[key] = BankAccount(
          name: '${d.bank} $label',
          mask: d.mask,
          badge: d.bank.isNotEmpty ? d.bank[0].toUpperCase() : 'L',
          color: _bankColor(d.bank),
          spentTotal: d.spentTotal,
          receivedTotal: d.receivedTotal,
          kind: AccountKind.loan,
          activityCount: d.smsHits,
        );
      }
    }

    final accounts = accountsByKey.values.toList()
      ..sort((a, b) {
        final kindOrder = a.kind.index.compareTo(b.kind.index);
        if (kindOrder != 0) return kindOrder;
        final aScore = a.receivedTotal + a.spentTotal;
        final bScore = b.receivedTotal + b.spentTotal;
        return bScore.compareTo(aScore);
      });
    return accounts;
  }

  Color _bankColor(String bank) {
    switch (bank.toUpperCase()) {
      case 'HDFC':
        return PaisaColors.bankHdfc;
      case 'ICICI':
        return PaisaColors.bankIcici;
      case 'AXIS':
        return PaisaColors.bankAxis;
      case 'SBI':
        return PaisaColors.bankSbi;
      case 'KOTAK':
        return PaisaColors.bankKotak;
      default:
        return PaisaColors.primary;
    }
  }

  String get currentMonthLabel {
    final month = currentMonth;
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[month.month - 1]} ${month.year}';
  }

  String get shortMonthLabel {
    final month = currentMonth;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return months[month.month - 1];
  }

  /// Inclusive date range for the current calendar month (for “See all”).
  DateTimeRange get currentMonthRange {
    final month = currentMonth;
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 0, 23, 59, 59);
    return DateTimeRange(start: start, end: end);
  }
}

class _SavingsStats {
  final bankVotes = <String, int>{};
  double received = 0;
  double spent = 0;
  int activityCount = 0;
}

/// Aggregates per-mask evidence for whether an account is a credit card, loan,
/// or plain savings, combining SMS discoveries with already-classified
/// transactions.
///
/// Classification is by BALANCED VOTING per mask, not "any credit-card evidence
/// wins". Each transaction contributes one vote for its own resolved
/// [AccountKind] (the most reliable per-transaction signal), and each SMS
/// discovery contributes weighted votes. A mask is a credit card / loan only
/// when that kind is the DOMINANT signal for the mask. This is critical because
/// a real savings account frequently pays a credit-card bill (CCBP / BBPS /
/// "trf to credit card") or receives a card-related SMS — those funding-side
/// transactions must not flip the whole account to "credit card". The card-ness
/// of a bill payment belongs to the card, not the savings account it was paid
/// from, so a mask dominated by ordinary bank movement (UPI/NEFT/IMPS/salary/
/// ATM) stays savings.
class _AccountKindEvidence {
  final _cc = <String, int>{};
  final _loan = <String, int>{};
  final _savings = <String, int>{};
  final _ccBankVotes = <String, Map<String, int>>{};
  final _loanBankVotes = <String, Map<String, int>>{};

  void addDiscovery(DiscoveredAccount d) {
    if (d.mask.isEmpty) return;
    final weight = d.smsHits < 1 ? 1 : d.smsHits;
    switch (d.kind) {
      case AccountKind.creditCard:
        _cc[d.mask] = (_cc[d.mask] ?? 0) + weight;
        _vote(_ccBankVotes, d.mask, d.bank, weight);
      case AccountKind.loan:
        _loan[d.mask] = (_loan[d.mask] ?? 0) + weight;
        _vote(_loanBankVotes, d.mask, d.bank, weight);
      case AccountKind.savings:
        _savings[d.mask] = (_savings[d.mask] ?? 0) + weight;
    }
  }

  void addTransaction(Transaction t) {
    if (t.maskedAccount.isEmpty) return;
    switch (t.accountKind) {
      case AccountKind.creditCard:
        // A credit-card bill PAID FROM a bank account (CCBP/BBPS debit) is a
        // funding-account movement, not spend ON the card. Count it as savings
        // evidence for the funding mask so paying a card bill can never turn a
        // savings account into a credit card. Genuine on-card activity (spends,
        // payments received on the card) still votes credit card.
        if (_isFundingSideBillPayment(t)) {
          _savings[t.maskedAccount] = (_savings[t.maskedAccount] ?? 0) + 1;
        } else {
          _cc[t.maskedAccount] = (_cc[t.maskedAccount] ?? 0) + 1;
          _vote(_ccBankVotes, t.maskedAccount, t.bank, 1);
        }
      case AccountKind.loan:
        _loan[t.maskedAccount] = (_loan[t.maskedAccount] ?? 0) + 1;
        _vote(_loanBankVotes, t.maskedAccount, t.bank, 1);
      case AccountKind.savings:
        _savings[t.maskedAccount] = (_savings[t.maskedAccount] ?? 0) + 1;
    }
  }

  /// True when a credit-card-kind transaction is really a bill payment made
  /// FROM a bank (funding) account rather than activity on the card itself.
  ///
  /// The enrichment layer labels CCBP debits "Credit card bill payment". When
  /// such a debit could not be routed to a specific discovered card it stays on
  /// the funding account's own mask — that outflow is savings-side money
  /// movement, so it must not count as evidence that the mask is a card.
  static bool _isFundingSideBillPayment(Transaction t) {
    if (t.isCredit) return false;
    return t.merchant.toLowerCase().contains('credit card bill payment');
  }

  AccountKind kindForMask(String mask) {
    final cc = _cc[mask] ?? 0;
    final loan = _loan[mask] ?? 0;
    final savings = _savings[mask] ?? 0;

    // No specific (card/loan) evidence at all → plain savings.
    if (cc == 0 && loan == 0) return AccountKind.savings;

    // Balanced voting: classify by the DOMINANT resolved kind for this mask.
    //
    //  - Credit card wins only when on-card votes strictly exceed savings votes
    //    (and are at least as strong as loan votes). A savings account with many
    //    UPI/NEFT/salary rows that merely paid a few card bills keeps its
    //    savings majority and stays savings.
    //  - Loan wins only when loan votes strictly exceed savings AND credit-card
    //    votes, so a single NACH/ECS loan EMI debited from a savings account
    //    does not flip it to "loan".
    //  - Ties and savings-dominant masks fall through to savings.
    if (cc >= loan && cc > savings) return AccountKind.creditCard;
    if (loan > cc && loan > savings) return AccountKind.loan;
    return AccountKind.savings;
  }

  /// Preferred bank for a mask, using discovered/transaction bank votes for the
  /// resolved kind. Returns null when there is no vote (caller falls back).
  String? bankForMask(String mask, AccountKind kind) {
    final votes = switch (kind) {
      AccountKind.creditCard => _ccBankVotes[mask],
      AccountKind.loan => _loanBankVotes[mask],
      AccountKind.savings => null,
    };
    if (votes == null || votes.isEmpty) return null;
    return votes.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  static void _vote(
    Map<String, Map<String, int>> target,
    String mask,
    String bank,
    int weight,
  ) {
    if (bank.isEmpty) return;
    final votes = target.putIfAbsent(mask, () => <String, int>{});
    votes[bank] = (votes[bank] ?? 0) + weight;
  }
}
