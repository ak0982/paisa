import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// On-device user preferences for privacy and profile.
///
/// Notification toggles (budget / weekly / sync alerts) were removed in
/// ISSUE-6: there was no notification package or SMS receiver backing them,
/// so the settings were placebo. Scan completion still shows an in-app
/// SnackBar after a manual rescan.
class AppSettings extends ChangeNotifier {
  AppSettings(this._prefs);

  final SharedPreferences _prefs;

  static const _maskMerchantsKey = 'privacy_mask_merchants';
  static const _blockScreenshotsKey = 'privacy_block_screenshots';
  static const _userNameKey = 'profile_user_name';
  static const _userEmailKey = 'profile_user_email';
  static const _hiddenBankAccountsKey = 'hidden_bank_account_masks';

  bool get maskMerchantNames => _prefs.getBool(_maskMerchantsKey) ?? false;

  /// Screenshot / screen-recording / recents protection (Android FLAG_SECURE).
  ///
  /// Defaults to **on** (SEC-2): the screens show balances and the Coin Flip
  /// reverse shows the verbatim bank SMS, so the protected state is the safe
  /// default. The customer can turn it off to take screenshots.
  bool get blockScreenshots => _prefs.getBool(_blockScreenshotsKey) ?? true;

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

  Future<void> setMaskMerchantNames(bool value) async {
    await _prefs.setBool(_maskMerchantsKey, value);
    notifyListeners();
  }

  Future<void> setBlockScreenshots(bool value) async {
    await _prefs.setBool(_blockScreenshotsKey, value);
    notifyListeners();
  }

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(prefs);
  }
}
