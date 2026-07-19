import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// On-device user preferences for notifications and privacy toggles.
class AppSettings extends ChangeNotifier {
  AppSettings(this._prefs);

  final SharedPreferences _prefs;

  static const _budgetAlertsKey = 'notify_budget_alerts';
  static const _weeklySummaryKey = 'notify_weekly_summary';
  static const _syncCompleteKey = 'notify_sync_complete';
  static const _maskMerchantsKey = 'privacy_mask_merchants';
  static const _userNameKey = 'profile_user_name';
  static const _userEmailKey = 'profile_user_email';
  static const _hiddenBankAccountsKey = 'hidden_bank_account_masks';

  bool get budgetAlerts => _prefs.getBool(_budgetAlertsKey) ?? true;
  bool get weeklySummary => _prefs.getBool(_weeklySummaryKey) ?? true;
  bool get syncCompleteAlerts => _prefs.getBool(_syncCompleteKey) ?? true;
  bool get maskMerchantNames => _prefs.getBool(_maskMerchantsKey) ?? false;

  /// Full name entered during profile setup (empty when not yet set).
  String get userName => _prefs.getString(_userNameKey)?.trim() ?? '';

  /// Optional email entered during profile setup.
  String get userEmail => _prefs.getString(_userEmailKey)?.trim() ?? '';

  /// True once the user has completed the local profile step.
  bool get hasProfile => userName.isNotEmpty;

  /// Masked account suffixes the user marked as "not mine" in Profile.
  Set<String> get hiddenBankAccountMasks {
    final raw = _prefs.getStringList(_hiddenBankAccountsKey);
    if (raw == null || raw.isEmpty) return const {};
    return raw.toSet();
  }

  /// First name for greetings, falling back to a friendly default.
  String get firstName {
    final name = userName;
    if (name.isEmpty) return 'there';
    return name.split(RegExp(r'\s+')).first;
  }

  /// Up to two uppercase initials derived from the name (default 'P').
  String get initials {
    final parts =
        userName.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'P';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  Future<void> setProfile({required String name, String email = ''}) async {
    await _prefs.setString(_userNameKey, name.trim());
    await _prefs.setString(_userEmailKey, email.trim());
    notifyListeners();
  }

  /// Clears profile details (used on logout).
  Future<void> clearProfile() async {
    await _prefs.remove(_userNameKey);
    await _prefs.remove(_userEmailKey);
    notifyListeners();
  }

  Future<void> hideBankAccount(String mask) async {
    final next = {...hiddenBankAccountMasks, mask};
    await _prefs.setStringList(_hiddenBankAccountsKey, next.toList()..sort());
    notifyListeners();
  }

  Future<void> unhideAllBankAccounts() async {
    await _prefs.remove(_hiddenBankAccountsKey);
    notifyListeners();
  }

  Future<void> setBudgetAlerts(bool value) async {
    await _prefs.setBool(_budgetAlertsKey, value);
    notifyListeners();
  }

  Future<void> setWeeklySummary(bool value) async {
    await _prefs.setBool(_weeklySummaryKey, value);
    notifyListeners();
  }

  Future<void> setSyncCompleteAlerts(bool value) async {
    await _prefs.setBool(_syncCompleteKey, value);
    notifyListeners();
  }

  Future<void> setMaskMerchantNames(bool value) async {
    await _prefs.setBool(_maskMerchantsKey, value);
    notifyListeners();
  }

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(prefs);
  }
}
