import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/models/transaction.dart';
import 'package:paisa_app/providers/finance_store.dart';
import 'package:paisa_app/services/sms/account_discovery.dart';

/// ISSUE-11: same last-4 at two banks must not merge into one account.
void main() {
  test('same mask at HDFC and SBI surfaces as two accounts', () {
    final store = FinanceStore()
      ..seedTransactions([
        Transaction(
          id: '1',
          smsId: '1',
          merchant: 'Swiggy',
          bank: 'HDFC',
          maskedAccount: '••••1234',
          category: SpendCategory.food,
          amount: 200,
          isCredit: false,
          timestamp: DateTime(2026, 7, 10),
          accountKind: AccountKind.savings,
        ),
        Transaction(
          id: '2',
          smsId: '2',
          merchant: 'Salary',
          bank: 'SBI',
          maskedAccount: '••••1234',
          category: SpendCategory.income,
          amount: 50000,
          isCredit: true,
          timestamp: DateTime(2026, 7, 5),
          accountKind: AccountKind.savings,
        ),
      ]);

    final accounts = store.bankAccounts();
    final matching = accounts.where((a) => a.mask == '••••1234').toList();
    expect(matching.length, 2);
    expect(matching.map((a) => a.name).toSet(), containsAll(['HDFC Savings', 'SBI Savings']));
  });
}
