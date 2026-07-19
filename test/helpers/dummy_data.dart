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
    timestamp: timestamp ?? DateTime(2026, 7, 7, 12, 0),
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

/// Rich dummy dataset spanning multiple months, banks, and categories.
List<Transaction> dummyTransactionHistory() {
  return [
    dummyTxn(
      id: '1',
      merchant: 'Swiggy',
      amount: 486,
      isCredit: false,
      category: SpendCategory.food,
      timestamp: DateTime(2026, 7, 5, 13, 20),
    ),
    dummyTxn(
      id: '2',
      merchant: 'Amazon',
      amount: 2499,
      isCredit: false,
      category: SpendCategory.shopping,
      bank: 'SBI',
      maskedAccount: '••••8890',
      timestamp: DateTime(2026, 7, 6, 10, 0),
    ),
    dummyTxn(
      id: '3',
      merchant: 'Salary',
      amount: 68000,
      isCredit: true,
      category: SpendCategory.income,
      timestamp: DateTime(2026, 7, 1, 9, 0),
    ),
    dummyTxn(
      id: '4',
      merchant: 'HDFC Home Loan EMI',
      amount: 8500,
      isCredit: false,
      category: SpendCategory.emi,
      accountKind: AccountKind.loan,
      timestamp: DateTime(2026, 7, 3, 8, 0),
    ),
    dummyTxn(
      id: '5',
      merchant: 'Ola',
      amount: 312,
      isCredit: false,
      category: SpendCategory.travel,
      bank: 'Axis',
      maskedAccount: '••••2015',
      timestamp: DateTime(2026, 7, 7, 18, 30),
    ),
    dummyTxn(
      id: '6',
      merchant: 'Jio Recharge',
      amount: 299,
      isCredit: false,
      category: SpendCategory.bills,
      bank: 'Paytm',
      maskedAccount: '',
      timestamp: DateTime(2026, 6, 15, 11, 0),
    ),
    dummyTxn(
      id: '7',
      merchant: 'Netflix',
      amount: 649,
      isCredit: false,
      category: SpendCategory.entertainment,
      timestamp: DateTime(2026, 6, 20, 0, 0),
    ),
    dummyTxn(
      id: '8',
      merchant: 'Apollo Pharmacy',
      amount: 450,
      isCredit: false,
      category: SpendCategory.health,
      timestamp: DateTime(2026, 5, 10, 16, 0),
    ),
    dummyTxn(
      id: '9',
      merchant: 'ATM Withdrawal',
      amount: 10000,
      isCredit: false,
      category: SpendCategory.atm,
      timestamp: DateTime(2026, 5, 5, 14, 0),
    ),
    dummyTxn(
      id: '10',
      merchant: 'Friend Transfer',
      amount: 5000,
      isCredit: false,
      category: SpendCategory.transfer,
      timestamp: DateTime(2026, 4, 1, 12, 0),
    ),
    dummyTxn(
      id: '11c',
      merchant: 'Cashback',
      amount: 50,
      isCredit: true,
      category: SpendCategory.income,
      bank: 'SBI',
      maskedAccount: '••••8890',
      timestamp: DateTime(2026, 5, 20, 9, 0),
    ),
    dummyTxn(
      id: '11b',
      merchant: 'Refund',
      amount: 200,
      isCredit: true,
      category: SpendCategory.shopping,
      bank: 'SBI',
      maskedAccount: '••••8890',
      timestamp: DateTime(2026, 6, 10, 9, 0),
    ),
    dummyTxn(
      id: '11',
      merchant: 'Bonus Credit',
      amount: 15000,
      isCredit: true,
      category: SpendCategory.income,
      timestamp: DateTime(2026, 4, 15, 10, 0),
    ),
    dummyTxn(
      id: '12',
      merchant: 'Zomato',
      amount: 650,
      isCredit: false,
      category: SpendCategory.food,
      timestamp: DateTime(2026, 7, 7, 20, 0),
    ),
  ];
}
