import 'dart:math';

import 'category_info.dart';

/// Source string persisted for user-minted cash moves (not SMS-parsed).
const String kManualSource = 'manual';

/// Reserved for future paste-SMS rows; preserved across full SMS rescan.
const String kPasteSource = 'paste';

/// Default merchant / message for a manual mint by [SpendCategory].
String defaultManualMessage(SpendCategory category) {
  return switch (category) {
    SpendCategory.food => 'Cash · Food',
    SpendCategory.travel => 'Cash · Travel',
    SpendCategory.shopping => 'Cash · Shopping',
    SpendCategory.bills => 'Cash · Bills',
    SpendCategory.entertainment => 'Cash · Entertainment',
    SpendCategory.health => 'Cash · Health',
    SpendCategory.emi => 'Cash · EMI',
    SpendCategory.atm => 'Cash withdrawn',
    SpendCategory.transfer => 'Cash transfer',
    SpendCategory.income => 'Cash received',
    SpendCategory.other => 'Cash spend',
  };
}

/// Default direction: Income → In (credit); everything else → Out.
bool defaultManualIsCredit(SpendCategory category) =>
    category == SpendCategory.income;

/// True when [source] must survive an SMS wipe / full rescan.
bool isPreservedAcrossSmsRescan(String source) =>
    source == kManualSource || source == kPasteSource;

/// Rounds to paise (2 decimal places) using half-up style via cents.
double roundManualAmount(double amount) {
  return (amount * 100).roundToDouble() / 100;
}

/// Validates a user-entered amount. Returns an error string, or null if OK.
String? validateManualAmount(double? amount) {
  if (amount == null || amount.isNaN || amount.isInfinite) {
    return 'Enter an amount';
  }
  if (amount <= 0) return 'Amount must be greater than zero';
  final rounded = roundManualAmount(amount);
  if (rounded <= 0) return 'Amount must be greater than zero';
  return null;
}

/// Clamps a chosen calendar day to today when it would otherwise be in the
/// future. Returns the (possibly clamped) local midnight day.
DateTime clampManualDay(DateTime day, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final chosen = DateTime(day.year, day.month, day.day);
  if (chosen.isAfter(today)) return today;
  return chosen;
}

/// Timestamp for a manual mint on [day]: keep the current clock when the day
/// is today; otherwise strike at local noon for stable day-strip ordering.
DateTime manualTimestampForDay(DateTime day, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final clamped = clampManualDay(day, now: n);
  final today = DateTime(n.year, n.month, n.day);
  if (clamped.year == today.year &&
      clamped.month == today.month &&
      clamped.day == today.day) {
    return n;
  }
  return DateTime(clamped.year, clamped.month, clamped.day, 12);
}

/// `manual_<32-hex>` id — never an inbox sms_id and never an `sms_` prefix.
String newManualTransactionId({Random? random}) {
  final r = random ?? Random.secure();
  final hex = List.generate(16, (_) => r.nextInt(256))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return 'manual_$hex';
}
