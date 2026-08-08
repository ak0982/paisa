import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/models/transaction.dart';
import 'package:paisa_app/services/sms/account_discovery.dart';
import 'package:paisa_app/services/sms/parsed_sms_transaction.dart';

SmsMessageInput dummySms({
  required String id,
  required String sender,
  required String body,
  DateTime? timestamp,
}) {
  return SmsMessageInput(
    id: id,
    sender: sender,
    body: body,
    timestamp: timestamp ?? dummyNowMonth(day: 7, hour: 12),
  );
}

Transaction dummyTxn({
  required String id,
  required String merchant,
  required double amount,
  required bool isCredit,
  required DateTime timestamp,
  SpendCategory category = SpendCategory.other,
  String bank = 'HDFC',
  String maskedAccount = '••••4321',
  AccountKind accountKind = AccountKind.savings,
}) {
  return Transaction(
    id: id,
    smsId: 'sms_$id',
    merchant: merchant,
    bank: bank,
    maskedAccount: maskedAccount,
    category: category,
    amount: amount,
    isCredit: isCredit,
    timestamp: timestamp,
    accountKind: accountKind,
  );
}

/// A timestamp in the calendar month that is [monthsAgo] before [DateTime.now].
///
/// Shared fixtures use this so Home / Reports "this month" KPIs stay aligned
/// with wall-clock date instead of rotting when a hardcoded month rolls over.
DateTime dummyNowMonth({
  int monthsAgo = 0,
  int day = 1,
  int hour = 0,
  int minute = 0,
}) {
  final now = DateTime.now();
  final first = DateTime(now.year, now.month - monthsAgo, 1);
  final lastDay = DateTime(first.year, first.month + 1, 0).day;
  return DateTime(
    first.year,
    first.month,
    day.clamp(1, lastDay),
    hour,
    minute,
  );
}

/// Inclusive start / end of the calendar month [monthsAgo] before now.
(DateTime start, DateTime end) dummyMonthBounds({int monthsAgo = 0}) {
  final start = dummyNowMonth(monthsAgo: monthsAgo, day: 1);
  final end = DateTime(start.year, start.month + 1, 0, 23, 59, 59, 999);
  return (start, end);
}

/// Rich dummy dataset spanning multiple months, banks, and categories.
///
/// Month 0 = current calendar month (the former hardcoded July 2026 slice).
/// Months 1–3 = prior months (former June / May / April).
List<Transaction> dummyTransactionHistory() {
  return [
    dummyTxn(
      id: '1',
      merchant: 'Swiggy',
      amount: 486,
      isCredit: false,
      category: SpendCategory.food,
      timestamp: dummyNowMonth(day: 5, hour: 13, minute: 20),
    ),
    dummyTxn(
      id: '2',
      merchant: 'Amazon',
      amount: 2499,
      isCredit: false,
      category: SpendCategory.shopping,
      bank: 'SBI',
      maskedAccount: '••••8890',
      timestamp: dummyNowMonth(day: 6, hour: 10),
    ),
    dummyTxn(
      id: '3',
      merchant: 'Salary',
      amount: 68000,
      isCredit: true,
      category: SpendCategory.income,
      timestamp: dummyNowMonth(day: 1, hour: 9),
    ),
    dummyTxn(
      id: '4',
      merchant: 'HDFC Home Loan EMI',
      amount: 8500,
      isCredit: false,
      category: SpendCategory.emi,
      accountKind: AccountKind.loan,
      timestamp: dummyNowMonth(day: 3, hour: 8),
    ),
    dummyTxn(
      id: '5',
      merchant: 'Ola',
      amount: 312,
      isCredit: false,
      category: SpendCategory.travel,
      bank: 'Axis',
      maskedAccount: '••••2015',
      timestamp: dummyNowMonth(day: 7, hour: 18, minute: 30),
    ),
    dummyTxn(
      id: '6',
      merchant: 'Jio Recharge',
      amount: 299,
      isCredit: false,
      category: SpendCategory.bills,
      bank: 'Paytm',
      maskedAccount: '',
      timestamp: dummyNowMonth(monthsAgo: 1, day: 15, hour: 11),
    ),
    dummyTxn(
      id: '7',
      merchant: 'Netflix',
      amount: 649,
      isCredit: false,
      category: SpendCategory.entertainment,
      timestamp: dummyNowMonth(monthsAgo: 1, day: 20),
    ),
    dummyTxn(
      id: '8',
      merchant: 'Apollo Pharmacy',
      amount: 450,
      isCredit: false,
      category: SpendCategory.health,
      timestamp: dummyNowMonth(monthsAgo: 2, day: 10, hour: 16),
    ),
    dummyTxn(
      id: '9',
      merchant: 'ATM Withdrawal',
      amount: 10000,
      isCredit: false,
      category: SpendCategory.atm,
      timestamp: dummyNowMonth(monthsAgo: 2, day: 5, hour: 14),
    ),
    dummyTxn(
      id: '10',
      merchant: 'Friend Transfer',
      amount: 5000,
      isCredit: false,
      category: SpendCategory.transfer,
      timestamp: dummyNowMonth(monthsAgo: 3, day: 1, hour: 12),
    ),
    dummyTxn(
      id: '11c',
      merchant: 'Cashback',
      amount: 50,
      isCredit: true,
      category: SpendCategory.income,
      bank: 'SBI',
      maskedAccount: '••••8890',
      timestamp: dummyNowMonth(monthsAgo: 2, day: 20, hour: 9),
    ),
    dummyTxn(
      id: '11b',
      merchant: 'Refund',
      amount: 200,
      isCredit: true,
      category: SpendCategory.shopping,
      bank: 'SBI',
      maskedAccount: '••••8890',
      timestamp: dummyNowMonth(monthsAgo: 1, day: 10, hour: 9),
    ),
    dummyTxn(
      id: '11',
      merchant: 'Bonus Credit',
      amount: 15000,
      isCredit: true,
      category: SpendCategory.income,
      timestamp: dummyNowMonth(monthsAgo: 3, day: 15, hour: 10),
    ),
    dummyTxn(
      id: '12',
      merchant: 'Zomato',
      amount: 650,
      isCredit: false,
      category: SpendCategory.food,
      timestamp: dummyNowMonth(day: 7, hour: 20),
    ),
  ];
}
