import 'package:intl/intl.dart';

final _inr = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 2,
);

String formatInr(double amount) => _inr.format(amount);

String formatAmount(double amount, {required bool isCredit}) {
  final formatted = _inr.format(amount.abs());
  return isCredit ? '+$formatted' : '−$formatted';
}

/// Alias of [formatInr] after the paise unification (R2-9). Callers that
/// historically expected a compact/rounded string now get full 2-dp INR.
String formatCompactInr(double amount) => formatInr(amount);

/// Formats a 0–1 spend share for category sticker badges.
///
/// - `<= 0` → empty (caller should omit the badge)
/// - `>= 1%` → integer, e.g. `32%`
/// - `>= 0.1%` → one decimal, e.g. `0.4%`
/// - `>= 0.01%` → two decimals, e.g. `0.03%`
/// - else → `<0.01%`
String formatSharePercent(double share) {
  if (share <= 0) return '';
  final pct = share * 100;
  if (pct >= 1) return '${pct.round()}%';
  if (pct >= 0.1) return '${pct.toStringAsFixed(1)}%';
  if (pct >= 0.01) return '${pct.toStringAsFixed(2)}%';
  return '<0.01%';
}

/// Applies the "mask merchant names" preference to a display label, e.g.
/// `Swiggy` → `Sw••••gy`. Display-only: it never redacts the original bank
/// SMS, which is the source of truth behind a transaction.
String maskedMerchantLabel(String merchant, bool mask) {
  if (!mask || merchant.length <= 2) return merchant;
  if (merchant.length <= 4) {
    return '${merchant[0]}••${merchant[merchant.length - 1]}';
  }
  return '${merchant.substring(0, 2)}••••'
      '${merchant.substring(merchant.length - 2)}';
}

/// Shared transaction date/time formats so every surface (rows, group
/// headers, drill-downs, recents, reports) shows dates consistently.
final _txnDateFmt = DateFormat('d MMM yyyy');
final _txnTimeFmt = DateFormat('HH:mm');

/// Absolute transaction date including day, short month and 4-digit year,
/// e.g. `12 Jul 2025`.
String formatTxnDate(DateTime date) => _txnDateFmt.format(date);

/// Time-of-day for a transaction, e.g. `15:45`.
String formatTxnTime(DateTime date) => _txnTimeFmt.format(date);
