import 'package:intl/intl.dart';

final _inr = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
);

String formatInr(double amount) => _inr.format(amount);

String formatAmount(double amount, {required bool isCredit}) {
  final formatted = _inr.format(amount.abs());
  return isCredit ? '+$formatted' : '−$formatted';
}

String formatCompactInr(double amount) => formatInr(amount);

/// Shared transaction date/time formats so every surface (rows, group
/// headers, drill-downs, recents, reports) shows dates consistently.
final _txnDateFmt = DateFormat('d MMM yyyy');
final _txnTimeFmt = DateFormat('HH:mm');

/// Absolute transaction date including day, short month and 4-digit year,
/// e.g. `12 Jul 2025`.
String formatTxnDate(DateTime date) => _txnDateFmt.format(date);

/// Time-of-day for a transaction, e.g. `15:45`.
String formatTxnTime(DateTime date) => _txnTimeFmt.format(date);
