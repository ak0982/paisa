import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color, DateTimeRange;
import 'package:flutter/services.dart' show PlatformException;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/bank_account.dart';
import '../models/budget.dart';
import '../models/category_info.dart';
import '../models/manual_transaction.dart';
import '../models/range_report.dart';
import '../models/transaction.dart';
import '../data/transaction_database.dart';
import '../data/sms_scan_state.dart';
import '../services/sms/account_bank_registry.dart';
import '../services/sms/account_discovery.dart';
import '../services/sms/merchant_categorizer.dart';
import '../services/sms/product_payment_linker.dart';
import '../services/sms/sms_reader_service.dart';
import '../services/sms/transaction_enrichment.dart';
import '../theme/paisa_colors.dart';

/// Period chips on Stats Spend Spiral (rolling windows + custom range).
enum StatsSpiralPeriod { oneMonth, sixMonths, oneYear, allTime, custom }

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
  Future<void>? _initFuture;

  /// Progress-only ticks (throttled). Does not rebuild You/Transactions/Stats data.
  final _scanProgressTick = ChangeNotifier();

  int? _lastProgressNotifyMs;
  static const _progressThrottleMs = 200;

  Map<String, _LedgerAccountBucket>? _cachedBuckets;
  Set<String> _cachedBucketHidden = const {};
  List<BankAccount>? _cachedAccounts;
  Set<String> _cachedAccountHidden = const {};

  List<Transaction> get transactions => List.unmodifiable(_transactions);
  bool get isLoading => _loading;
  String? get error => _error;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  SmsScanProgress? get scanProgress => _scanProgress;
  Listenable get scanProgressListenable => _scanProgressTick;
  bool get hasSmsPermission => _hasSmsPermission;
  bool _hasSmsPermission = false;

  /// True when SMS access was permanently denied and requires app settings.
  bool get permissionPermanentlyDenied => _permissionPermanentlyDenied;
  bool _permissionPermanentlyDenied = false;

  /// Show the existing loading UI on the first frame while [init] runs after
  /// [runApp] (ISSUE-7: do not block the splash on DB/SMS work).
  void prepareForDeferredInit() {
    _loading = true;
  }

  Future<void> init() {
    return _initFuture ??= _doInit();
  }

  Future<void> _doInit() async {
    _hasSmsPermission = await _smsReader.hasSmsPermission();
    _transactions = await _db.getAll();
    _discoveredAccounts = await _db.getDiscoveredAccounts();
    _userBudgetLimits = _parseBudgetLimits(await _db.getCategoryBudgets());
    _userYearlyBudgetLimits =
        _parseBudgetLimits(await _db.getCategoryBudgetsYearly());
    await _loadBudgetPeriodPref();
    _invalidateLedgerCache();
    // Plans default to ₹0 until the user sets them. Existing seeded/user
    // limits already loaded from `category_budgets` are kept as-is.
    _loading = false;
    notifyListeners();
  }

  Future<void> _awaitInit() async {
    final pending = _initFuture;
    if (pending != null) await pending;
  }

  @override
  void dispose() {
    _scanProgressTick.dispose();
    super.dispose();
  }

  void _invalidateLedgerCache() {
    _cachedBuckets = null;
    _cachedAccounts = null;
    _cachedBucketHidden = const {};
    _cachedAccountHidden = const {};
  }

  static bool _sameHiddenMasks(Set<String> a, Set<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }

  void _emitScanProgress(SmsScanProgress progress, {bool force = false}) {
    _scanProgress = progress;
    final now = DateTime.now().millisecondsSinceEpoch;
    final shouldNotify = force ||
        _lastProgressNotifyMs == null ||
        progress.done ||
        now - _lastProgressNotifyMs! >= _progressThrottleMs;
    if (!shouldNotify) return;
    _lastProgressNotifyMs = now;
    _scanProgressTick.notifyListeners();
  }

  /// Spend categories in Budget envelopes — same debit spend pool as Reports KPIs
  /// (`buildReport` / `_spendTxns`). Excludes [SpendCategory.income] (credits).
  static const budgetableCategories = <SpendCategory>[
    SpendCategory.food,
    SpendCategory.travel,
    SpendCategory.shopping,
    SpendCategory.bills,
    SpendCategory.entertainment,
    SpendCategory.health,
    SpendCategory.emi,
    SpendCategory.atm,
    SpendCategory.other,
    SpendCategory.transfer,
  ];

  static const _budgetPeriodKey = 'budget_period';

  /// Active envelope window on the Budget tab (Monthly vs Yearly).
  BudgetPeriod _budgetPeriod = BudgetPeriod.monthly;

  BudgetPeriod get budgetPeriod => _budgetPeriod;

  Future<void> _loadBudgetPeriodPref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_budgetPeriodKey);
      if (raw == BudgetPeriod.yearly.name) {
        _budgetPeriod = BudgetPeriod.yearly;
      } else {
        _budgetPeriod = BudgetPeriod.monthly;
      }
    } catch (_) {
      _budgetPeriod = BudgetPeriod.monthly;
    }
  }

  /// Switches Budget tab between monthly and yearly envelopes; remembers choice.
  Future<void> setBudgetPeriod(BudgetPeriod period) async {
    if (_budgetPeriod == period) return;
    _budgetPeriod = period;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_budgetPeriodKey, period.name);
    } catch (_) {}
  }

  /// User-set monthly spend limits per category (ISSUE-5). A category present
  /// here is stored plan intent (including ₹0). Absent categories default to
  /// plan ₹0 until the user sets one. Persisted in `category_budgets`.
  Map<SpendCategory, double> _userBudgetLimits = {};

  /// User-set yearly spend limits — independent of [_userBudgetLimits].
  /// Persisted in `category_budgets_yearly`.
  Map<SpendCategory, double> _userYearlyBudgetLimits = {};

  Map<SpendCategory, double> _parseBudgetLimits(Map<String, double> raw) {
    final result = <SpendCategory, double>{};
    for (final entry in raw.entries) {
      for (final category in SpendCategory.values) {
        if (category.name == entry.key) {
          result[category] = entry.value;
          break;
        }
      }
    }
    return result;
  }

  Map<SpendCategory, double> _limitsFor(BudgetPeriod period) =>
      period == BudgetPeriod.yearly
          ? _userYearlyBudgetLimits
          : _userBudgetLimits;

  /// Persisted limit for [category] in [period] (defaults to active tab period).
  double? userBudgetLimit(
    SpendCategory category, {
    BudgetPeriod? period,
  }) =>
      _limitsFor(period ?? _budgetPeriod)[category];

  /// Saves an explicit plan for [category] in [period] (defaults to active tab).
  /// ₹0 is allowed and persists. Monthly and yearly rows are independent.
  Future<void> setCategoryBudgetLimit(
    SpendCategory category,
    double limit, {
    BudgetPeriod? period,
  }) async {
    final clamped = limit < 0 ? 0.0 : limit;
    final p = period ?? _budgetPeriod;
    if (p == BudgetPeriod.yearly) {
      await _db.setCategoryBudgetYearly(category.name, clamped);
      _userYearlyBudgetLimits[category] = clamped;
    } else {
      await _db.setCategoryBudget(category.name, clamped);
      _userBudgetLimits[category] = clamped;
    }
    notifyListeners();
  }

  /// Drops the stored plan for [period] so envelopes show limit 0 until set.
  Future<void> clearCategoryBudgetLimit(
    SpendCategory category, {
    BudgetPeriod? period,
  }) async {
    final p = period ?? _budgetPeriod;
    if (p == BudgetPeriod.yearly) {
      await _db.deleteCategoryBudgetYearly(category.name);
      _userYearlyBudgetLimits.remove(category);
    } else {
      await _db.deleteCategoryBudget(category.name);
      _userBudgetLimits.remove(category);
    }
    notifyListeners();
  }

  /// Clears every stored plan for [period] (defaults to the active tab).
  Future<void> clearAllBudgetLimits({BudgetPeriod? period}) async {
    final p = period ?? _budgetPeriod;
    if (p == BudgetPeriod.yearly) {
      await _db.clearCategoryBudgetsYearly();
      _userYearlyBudgetLimits = {};
    } else {
      await _db.clearCategoryBudgets();
      _userBudgetLimits = {};
    }
    notifyListeners();
  }

  /// True when any yearly envelope already has a stored plan (including ₹0).
  bool get hasAnyYearlyBudgetPlan => _userYearlyBudgetLimits.isNotEmpty;

  /// Copies each monthly plan ×12 into yearly. When [overwrite] is false and
  /// a yearly row already exists, that category is left unchanged.
  ///
  /// Returns how many yearly rows were written.
  Future<int> copyMonthlyPlansToYearly({bool overwrite = true}) async {
    var written = 0;
    for (final entry in _userBudgetLimits.entries) {
      if (!overwrite && _userYearlyBudgetLimits.containsKey(entry.key)) {
        continue;
      }
      final yearly = entry.value * 12;
      await _db.setCategoryBudgetYearly(entry.key.name, yearly);
      _userYearlyBudgetLimits[entry.key] = yearly;
      written++;
    }
    if (written > 0) notifyListeners();
    return written;
  }

  /// Spend-KPI transactions for [category] in [range] — same filter as envelope
  /// Spent (`_spendTxns` / `countsTowardSpend` + self-transfer pairing).
  List<Transaction> budgetSpendTransactions(
    SpendCategory category,
    DateTimeRange range,
  ) {
    final items = transactionsInRange(range.start, range.end);
    return _spendTxns(items)
        .where((t) => t.category == category)
        .toList(growable: false);
  }

  /// Round to the nearest ₹100, floored at ₹1,000.
  static double roundBudgetLimit(double raw) {
    final rounded = ((raw / 100).ceil() * 100).toDouble();
    return rounded < 1000 ? 1000.0 : rounded;
  }

  /// Suggested plan for [category] from history (monthly median × 1.1, or
  /// prior-year spend × 1.1 / 12× monthly suggestion for yearly).
  double suggestedBudgetLimit(
    SpendCategory category, {
    BudgetPeriod? period,
  }) {
    final p = period ?? _budgetPeriod;
    if (p == BudgetPeriod.yearly) {
      final lastYear = DateTime.now().year - 1;
      final prior = _categorySpendInYear(category, lastYear);
      if (prior > 0) return roundBudgetLimit(prior * 11 / 10);
      final monthlyHint = suggestedBudgetLimit(
        category,
        period: BudgetPeriod.monthly,
      );
      return roundBudgetLimit(monthlyHint * 12);
    }

    final history = <double>[];
    final anchor = currentMonth;
    for (var i = 1; i <= 3; i++) {
      final month = DateTime(anchor.year, anchor.month - i, 1);
      final spent = _categorySpendInMonth(category, month);
      if (spent > 0) history.add(spent);
    }
    if (history.isNotEmpty) {
      history.sort();
      final median = history.length.isOdd
          ? history[history.length ~/ 2]
          : (history[history.length ~/ 2 - 1] + history[history.length ~/ 2]) /
              2;
      // Use *11/10 (not *1.1) so integer rupee medians stay exact under ceil.
      return roundBudgetLimit(median * 11 / 10);
    }
    final current = categorySpending[category] ?? 0;
    return roundBudgetLimit(current * 11 / 10);
  }

  double _categorySpendInMonth(SpendCategory category, DateTime month) {
    final inMonth = _transactions.where(
      (t) => t.timestamp.year == month.year && t.timestamp.month == month.month,
    );
    return _spendTxns(inMonth.toList())
        .where((t) => t.category == category)
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  double _categorySpendInYear(SpendCategory category, int year) {
    final inYear = _transactions.where((t) => t.timestamp.year == year);
    return _spendTxns(inYear.toList())
        .where((t) => t.category == category)
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  /// Seeds a stored limit for every currently-active spend category that does
  /// not already have one. Called after sync so budgets become fixed user
  /// intent (editable) instead of a live function of this month's spend.
  Set<SpendCategory> _recentSpendCategories() {
    final out = <SpendCategory>{};
    final anchor = currentMonth;
    for (var i = 0; i <= 3; i++) {
      final month = DateTime(anchor.year, anchor.month - i, 1);
      final spent = _spendTxns(
        _transactions
            .where(
              (t) =>
                  t.timestamp.year == month.year &&
                  t.timestamp.month == month.month,
            )
            .toList(),
      );
      for (final t in spent) {
        if (t.category == SpendCategory.income ||
            t.category == SpendCategory.transfer) {
          continue;
        }
        out.add(t.category);
      }
    }
    return out;
  }

  /// Optionally seeds suggested limits for categories with spend history that
  /// lack a stored plan. Not called on init/sync — plans default to ₹0 until
  /// the user sets them. Kept for tests / one-off migration.
  Future<void> ensureDefaultBudgetsSeeded() async {
    final categories = {
      ...categorySpending.keys,
      ..._userBudgetLimits.keys,
      ..._recentSpendCategories(),
    };
    var changed = false;
    for (final category in categories) {
      if (_userBudgetLimits.containsKey(category)) continue;
      // Skip non-spend categories that may appear in the map.
      if (category == SpendCategory.income ||
          category == SpendCategory.transfer) {
        continue;
      }
      final suggestion =
          suggestedBudgetLimit(category, period: BudgetPeriod.monthly);
      await _db.setCategoryBudget(category.name, suggestion);
      _userBudgetLimits[category] = suggestion;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// Opens the OS settings page for granting SMS access manually.
  Future<void> openPermissionSettings() =>
      _smsReader.openPermissionSettings();

  /// Seeds in-memory transactions for unit tests only.
  @visibleForTesting
  void seedTransactions(List<Transaction> items) {
    _transactions = List.from(items);
    _invalidateLedgerCache();
    notifyListeners();
  }

  /// Seeds an in-memory plan for widget tests without opening SQLite
  /// (platform/FFI open can hang under [TestWidgetsFlutterBinding]).
  @visibleForTesting
  void seedCategoryBudgetLimit(
    SpendCategory category,
    double limit, {
    BudgetPeriod? period,
  }) {
    final clamped = limit < 0 ? 0.0 : limit;
    final p = period ?? _budgetPeriod;
    if (p == BudgetPeriod.yearly) {
      _userYearlyBudgetLimits[category] = clamped;
    } else {
      _userBudgetLimits[category] = clamped;
    }
    notifyListeners();
  }

  /// Seeds in-memory discovered accounts for unit tests / diagnostics only.
  @visibleForTesting
  void seedDiscoveredAccounts(List<DiscoveredAccount> items) {
    _discoveredAccounts = List.from(items);
    _invalidateLedgerCache();
    notifyListeners();
  }

  /// Wipes all local transactions (including manual mints) and scan progress.
  Future<void> clearAllData() async {
    await _db.clearAll();
    await _db.resetScanState();
    await _db.clearCategoryBudgets();
    await _db.clearCategoryBudgetsYearly();
    _transactions = [];
    _discoveredAccounts = [];
    _userBudgetLimits = {};
    _userYearlyBudgetLimits = {};
    _lastSyncedAt = null;
    _scanProgress = null;
    _error = null;
    _loading = false;
    _invalidateLedgerCache();
    notifyListeners();
  }

  /// Persists a user-minted cash move (`source: manual`, bank Cash, no smsId).
  ///
  /// Does **not** add Cash to `_realBanks` / You accounts — empty mask +
  /// non-allowlisted bank keep it out of [bankAccounts].
  ///
  /// Throws [ArgumentError] when amount is missing/≤0. Future dates are
  /// clamped to today. Commits to SQLite before refreshing memory so an
  /// in-flight [_runSync] final `getAll()` still includes the row.
  Future<Transaction> addManualTransaction({
    required double amount,
    required DateTime date,
    required SpendCategory category,
    required String message,
    required bool isCredit,
    DateTime? now,
  }) async {
    await _awaitInit();
    final amountError = validateManualAmount(amount);
    if (amountError != null) {
      throw ArgumentError(amountError);
    }
    final rounded = roundManualAmount(amount);
    final clock = now ?? DateTime.now();
    final timestamp = manualTimestampForDay(date, now: clock);
    final trimmed = message.trim();
    final merchant =
        trimmed.isEmpty ? defaultManualMessage(category) : trimmed;

    final tx = Transaction(
      id: newManualTransactionId(),
      smsId: null,
      merchant: merchant,
      bank: 'Cash',
      maskedAccount: '',
      category: category,
      amount: rounded,
      isCredit: isCredit,
      timestamp: timestamp,
      source: kManualSource,
      accountKind: AccountKind.savings,
    );

    await _db.upsertAll([tx]);
    _transactions = await _db.getAll();
    _invalidateLedgerCache();
    notifyListeners();
    return tx;
  }

  /// Deletes a user-minted row. Returns false when the id is missing or not
  /// `source == manual` (SMS rows are never deleted this way).
  Future<bool> deleteManualTransaction(String id) async {
    await _awaitInit();
    Transaction? existing;
    for (final t in _transactions) {
      if (t.id == id) {
        existing = t;
        break;
      }
    }
    if (existing == null || !existing.isManual) return false;
    await _db.deleteByIds([id]);
    _transactions = await _db.getAll();
    _invalidateLedgerCache();
    notifyListeners();
    return true;
  }

  /// Reads SMS inbox, parses with regex, persists new transactions.
  ///
  /// Re-entrancy guarded: if a scan is already running (e.g. the user pulls
  /// to refresh repeatedly), the in-flight scan is returned instead of
  /// starting a second overlapping scan.
  Future<ScanResult> syncFromSms() {
    return _activeSync ??= () async {
      await _awaitInit();
      return _runSync();
    }()
        .whenComplete(() => _activeSync = null);
  }

  /// Builds last4→bank vote counts from already-stored transactions so an
  /// incremental scan's AccountBankRegistry is not empty (ISSUE-12).
  static Map<String, Map<String, int>> _bankVotesFromTransactions(
    List<Transaction> txns,
  ) {
    final votes = <String, Map<String, int>>{};
    for (final t in txns) {
      final last4 = AccountBankRegistry.last4FromMask(t.maskedAccount);
      if (last4 == null) continue;
      final bank = canonicalizeBank(t.bank);
      if (bank.isEmpty || !_realBanks.contains(bank)) continue;
      final bucket = votes.putIfAbsent(last4, () => {});
      bucket[bank] = (bucket[bank] ?? 0) + 1;
    }
    return votes;
  }

  static Map<String, Map<String, int>> _bankVotesFromDiscoveries(
    List<DiscoveredAccount> discoveries,
  ) {
    final votes = <String, Map<String, int>>{};
    for (final d in discoveries) {
      final last4 = AccountBankRegistry.last4FromMask(d.mask);
      if (last4 == null) continue;
      final bank = canonicalizeBank(d.bank);
      if (bank.isEmpty || !_realBanks.contains(bank)) continue;
      final weight = d.smsHits < 1 ? 1 : d.smsHits;
      final bucket = votes.putIfAbsent(last4, () => {});
      bucket[bank] = (bucket[bank] ?? 0) + weight;
    }
    return votes;
  }

  static Map<String, Map<String, int>> _mergeBankVotes(
    Map<String, Map<String, int>> a,
    Map<String, Map<String, int>> b,
  ) {
    final out = <String, Map<String, int>>{
      for (final e in a.entries) e.key: Map<String, int>.from(e.value),
    };
    for (final e in b.entries) {
      final bucket = out.putIfAbsent(e.key, () => {});
      for (final v in e.value.entries) {
        bucket[v.key] = (bucket[v.key] ?? 0) + v.value;
      }
    }
    return out;
  }

  /// Votes captured before a full rescan clears local data, so pass-1 learn
  /// still knows Slice/HDFC/… ownership for beneficiary last-4s.
  Map<String, Map<String, int>>? _rescanSeedVotes;

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

  /// Re-reads the full SMS inbox from scratch and refreshes every SMS-derived
  /// transaction (e.g. after parser improvements).
  ///
  /// Clears SMS rows and discoveries first so phantom accounts from older
  /// parser versions cannot linger in Profile. **Manual / paste mints are
  /// preserved** across the wipe; logout / [clearAllData] still removes them.
  Future<ScanResult> fullRescanFromSms() async {
    await _awaitInit();
    _rescanSeedVotes = _mergeBankVotes(
      _bankVotesFromTransactions(_transactions),
      _bankVotesFromDiscoveries(_discoveredAccounts),
    );
    await _db.clearSmsDerivedData();
    _transactions = await _db.getAll();
    _discoveredAccounts = [];
    _invalidateLedgerCache();
    await _db.resetScanState();
    return syncFromSms();
  }

  Future<ScanResult> _runSync() async {
    _loading = true;
    _error = null;
    _lastProgressNotifyMs = null;
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
      final liveVotes = _bankVotesFromTransactions(_transactions);
      final seedVotes = _rescanSeedVotes != null
          ? _mergeBankVotes(_rescanSeedVotes!, liveVotes)
          : liveVotes;
      _rescanSeedVotes = null;
      final scanOptions = _smsReader.optionsFromState(
        scanState,
        seedBankVotes: seedVotes,
      );
      // Full scan reads the entire inbox (sinceMs == null). We persist 0
      // (epoch) as the effective "since" so it's clear the window is unbounded.
      final sinceMs = scanOptions.sinceMs ?? 0;

      final scan = await _smsReader.scanInbox(
        options: scanOptions,
        onProgress: (progress) {
          _emitScanProgress(
            progress,
            force: progress.done || _lastProgressNotifyMs == null,
          );
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
      _invalidateLedgerCache();
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
          // Keep the funding (debited) bank|mask — never rewrite onto the loan
          // product (CCBP-parallel). Association is merchant / product link only.
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

        final canonicalBank = canonicalizeBank(bank);
        final twinHints =
            TransactionEnrichment.cardAlertTwinHints(message.body);
        transactionsToSave.add(
          Transaction(
            id: 'sms_${message.id}',
            smsId: message.id,
            merchant: merchant,
            bank: canonicalBank.isNotEmpty ? canonicalBank : bank,
            maskedAccount: displayMask,
            category: category,
            amount: parsed.amount,
            isCredit: parsed.isCredit,
            timestamp: parsed.timestamp,
            source: 'SMS',
            accountKind: accountKind,
            isDebitCardAlertTwin: twinHints.isTwin,
            isLeanDebitCardAlert: twinHints.isLean,
          ),
        );
      }

      if (transactionsToSave.isNotEmpty) {
        // Cross-source de-duplication: drop wallet-sourced mirrors of a
        // bank-sourced payment (one UPI payment → two SMS). See ISSUE-4.
        final afterWallet =
            _dropCrossSourceDuplicates(transactionsToSave, _transactions);
        // Same-source debit-card / CCBP / BBPS alert twins (Spent vs ALERT).
        final deduped =
            _dropSameSourceAlertTwins(afterWallet, _transactions);
        if (deduped.isNotEmpty) {
          await _db.upsertAll(deduped);
        }
        // Dropped twin SMS ids must leave the DB — upsert would otherwise
        // leave a previously stored ALERT row after a rescan/overlap.
        final keptIds = deduped.map((t) => t.id).toSet();
        await _db.deleteByIds(
          afterWallet.where((t) => !keptIds.contains(t.id)).map((t) => t.id),
        );
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
      _invalidateLedgerCache();
      _lastSyncedAt = DateTime.now();
      // Plans stay at stored limits (or ₹0). Do not auto-seed suggestions —
      // the Budget tab is a user plan surface.
      _loading = false;
      _scanProgress = null;
      _scanProgressTick.notifyListeners();
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
      // SEC-4: debugPrint is NOT compiled out of release builds — it writes to
      // logcat, where anything with READ_LOGS or an ADB cable can read it. The
      // scan path handles SMS, so keep release builds silent.
      if (kDebugMode) {
        debugPrint('FinanceStore: SMS scan failed: $e');
        debugPrintStack(stackTrace: stackTrace);
      }
      _error = friendlyScanError(e);
      _loading = false;
      _scanProgress = null;
      _scanProgressTick.notifyListeners();
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
  /// are logged via debugPrint in debug builds only (SEC-4).
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

  @visibleForTesting
  List<Transaction> debugDropSameSourceAlertTwins(
    List<Transaction> candidates,
    List<Transaction> existing,
  ) =>
      _dropSameSourceAlertTwins(candidates, existing);

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

  /// Same-source debit-card / CCBP / BBPS alert-twin collapse (schema 35).
  ///
  /// HDFC (and similar) send two spend SMS for one debit-card / SmartPay
  /// charge, seconds apart: a rich `Spent Rs … Bal Rs … BLOCK DC` row and a
  /// lean `ALERT: … spent via Debit Card` security ping. Different SMS ids
  /// would otherwise store both. Drop the lean ping when a same-bank,
  /// same-mask, same-direction, paise-close, same-merchant twin exists within
  /// [_selfTransferWindow].
  ///
  /// Two genuine same-amount purchases (different merchants, or two rich
  /// Spent rows, or not alert-shaped) are both kept — ISSUE-4 still holds.
  /// Opposite-direction legs (HDFC debit + HSBC payment-received) are not
  /// twins.
  List<Transaction> _dropSameSourceAlertTwins(
    List<Transaction> candidates,
    List<Transaction> existing,
  ) {
    // Keep rich Spent/BLOCK DC rows first so a lean ALERT sees them as peers.
    final ordered = [...candidates]..sort(
        (a, b) => (a.isLeanDebitCardAlert ? 1 : 0)
            .compareTo(b.isLeanDebitCardAlert ? 1 : 0),
      );

    final result = <Transaction>[];
    for (final c in ordered) {
      if (_isLeanCardAlert(c) &&
          _hasRichOrStoredAlertTwin(c, existing, result)) {
        continue;
      }
      result.add(c);
    }
    return result;
  }

  bool _isLeanCardAlert(Transaction t) => t.isLeanDebitCardAlert;

  bool _isAlertTwinShape(Transaction t) {
    if (t.isDebitCardAlertTwin || t.isLeanDebitCardAlert) return true;
    final m = t.merchant.toLowerCase();
    return m.contains('ccbbpsno') ||
        m.contains('ccbpsno') ||
        m.contains('ccbbps') ||
        m.contains('bbpsbill') ||
        m.contains('dcsi-bbps');
  }

  bool _hasRichOrStoredAlertTwin(
    Transaction lean,
    List<Transaction> existing,
    List<Transaction> kept,
  ) {
    for (final p in existing) {
      if (p.id == lean.id) continue;
      if (_isLeanCardAlert(p)) continue;
      if (_areSameSourceAlertTwins(lean, p)) return true;
    }
    for (final p in kept) {
      if (p.id == lean.id) continue;
      if (_isLeanCardAlert(p)) continue;
      if (_areSameSourceAlertTwins(lean, p)) return true;
    }
    return false;
  }

  bool _areSameSourceAlertTwins(Transaction a, Transaction b) {
    if (a.isCredit != b.isCredit) return false;
    if (!_isAlertTwinShape(a) || !_isAlertTwinShape(b)) return false;
    if (!ProductPaymentLinker.amountsClose(a.amount, b.amount)) return false;
    if (a.timestamp.difference(b.timestamp).abs() > _selfTransferWindow) {
      return false;
    }
    final aBank = canonicalizeBank(a.bank);
    final bBank = canonicalizeBank(b.bank);
    if (aBank.isEmpty || bBank.isEmpty || aBank != bBank) return false;
    final aLast4 = AccountBankRegistry.last4FromMask(a.maskedAccount);
    final bLast4 = AccountBankRegistry.last4FromMask(b.maskedAccount);
    if (aLast4 == null || bLast4 == null || aLast4 != bLast4) return false;
    return _sameAlertMerchant(a.merchant, b.merchant);
  }

  static bool _sameAlertMerchant(String a, String b) {
    final x = a.trim().toLowerCase();
    final y = b.trim().toLowerCase();
    if (x.isEmpty || y.isEmpty) return false;
    return x == y;
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

    final byDay = <DateTime, double>{};
    for (final t in debits) {
      final key = DateTime(
        t.timestamp.year,
        t.timestamp.month,
        t.timestamp.day,
      );
      byDay[key] = (byDay[key] ?? 0) + t.amount;
    }
    DateTime? highestDay;
    var highestDaySpend = 0.0;
    for (final e in byDay.entries) {
      if (e.value > highestDaySpend) {
        highestDaySpend = e.value;
        highestDay = e.key;
      }
    }

    final report = RangeReport(
      start: start,
      end: end,
      spent: spent,
      income: income,
      transactionCount: items.length,
      spendCount: debits.length,
      categorySpending: sortedCategories,
      topMerchants: topMerchants,
      incomeSources: incomeSources,
      dailyAverage: 0,
      highestDaySpend: highestDaySpend,
      highestDay: highestDay,
      topCategory:
          sortedCategories.isEmpty ? null : sortedCategories.keys.first,
    );

    return RangeReport(
      start: report.start,
      end: report.end,
      spent: report.spent,
      income: report.income,
      transactionCount: report.transactionCount,
      spendCount: report.spendCount,
      categorySpending: report.categorySpending,
      topMerchants: report.topMerchants,
      incomeSources: report.incomeSources,
      dailyAverage: spent / report.dayCount,
      highestDaySpend: report.highestDaySpend,
      highestDay: report.highestDay,
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

  /// IN across the whole insights window — same exclusions as every other
  /// income KPI (no CC payment-received, no self-transfer legs).
  double get insightsIncome => _sumAmount(_incomeTxns(insightsTransactions));

  /// Signed net across the insights window: IN − OUT.
  double get insightsNet => insightsIncome - insightsSpent;

  /// Number of real spend movements in the insights window.
  int get insightsSpendCount => _spendTxns(insightsTransactions).length;

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

  /// Last [count] calendar months of OUT spend, oldest → newest.
  ///
  /// Each entry is `(monthStart, spend)` where [monthStart] is the 1st of that
  /// month. Months with zero spend are included so charts can show gaps.
  List<(DateTime month, double spend)> insightsMonthlySpendSeries({
    int count = 6,
  }) {
    final n = count.clamp(1, 36);
    final now = DateTime.now();
    final current = DateTime(now.year, now.month);
    final out = <(DateTime, double)>[];
    for (var i = n - 1; i >= 0; i--) {
      final month = DateTime(current.year, current.month - i);
      out.add((month, _monthSpending(month.year, month.month)));
    }
    return out;
  }

  /// Inclusive local-day window for Stats spiral period chips.
  ///
  /// Rolling windows end at end-of-today. [custom] is required when
  /// [period] is [StatsSpiralPeriod.custom]; otherwise falls back to 1M.
  DateTimeRange statsSpiralRange(
    StatsSpiralPeriod period, {
    DateTimeRange? custom,
    DateTime? clock,
  }) {
    final now = clock ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (period) {
      case StatsSpiralPeriod.oneMonth:
        return DateTimeRange(
          start: DateTime(today.year, today.month - 1, today.day),
          end: _endOfDay(today),
        );
      case StatsSpiralPeriod.sixMonths:
        return DateTimeRange(
          start: DateTime(today.year, today.month - 6, today.day),
          end: _endOfDay(today),
        );
      case StatsSpiralPeriod.oneYear:
        return DateTimeRange(
          start: DateTime(today.year - 1, today.month, today.day),
          end: _endOfDay(today),
        );
      case StatsSpiralPeriod.allTime:
        final earliest = earliestTransactionDate;
        return DateTimeRange(
          start: earliest != null
              ? DateTime(earliest.year, earliest.month, earliest.day)
              : DateTime(today.year, today.month, 1),
          end: _endOfDay(today),
        );
      case StatsSpiralPeriod.custom:
        final range = custom ??
            DateTimeRange(
              start: DateTime(today.year, today.month - 1, today.day),
              end: today,
            );
        return DateTimeRange(
          start: DateTime(
            range.start.year,
            range.start.month,
            range.start.day,
          ),
          end: _endOfDay(range.end),
        );
    }
  }

  /// Bucketed OUT spend for [start]–[end] (inclusive), oldest → newest.
  ///
  /// Bucketing adapts to span length so the spiral stays readable:
  /// ≤62 days → daily, ≤400 days → weekly, else monthly.
  List<(DateTime bucketStart, double spend)> spendSeriesInRange(
    DateTime start,
    DateTime end,
  ) {
    var s = DateTime(start.year, start.month, start.day);
    var e = DateTime(end.year, end.month, end.day);
    if (e.isBefore(s)) {
      final swap = s;
      s = e;
      e = swap;
    }
    final daySpan = e.difference(s).inDays + 1;
    if (daySpan <= 62) {
      return _dailySpendSeries(s, e);
    }
    if (daySpan <= 400) {
      return _weeklySpendSeries(s, e);
    }
    return _monthlySpendSeries(s, e);
  }

  List<(DateTime, double)> _dailySpendSeries(DateTime s, DateTime e) {
    final out = <(DateTime, double)>[];
    for (var d = s; !d.isAfter(e); d = d.add(const Duration(days: 1))) {
      out.add((d, daySpend(d)));
    }
    return out;
  }

  List<(DateTime, double)> _weeklySpendSeries(DateTime s, DateTime e) {
    final out = <(DateTime, double)>[];
    var cursor = s;
    while (!cursor.isAfter(e)) {
      final weekEnd = cursor.add(const Duration(days: 6));
      final clipEnd = weekEnd.isAfter(e) ? e : weekEnd;
      var sum = 0.0;
      for (var d = cursor;
          !d.isAfter(clipEnd);
          d = d.add(const Duration(days: 1))) {
        sum += daySpend(d);
      }
      out.add((cursor, sum));
      cursor = clipEnd.add(const Duration(days: 1));
    }
    return out;
  }

  List<(DateTime, double)> _monthlySpendSeries(DateTime s, DateTime e) {
    final out = <(DateTime, double)>[];
    var cursor = DateTime(s.year, s.month, 1);
    final lastMonth = DateTime(e.year, e.month, 1);
    while (!cursor.isAfter(lastMonth)) {
      final monthStart = cursor.year == s.year && cursor.month == s.month
          ? s
          : cursor;
      final monthLast = DateTime(cursor.year, cursor.month + 1, 0);
      final monthEnd =
          monthLast.isAfter(e) ? e : monthLast;
      var sum = 0.0;
      for (var d = monthStart;
          !d.isAfter(monthEnd);
          d = d.add(const Duration(days: 1))) {
        sum += daySpend(d);
      }
      out.add((cursor, sum));
      cursor = DateTime(cursor.year, cursor.month + 1, 1);
    }
    return out;
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

  /// Calendar date behind [insightsHighestDaySpend] so Stats can drill into it.
  /// Null when nothing has been spent yet.
  DateTime? get insightsHighestDay {
    final byDay = <DateTime, double>{};
    for (final t in _spendTxns(insightsTransactions)) {
      final key = DateTime(
        t.timestamp.year,
        t.timestamp.month,
        t.timestamp.day,
      );
      byDay[key] = (byDay[key] ?? 0) + t.amount;
    }
    if (byDay.isEmpty) return null;
    var best = byDay.entries.first;
    for (final e in byDay.entries) {
      if (e.value > best.value) best = e;
    }
    return best.key;
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
          t.countsTowardSpend &&
          _isRealBankAccount(t.bank, t.maskedAccount)) {
        debitsByAmount.putIfAbsent(t.amount, () => []).add(t);
      }
    }
    if (debitsByAmount.isEmpty) return const {};

    final matched = <String>{};
    final usedDebits = <String>{};
    for (final c in txns) {
      if (!c.isCredit || !c.countsTowardIncome) continue;
      // Both legs must be distinct real bank accounts. Wallet / P2P credits
      // (LenDenClub, Paytm, empty mask) must not cancel a genuine merchant UPI
      // debit that happens to share the amount within three minutes.
      if (!_isRealBankAccount(c.bank, c.maskedAccount)) continue;
      final peers = debitsByAmount[c.amount];
      if (peers == null) continue;
      for (final d in peers) {
        if (usedDebits.contains(d.id)) continue;
        final cKey = _AccountKindEvidence.evidenceKey(c.bank, c.maskedAccount);
        final dKey = _AccountKindEvidence.evidenceKey(d.bank, d.maskedAccount);
        if (cKey == dKey) continue;
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

  // --- Day Strip (single local calendar day) ---

  /// Inclusive local-midnight start and exclusive next-midnight end for [day].
  static (DateTime start, DateTime end) dayBounds(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    return (start, start.add(const Duration(days: 1)));
  }

  /// Every cash movement on [day]'s local calendar date, oldest → newest.
  /// Includes internal moves (CC bill / self-transfer / CC payment-received).
  List<Transaction> transactionsForDay(DateTime day) {
    final (start, end) = dayBounds(day);
    return _transactions.where((t) {
      return !t.timestamp.isBefore(start) && t.timestamp.isBefore(end);
    }).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  /// OUT for [day]: real spend KPIs (same exclusions as Home / ISSUE-4).
  double daySpend(DateTime day) =>
      _sumAmount(_spendTxns(transactionsForDay(day)));

  /// IN for [day]: real income KPIs (same exclusions as Home / ISSUE-4).
  double dayIncome(DateTime day) =>
      _sumAmount(_incomeTxns(transactionsForDay(day)));

  /// Signed net for [day]: IN − OUT.
  double dayNet(DateTime day) => dayIncome(day) - daySpend(day);

  /// Ids of self-transfer legs within [day]'s transactions.
  Set<String> daySelfTransferLegIds(DateTime day) =>
      _selfTransferLegIds(transactionsForDay(day));

  /// True when [t] appears on the day list but is excluded from OUT/IN KPIs.
  bool isDayInternalMove(Transaction t, {DateTime? day}) {
    if (t.isCreditCardBillPayment || t.isCreditCardPaymentReceived) {
      return true;
    }
    final anchor = day ?? t.timestamp;
    return daySelfTransferLegIds(anchor).contains(t.id);
  }

  /// OUT totals for the last [count] local days ending at [anchor] (inclusive).
  /// Index 0 is oldest; last index is [anchor]'s day. Used for Home intensity ticks.
  List<double> recentDaySpendSeries({DateTime? anchor, int count = 5}) {
    final end = anchor ?? DateTime.now();
    final day = DateTime(end.year, end.month, end.day);
    return List.generate(count, (i) {
      final d = day.subtract(Duration(days: count - 1 - i));
      return daySpend(d);
    });
  }

  // --- Day Strip (inclusive local date range) ---

  /// Inclusive local-midnight start → exclusive day-after-[endInclusive] end.
  static (DateTime start, DateTime endExclusive) rangeBounds(
    DateTime start,
    DateTime endInclusive,
  ) {
    var a = DateTime(start.year, start.month, start.day);
    var b = DateTime(endInclusive.year, endInclusive.month, endInclusive.day);
    if (b.isBefore(a)) {
      final tmp = a;
      a = b;
      b = tmp;
    }
    return (a, b.add(const Duration(days: 1)));
  }

  /// Every cash movement from [start] through [endInclusive] (local calendar).
  /// Includes internal moves. Oldest → newest.
  List<Transaction> transactionsForDateRange(
    DateTime start,
    DateTime endInclusive,
  ) {
    final (lo, hi) = rangeBounds(start, endInclusive);
    return _transactions.where((t) {
      return !t.timestamp.isBefore(lo) && t.timestamp.isBefore(hi);
    }).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  /// OUT KPI for an inclusive local date range (same exclusions as [daySpend]).
  double rangeSpend(DateTime start, DateTime endInclusive) =>
      _sumAmount(_spendTxns(transactionsForDateRange(start, endInclusive)));

  /// IN KPI for an inclusive local date range (same exclusions as [dayIncome]).
  double rangeIncome(DateTime start, DateTime endInclusive) =>
      _sumAmount(_incomeTxns(transactionsForDateRange(start, endInclusive)));

  /// Signed net for an inclusive local date range: IN − OUT.
  double rangeNet(DateTime start, DateTime endInclusive) =>
      rangeIncome(start, endInclusive) - rangeSpend(start, endInclusive);

  /// Self-transfer leg ids within an inclusive local date range.
  Set<String> rangeSelfTransferLegIds(DateTime start, DateTime endInclusive) =>
      _selfTransferLegIds(transactionsForDateRange(start, endInclusive));

  /// True when [t] is listed but excluded from OUT/IN KPIs for [start]–[end].
  bool isRangeInternalMove(
    Transaction t, {
    required DateTime start,
    required DateTime endInclusive,
  }) {
    if (t.isCreditCardBillPayment || t.isCreditCardPaymentReceived) {
      return true;
    }
    return rangeSelfTransferLegIds(start, endInclusive).contains(t.id);
  }

  /// Day-of-month → OUT spend for [month]'s calendar month (local dates).
  /// Days with zero OUT are omitted. Used by Pulse Calendar intensity fills.
  Map<int, double> monthDaySpendMap(DateTime month) {
    final year = month.year;
    final m = month.month;
    final lastDay = DateTime(year, m + 1, 0).day;
    final map = <int, double>{};
    for (var d = 1; d <= lastDay; d++) {
      final spend = daySpend(DateTime(year, m, d));
      if (spend > 0) map[d] = spend;
    }
    return map;
  }

  /// Normalized 0–1 intensity for [day]'s OUT vs peak OUT in that month.
  /// Returns 0 when the day (or month peak) has no spend.
  double daySpendIntensity(DateTime day, {Map<int, double>? monthMap}) {
    final map = monthMap ?? monthDaySpendMap(day);
    final spend = map[day.day] ?? daySpend(day);
    if (spend <= 0) return 0;
    var peak = 0.0;
    for (final v in map.values) {
      if (v > peak) peak = v;
    }
    if (peak <= 0) peak = spend;
    return (spend / peak).clamp(0.0, 1.0);
  }

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

  /// Calendar-year cashflow transactions (same home filter as monthly).
  List<Transaction> get currentYearTransactions {
    final year = DateTime.now().year;
    return _transactions
        .where((t) => t.timestamp.year == year && countsOnHome(t))
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  /// Year-to-date spend per category (current calendar year).
  Map<SpendCategory, double> get yearlyCategorySpending {
    final map = <SpendCategory, double>{};
    for (final t in _spendTxns(currentYearTransactions)) {
      map[t.category] = (map[t.category] ?? 0) + t.amount;
    }
    return map;
  }

  /// Inclusive end-of-local-day — matches Reports `_endOfDay`.
  static DateTime _endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  /// Reports preset "This month": 1st of month → end of today.
  DateTimeRange get reportsThisMonthRange {
    final now = DateTime.now();
    return DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: _endOfDay(now),
    );
  }

  /// Reports preset "This year": Jan 1 → end of today.
  DateTimeRange get reportsThisYearRange {
    final now = DateTime.now();
    return DateTimeRange(
      start: DateTime(now.year, 1, 1),
      end: _endOfDay(now),
    );
  }

  /// Date window for Budget spent / drill-down — mirrors Reports presets.
  DateTimeRange budgetReportRangeFor(BudgetPeriod period) =>
      period == BudgetPeriod.yearly
          ? reportsThisYearRange
          : reportsThisMonthRange;

  /// Spend report for the Budget period (same math as Reports This month/year).
  RangeReport budgetReportFor(BudgetPeriod period) {
    final range = budgetReportRangeFor(period);
    return buildReport(range.start, range.end);
  }

  Map<SpendCategory, double> categorySpendingFor(BudgetPeriod period) =>
      budgetReportFor(period).categorySpending;

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

  /// Spend plans for every budgetable category in the active Budget period.
  List<Budget> get budgets => budgetsFor(_budgetPeriod);

  /// Monthly or yearly envelopes — always the full budgetable set (plan 0 ok).
  List<Budget> budgetsFor(BudgetPeriod period) {
    final spending = categorySpendingFor(period);
    final limits = _limitsFor(period);
    final list = budgetableCategories.map((category) {
      final spent = spending[category] ?? 0.0;
      final stored = limits[category];
      return Budget(
        category: category,
        spent: spent,
        limit: stored ?? 0.0,
        isUserSet: stored != null,
      );
    }).toList();

    // Active rows (spend or a stored plan) first by spent desc, then unset.
    int rank(Budget b) {
      if (b.spent > 0 || b.hasStoredPlan || b.limit > 0) return 0;
      return 1;
    }

    list.sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      final bySpent = b.spent.compareTo(a.spent);
      if (bySpent != 0) return bySpent;
      return a.info.label.compareTo(b.info.label);
    });
    return list;
  }

  double get totalBudget =>
      budgets.fold(0.0, (sum, b) => sum + b.limit);

  double get budgetSpent => budgetSpentFor(_budgetPeriod);

  double totalBudgetFor(BudgetPeriod period) =>
      budgetsFor(period).fold(0.0, (sum, b) => sum + b.limit);

  double budgetSpentFor(BudgetPeriod period) =>
      budgetReportFor(period).spent;

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
    'Union Bank',
    'Bank of India',
    'Indian Bank',
    'IDFC',
    'Federal',
    'HSBC',
    'Slice',
  };

  /// Normalize bank display aliases into a single key (e.g. BOB → Bank of Baroda).
  static String canonicalizeBank(String bank) {
    final b = bank.trim();
    if (b.isEmpty || b == 'Bank') return '';
    switch (b.toLowerCase()) {
      case 'bob':
      case 'baroda':
      case 'bank of baroda':
        return 'Bank of Baroda';
      case 'hdfc bank':
        return 'HDFC';
      case 'sbi bank':
      case 'state bank':
      case 'state bank of india':
        return 'SBI';
      case 'icici bank':
        return 'ICICI';
      case 'axis bank':
        return 'Axis';
      case 'kotak bank':
      case 'kotak mahindra':
      case 'kotak mahindra bank':
        return 'Kotak';
      case 'yes bank':
        return 'Yes Bank';
      case 'idfc bank':
      case 'idfc first':
      case 'idfc first bank':
        return 'IDFC';
      case 'federal bank':
        return 'Federal';
      case 'hsbc bank':
        return 'HSBC';
      case 'slice':
      case 'slice small finance bank':
        return 'Slice';
      case 'pnb':
      case 'punjab national bank':
        return 'PNB';
      case 'canara bank':
        return 'Canara';
      case 'indusind bank':
        return 'IndusInd';
      case 'union bank':
      case 'union bank of india':
        return 'Union Bank';
      case 'boi':
      case 'bank of india':
        return 'Bank of India';
      case 'indian bank':
        return 'Indian Bank';
      default:
        return b;
    }
  }

  static bool _isRealBankAccount(String bank, String maskedAccount) {
    final canonical = canonicalizeBank(bank);
    if (!_realBanks.contains(canonical)) return false;
    return _isRealMask(maskedAccount);
  }

  static bool _isRealMask(String maskedAccount) {
    if (!RegExp(r'••••\d{4}$').hasMatch(maskedAccount)) return false;
    final last4 = int.tryParse(maskedAccount.substring(4));
    // Reject year-like suffixes pulled from dates in wallet SMS.
    if (last4 != null && last4 >= 2015 && last4 <= 2035) return false;
    return true;
  }

  static bool _isMasklessOrUnknown(String mask) =>
      mask.isEmpty || mask.contains('????');

  /// Whether a transaction should surface as a discovered account of [kind].
  ///
  /// Savings accounts must belong to a recognised bank. Credit-card and loan
  /// accounts are allowed for any non-wallet issuer (e.g. "BOB" card) as long as
  /// the mask is a real masked last-4, so cards from smaller issuers still show.
  static bool _isAccountTransaction(String bank, String mask, AccountKind kind) {
    final canonical = canonicalizeBank(bank);
    if (kind == AccountKind.savings) {
      return _isRealBankAccount(canonical, mask);
    }
    if (!_isRealMask(mask)) return false;
    if (canonical.isEmpty || _walletBanks.contains(canonical) || _walletBanks.contains(bank)) {
      return false;
    }
    return true;
  }

  static AccountKind _orphanKind(Transaction t) {
    if (t.isCreditCardBillPayment) return AccountKind.savings;
    return t.accountKind;
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

  /// Public (bank|mask) key used to associate transactions with a You-section
  /// account. Same last-4 at two banks stay separate. Banks are canonicalized.
  static String accountEvidenceKey(String bank, String mask) =>
      _AccountKindEvidence.evidenceKey(bank, mask);

  /// All-time transactions for a You-section account.
  ///
  /// Prefer [evidenceKey] from [BankAccount.evidenceKey] so display-bank remaps
  /// cannot empty the list. Uses the same association as [bankAccounts]
  /// (including product↔funding EMI links).
  List<Transaction> transactionsForAccount({
    String? evidenceKey,
    String? bank,
    String? mask,
  }) {
    final buckets = _ledgerAccountBuckets();
    final key = evidenceKey ??
        ((bank != null && mask != null && mask.isNotEmpty)
            ? accountEvidenceKey(bank, mask)
            : null);
    if (key == null || key.isEmpty) return const [];
    return List<Transaction>.from(buckets[key]?.txns ?? const []);
  }

  /// Groups ledger rows into You-section account buckets (exact mask match +
  /// unambiguous same-bank maskless orphans + same-last4 relay rematch).
  Map<String, _LedgerAccountBucket> _ledgerAccountBuckets({
    Set<String> hiddenMasks = const {},
  }) {
    if (_cachedBuckets != null &&
        _sameHiddenMasks(_cachedBucketHidden, hiddenMasks)) {
      return _cachedBuckets!;
    }
    final buckets = _computeLedgerAccountBuckets(hiddenMasks: hiddenMasks);
    _cachedBuckets = buckets;
    _cachedBucketHidden = Set<String>.from(hiddenMasks);
    if (!_sameHiddenMasks(_cachedAccountHidden, hiddenMasks)) {
      _cachedAccounts = null;
    }
    return buckets;
  }

  Map<String, _LedgerAccountBucket> _computeLedgerAccountBuckets({
    required Set<String> hiddenMasks,
  }) {
    final kinds = _AccountKindEvidence();
    final merged = mergeDiscoveries(_discoveredAccounts);
    final pairingIndex = ProductPairingIndex(_transactions);
    for (final d in merged.values) {
      kinds.addDiscovery(d);
    }
    for (final t in _transactions) {
      kinds.addTransaction(t);
    }

    final buckets = <String, _LedgerAccountBucket>{};
    final orphans = <Transaction>[];
    final assignedIds = <String>{};

    for (final t in _transactions) {
      if (hiddenMasks.contains(t.maskedAccount)) continue;

      if (_isMasklessOrUnknown(t.maskedAccount)) {
        orphans.add(t);
        continue;
      }

      // Loan-kind EMI/NACH stays on the funding bank|mask (same as CCBP).
      // Product association is merchant / resolveAssociatedLoanProduct — never
      // move the debit onto the loan issuer account for listing/balance.

      final kind = kinds.kindFor(t.bank, t.maskedAccount);
      if (!_isAccountTransaction(t.bank, t.maskedAccount, kind)) {
        // Weak bank (Bank / empty / non-allowlist) with a real mask — try rematch later.
        orphans.add(t);
        continue;
      }

      final key = accountEvidenceKey(t.bank, t.maskedAccount);
      final bucket = buckets.putIfAbsent(key, _LedgerAccountBucket.new);
      final voteBank = canonicalizeBank(t.bank);
      bucket.add(
        t,
        voteBank: voteBank.isNotEmpty ? voteBank : t.bank,
        mask: t.maskedAccount,
        evidenceKey: key,
      );
      assignedIds.add(t.id);
    }

    // Index masked buckets by (canonicalBank, kind) for orphan attachment.
    final byBankKind = <String, List<String>>{};
    final byMask = <String, List<String>>{};
    for (final entry in buckets.entries) {
      final bucket = entry.value;
      final majority = bucket.majorityBank;
      final kind = kinds.kindFor(majority, bucket.mask);
      bucket.kind = kind;
      final cBank = canonicalizeBank(majority);
      if (cBank.isEmpty) continue;
      final bk = '${kind.name}|$cBank';
      byBankKind.putIfAbsent(bk, () => []).add(entry.key);
      byMask.putIfAbsent(bucket.mask, () => []).add(entry.key);
    }

    // Prefer discovery-backed owner when the same last-4 was split across banks
    // (e.g. Slice native + ICICI relay mis-tagged as ICICI).
    for (final entry in byMask.entries) {
      final keys = entry.value;
      if (keys.length <= 1) continue;
      final mask = entry.key;
      final discBanks = merged.values
          .where(
            (d) =>
                d.mask == mask &&
                d.kind == AccountKind.savings &&
                _realBanks.contains(canonicalizeBank(d.bank)),
          )
          .map((d) => canonicalizeBank(d.bank))
          .toSet();
      if (discBanks.length != 1) continue;
      final ownerBank = discBanks.first;
      final ownerKey = accountEvidenceKey(ownerBank, mask);
      final owner = buckets.putIfAbsent(ownerKey, () {
        final b = _LedgerAccountBucket();
        b.mask = mask;
        b.evidenceKey = ownerKey;
        b.kind = AccountKind.savings;
        return b;
      });
      for (final key in List<String>.from(keys)) {
        if (key == ownerKey) continue;
        final donor = buckets[key];
        if (donor == null) continue;
        // Last-4 collision with a savings discovery must not swallow a real
        // card or loan (R2-4). Slice+ICICI *savings* relay still folds.
        final donorKind =
            donor.kind ?? kinds.kindFor(donor.majorityBank, donor.mask);
        if (donorKind == AccountKind.creditCard ||
            donorKind == AccountKind.loan) {
          continue;
        }
        for (final t in List<Transaction>.from(donor.txns)) {
          owner.add(
            t,
            voteBank: ownerBank,
            mask: mask,
            evidenceKey: ownerKey,
          );
          assignedIds.add(t.id);
        }
        buckets.remove(key);
      }
      owner.kind = AccountKind.savings;
    }

    // Rebuild indexes after discovery fold.
    byBankKind.clear();
    byMask.clear();
    for (final entry in buckets.entries) {
      final bucket = entry.value;
      final majority = bucket.majorityBank;
      final kind = bucket.kind ?? kinds.kindFor(majority, bucket.mask);
      bucket.kind = kind;
      final cBank = canonicalizeBank(majority);
      if (cBank.isEmpty && bucket.txns.isNotEmpty) {
        // Owner created only from fold — majority may still be empty until votes added.
        continue;
      }
      if (cBank.isEmpty) continue;
      byBankKind.putIfAbsent('${kind.name}|$cBank', () => []).add(entry.key);
      byMask.putIfAbsent(bucket.mask, () => []).add(entry.key);
    }

    for (final t in orphans) {
      if (assignedIds.contains(t.id)) continue;

      // Same-mask rematch: Bank / wrong-bank / maskless → unique real owner.
      if (!_isMasklessOrUnknown(t.maskedAccount)) {
        final owners = byMask[t.maskedAccount]
                ?.where((k) {
                  final b = buckets[k];
                  if (b == null) return false;
                  final bank = canonicalizeBank(b.majorityBank);
                  return bank.isNotEmpty && _realBanks.contains(bank);
                })
                .toList() ??
            const <String>[];
        if (owners.length == 1) {
          final key = owners.first;
          final bucket = buckets[key]!;
          final ownerBank = canonicalizeBank(bucket.majorityBank);
          final kind = bucket.kind ?? AccountKind.savings;
          if (_isAccountTransaction(ownerBank, bucket.mask, kind)) {
            bucket.add(
              t,
              voteBank: ownerBank,
              mask: bucket.mask,
              evidenceKey: key,
            );
            assignedIds.add(t.id);
            continue;
          }
        }
      }

      final cBank = canonicalizeBank(t.bank);
      if (cBank.isEmpty || _walletBanks.contains(cBank)) continue;

      final kind = _orphanKind(t);
      final candidates = byBankKind['${kind.name}|$cBank'];
      if (candidates == null || candidates.length != 1) continue;

      final key = candidates.first;
      final bucket = buckets[key]!;
      if (!_isAccountTransaction(cBank, bucket.mask, kind)) continue;

      bucket.add(
        t,
        voteBank: cBank,
        mask: bucket.mask,
        evidenceKey: key,
      );
      assignedIds.add(t.id);
    }

    // Orphan CCBP under the unique card for drilldown. Loan funding EMI stays
    // on the funding account only (never dual-listed onto the loan bucket).
    _attachLinkedProductPayments(buckets, pairingIndex);

    return buckets;
  }

  void _attachLinkedProductPayments(
    Map<String, _LedgerAccountBucket> buckets,
    ProductPairingIndex pairingIndex,
  ) {
    final discoveries = mergeDiscoveries(_discoveredAccounts).values;
    for (final entry in List<MapEntry<String, _LedgerAccountBucket>>.from(
      buckets.entries,
    )) {
      final bucket = entry.value;
      final kind = bucket.kind;
      // Credit-card orphans only. Loan EMI must not move onto the loan bucket
      // (spend/balance belong on the funding bank that was debited).
      if (kind != AccountKind.creditCard) continue;
      final productBank = canonicalizeBank(bucket.majorityBank);
      if (productBank.isEmpty || bucket.mask.isEmpty) continue;

      final linked = ProductPaymentLinker.linkedFundingTransactions(
        productBank: productBank,
        productMask: bucket.mask,
        productKind: kind!,
        all: _transactions,
        discoveries: discoveries,
        index: pairingIndex,
      );
      final existingIds = bucket.txns.map((t) => t.id).toSet();
      for (final t in linked) {
        if (existingIds.contains(t.id)) continue;
        // Belt-and-suspenders: never double-count a paired product ack.
        final covered = bucket.txns.any(
          (a) =>
              ProductPaymentLinker.amountsClose(a.amount, t.amount) &&
              ProductPaymentLinker.withinPairingWindow(a.timestamp, t.timestamp),
        );
        if (covered) continue;
        bucket.add(
          t,
          voteBank: productBank,
          mask: bucket.mask,
          evidenceKey: entry.key,
        );
        existingIds.add(t.id);
      }
    }
  }

  List<BankAccount> bankAccounts({Set<String> hiddenMasks = const {}}) {
    if (_cachedAccounts != null &&
        _sameHiddenMasks(_cachedAccountHidden, hiddenMasks)) {
      return _cachedAccounts!;
    }
    final accounts = _computeBankAccounts(hiddenMasks: hiddenMasks);
    _cachedAccounts = accounts;
    _cachedAccountHidden = Set<String>.from(hiddenMasks);
    return accounts;
  }

  List<BankAccount> _computeBankAccounts({required Set<String> hiddenMasks}) {
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
    // We aggregate both sources per (bank, mask) and classify by the DOMINANT
    // kind (balanced voting), so a savings account that occasionally pays a
    // card bill stays savings while a mask whose activity is genuinely on a
    // card becomes a card. Keying by bank|mask (ISSUE-11) keeps two banks that
    // share a last-4 from merging into one pooled account.
    final kinds = _AccountKindEvidence();
    for (final d in merged.values) {
      kinds.addDiscovery(d);
    }
    for (final t in _transactions) {
      kinds.addTransaction(t);
    }

    final buckets = _ledgerAccountBuckets(hiddenMasks: hiddenMasks);
    // Rebuild kind on buckets (already set) and emit BankAccount rows.
    for (final entry in buckets.entries) {
      final stats = entry.value;
      final mask = stats.mask;
      if (hiddenMasks.contains(mask)) continue;
      if (stats.activityCount < 1) continue;

      final bank = stats.majorityBank;
      final kind = stats.kind ?? kinds.kindFor(bank, mask);
      final preferredBank = kinds.bankFor(bank, mask, kind) ?? bank;
      final displayBank = canonicalizeBank(preferredBank).isNotEmpty
          ? canonicalizeBank(preferredBank)
          : preferredBank;
      final key = '${kind.name}|$displayBank|$mask';

      accountsByKey[key] = BankAccount(
        bank: displayBank,
        name: '$displayBank ${_kindLabel(kind)}',
        mask: mask,
        badge: displayBank.isNotEmpty
            ? displayBank[0].toUpperCase()
            : _kindBadge(kind),
        color: _bankColor(displayBank),
        evidenceKey: entry.key,
        receivedTotal: stats.received,
        spentTotal: stats.spent,
        kind: kind,
        activityCount: stats.activityCount,
      );
    }

    for (final d in merged.values) {
      if (hiddenMasks.contains(d.mask)) continue;
      final resolvedKind = kinds.kindFor(d.bank, d.mask);
      final evidenceKey = _AccountKindEvidence.evidenceKey(d.bank, d.mask);
      final dBank = canonicalizeBank(d.bank).isNotEmpty
          ? canonicalizeBank(d.bank)
          : d.bank;

      if (d.kind == AccountKind.savings) {
        // A discovered "savings" mask that transactions prove is a card/loan is
        // handled by the transaction loop above — skip the savings fallback.
        if (resolvedKind != AccountKind.savings) continue;
        if (!_isRealBankAccount(dBank, d.mask)) continue;
        if (_walletBanks.contains(dBank) && !buckets.containsKey(evidenceKey)) {
          continue;
        }
        if (d.smsHits < 2) continue;
        final key = 'savings|$dBank|${d.mask}';
        if (accountsByKey.containsKey(key) || buckets.containsKey(evidenceKey)) {
          continue;
        }
        accountsByKey[key] = BankAccount(
          bank: dBank,
          name: '$dBank Savings',
          mask: d.mask,
          badge: dBank.isNotEmpty ? dBank[0].toUpperCase() : 'B',
          color: _bankColor(dBank),
          evidenceKey: evidenceKey,
          receivedTotal: d.receivedTotal,
          spentTotal: d.spentTotal,
          kind: AccountKind.savings,
          activityCount: d.smsHits,
        );
        continue;
      }

      if (d.kind == AccountKind.creditCard) {
        if (d.smsHits < 2) continue;
        // Do not stack discovery totals onto an account that already has ledger
        // rows — drilldown would look emptier than the You card.
        if (buckets.containsKey(evidenceKey)) continue;
        final key = 'creditCard|$dBank|${d.mask}';
        if (accountsByKey.containsKey(key)) continue;
        accountsByKey[key] = BankAccount(
          bank: dBank,
          name: '$dBank Credit Card',
          mask: d.mask,
          badge: dBank.isNotEmpty ? dBank[0].toUpperCase() : 'C',
          color: _bankColor(dBank),
          evidenceKey: evidenceKey,
          spentTotal: d.spentTotal,
          receivedTotal: d.receivedTotal,
          kind: AccountKind.creditCard,
          activityCount: d.smsHits,
        );
        continue;
      }

      if (d.kind == AccountKind.loan) {
        if (d.smsHits < 1) continue;
        if (buckets.containsKey(evidenceKey)) continue;
        final key = 'loan|$dBank|${d.mask}';
        if (accountsByKey.containsKey(key)) continue;
        final label = d.accountLabel ?? 'Loan';
        accountsByKey[key] = BankAccount(
          bank: dBank,
          name: '$dBank $label',
          mask: d.mask,
          badge: dBank.isNotEmpty ? dBank[0].toUpperCase() : 'L',
          color: _bankColor(dBank),
          evidenceKey: evidenceKey,
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

  String get currentYearLabel => '${DateTime.now().year}';

  /// Hero / list subtitle for the active Budget period.
  String get budgetPeriodLabel => _budgetPeriod == BudgetPeriod.yearly
      ? currentYearLabel
      : currentMonthLabel;

  /// Inclusive date range for category drill-down from the Budget tab.
  DateTimeRange get budgetPeriodRange => budgetReportRangeFor(_budgetPeriod);

  /// Days remaining in the active Budget calendar window.
  int get budgetDaysLeft {
    final now = DateTime.now();
    if (_budgetPeriod == BudgetPeriod.yearly) {
      final end = DateTime(now.year, 12, 31);
      return end.difference(DateTime(now.year, now.month, now.day)).inDays;
    }
    final lastDay = DateTime(now.year, now.month + 1, 0).day;
    return lastDay - now.day;
  }

  /// Daily rupees left to stay on plan for the active period (null when N/A).
  ///
  /// Only when there is remaining headroom under a positive total plan and at
  /// least one day left. Prefer monthly pacing on the Budget hero.
  double? get budgetDailyPaceLeft {
    final planned = totalBudget;
    final spent = budgetSpent;
    if (planned <= 0) return null;
    if (Budget.isOverAggregate(planned: planned, spent: spent)) return null;
    final left = (planned - spent).clamp(0.0, double.infinity);
    final days = budgetDaysLeft;
    if (days <= 0 || left <= 0) return null;
    return left / days;
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

  /// Inclusive date range for the current calendar year.
  DateTimeRange get currentYearRange {
    final year = DateTime.now().year;
    final start = DateTime(year, 1, 1);
    final end = DateTime(year, 12, 31, 23, 59, 59);
    return DateTimeRange(start: start, end: end);
  }
}

class _LedgerAccountBucket {
  final bankVotes = <String, int>{};
  final txns = <Transaction>[];
  String mask = '';
  String evidenceKey = '';
  AccountKind? kind;
  double received = 0;
  double spent = 0;
  int activityCount = 0;

  String get majorityBank {
    if (bankVotes.isEmpty) return '';
    return bankVotes.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  void add(
    Transaction t, {
    required String voteBank,
    required String mask,
    required String evidenceKey,
  }) {
    txns.add(t);
    this.mask = mask;
    this.evidenceKey = evidenceKey;
    bankVotes[voteBank] = (bankVotes[voteBank] ?? 0) + 1;
    activityCount++;
    if (t.isCredit) {
      received += t.amount;
    } else {
      spent += t.amount;
    }
  }
}

/// Aggregates per-(bank, mask) evidence for whether an account is a credit card,
/// loan, or plain savings, combining SMS discoveries with already-classified
/// transactions.
///
/// Classification is by BALANCED VOTING per account key (`bank|mask`), not
/// "any credit-card evidence wins". Each transaction contributes one vote for
/// its own resolved [AccountKind], and each SMS discovery contributes weighted
/// votes. A mask is a credit card / loan only when that kind is the DOMINANT
/// signal for that bank+mask. Keying by bank|mask (ISSUE-11) prevents two
/// different banks that happen to share a last-4 from pooling votes / totals.
class _AccountKindEvidence {
  final _cc = <String, int>{};
  final _loan = <String, int>{};
  final _savings = <String, int>{};
  final _ccBankVotes = <String, Map<String, int>>{};
  final _loanBankVotes = <String, Map<String, int>>{};

  /// Composite evidence key. Falls back to mask-only when the bank is unknown
  /// so sparse rows still participate. Banks are canonicalized first.
  static String evidenceKey(String bank, String mask) {
    final c = FinanceStore.canonicalizeBank(bank);
    if (c.isEmpty) return mask;
    return '$c|$mask';
  }

  void addDiscovery(DiscoveredAccount d) {
    if (d.mask.isEmpty) return;
    final key = evidenceKey(d.bank, d.mask);
    final voteBank = FinanceStore.canonicalizeBank(d.bank);
    final weight = d.smsHits < 1 ? 1 : d.smsHits;
    switch (d.kind) {
      case AccountKind.creditCard:
        _cc[key] = (_cc[key] ?? 0) + weight;
        _vote(_ccBankVotes, key, voteBank.isNotEmpty ? voteBank : d.bank, weight);
      case AccountKind.loan:
        _loan[key] = (_loan[key] ?? 0) + weight;
        _vote(_loanBankVotes, key, voteBank.isNotEmpty ? voteBank : d.bank, weight);
      case AccountKind.savings:
        _savings[key] = (_savings[key] ?? 0) + weight;
    }
  }

  void addTransaction(Transaction t) {
    if (t.maskedAccount.isEmpty) return;
    final key = evidenceKey(t.bank, t.maskedAccount);
    final voteBank = FinanceStore.canonicalizeBank(t.bank);
    final bankLabel = voteBank.isNotEmpty ? voteBank : t.bank;
    switch (t.accountKind) {
      case AccountKind.creditCard:
        // A credit-card bill PAID FROM a bank account (CCBP/BBPS debit) is a
        // funding-account movement, not spend ON the card. Count it as savings
        // evidence for the funding mask so paying a card bill can never turn a
        // savings account into a credit card. Genuine on-card activity (spends,
        // payments received on the card) still votes credit card.
        if (_isFundingSideBillPayment(t)) {
          _savings[key] = (_savings[key] ?? 0) + 1;
        } else {
          _cc[key] = (_cc[key] ?? 0) + 1;
          _vote(_ccBankVotes, key, bankLabel, 1);
        }
      case AccountKind.loan:
        // EMI/NACH paid FROM a savings account must not flip that mask to loan.
        if (_isFundingSideLoanPayment(t)) {
          _savings[key] = (_savings[key] ?? 0) + 1;
        } else {
          _loan[key] = (_loan[key] ?? 0) + 1;
          _vote(_loanBankVotes, key, bankLabel, 1);
        }
      case AccountKind.savings:
        _savings[key] = (_savings[key] ?? 0) + 1;
    }
  }

  /// True when a credit-card-kind transaction is really a bill payment made
  /// FROM a bank (funding) account rather than activity on the card itself.
  static bool _isFundingSideBillPayment(Transaction t) {
    if (t.isCredit) return false;
    final m = t.merchant.toLowerCase();
    return m.contains('credit card bill payment') || m.contains('ccbp');
  }

  /// True when a loan-kind row is a funding-account EMI/NACH debit rather than
  /// activity on the loan product mask itself (PNB deposit, disbursal, etc.).
  static bool _isFundingSideLoanPayment(Transaction t) {
    if (t.isCredit) return false;
    final m = t.merchant.toLowerCase();
    // Product-side acknowledgments / disbursals stay loan evidence.
    if (m.contains('disburs') ||
        m.contains('loan payment') ||
        m.contains('against loan') ||
        m.contains('depositing')) {
      return false;
    }
    // Explicit funding-rail merchants only — do not treat every EMI-categorised
    // row as funding (product-side loan activity also uses SpendCategory.emi).
    return m.contains('nach') ||
        m.contains('tp ach') ||
        m.contains('mbk emi') ||
        m.contains('home loan emi') ||
        m.contains('personal loan emi') ||
        m.contains('car loan emi') ||
        RegExp(r'\b[a-z]+\s+emi\b').hasMatch(m);
  }

  AccountKind kindFor(String bank, String mask) {
    final key = evidenceKey(bank, mask);
    final cc = _cc[key] ?? 0;
    final loan = _loan[key] ?? 0;
    final savings = _savings[key] ?? 0;

    if (cc == 0 && loan == 0) return AccountKind.savings;

    if (cc >= loan && cc > savings) return AccountKind.creditCard;
    if (loan > cc && loan > savings) return AccountKind.loan;
    return AccountKind.savings;
  }

  /// Preferred bank for an evidence key, using discovered/transaction bank
  /// votes for the resolved kind. Returns null when there is no vote.
  String? bankFor(String bank, String mask, AccountKind kind) {
    final key = evidenceKey(bank, mask);
    final votes = switch (kind) {
      AccountKind.creditCard => _ccBankVotes[key],
      AccountKind.loan => _loanBankVotes[key],
      AccountKind.savings => null,
    };
    if (votes == null || votes.isEmpty) return null;
    return votes.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  static void _vote(
    Map<String, Map<String, int>> target,
    String key,
    String bank,
    int weight,
  ) {
    if (bank.isEmpty) return;
    final votes = target.putIfAbsent(key, () => <String, int>{});
    votes[bank] = (votes[bank] ?? 0) + weight;
  }
}
