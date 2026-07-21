import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/models/transaction.dart';
import 'package:paisa_app/providers/finance_store.dart';
import 'package:paisa_app/services/sms/account_discovery.dart';

/// ISSUE-4: spend/income KPIs must exclude internal movement (self-transfers,
/// CC bill payments, CC payment-received) while genuine one-sided spend/income
/// still counts. Cross-source duplicate SMS collapse to one row.
void main() {
  final month = DateTime(DateTime.now().year, DateTime.now().month, 15, 12);

  Transaction tx({
    required String id,
    required double amount,
    required bool isCredit,
    required SpendCategory category,
    AccountKind kind = AccountKind.savings,
    String merchant = 'Test',
    String bank = 'SBI',
    String mask = '••••0429',
    Duration offset = Duration.zero,
  }) =>
      Transaction(
        id: id,
        smsId: id,
        merchant: merchant,
        bank: bank,
        maskedAccount: mask,
        category: category,
        amount: amount,
        isCredit: isCredit,
        timestamp: month.add(offset),
        accountKind: kind,
      );

  test('self-transfer pair nets to spend 0, income 0', () {
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'xfer_out',
          amount: 5000,
          isCredit: false,
          category: SpendCategory.transfer,
          merchant: 'Axis Transfer',
        ),
        tx(
          id: 'xfer_in',
          amount: 5000,
          isCredit: true,
          category: SpendCategory.income,
          merchant: 'Self Transfer',
          bank: 'Axis',
          mask: '••••9867',
          offset: const Duration(seconds: 40),
        ),
      ]);

    expect(store.monthlySpent, 0);
    expect(store.monthlyIncome, 0);
    // Both legs remain visible in the list.
    expect(store.homeMonthTransactions.length, 2);
  });

  test('genuine merchant purchase worded "trf to" still counts as spend', () {
    // SBI UPI merchant purchases are categorised as transfer, but there is no
    // matching credit leg, so they must NOT be excluded from spend.
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'buy',
          amount: 3250,
          isCredit: false,
          category: SpendCategory.transfer,
          merchant: 'Innofin Solution',
        ),
      ]);

    expect(store.monthlySpent, 3250);
  });

  test('genuine incoming payment still counts as income', () {
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'salary',
          amount: 50000,
          isCredit: true,
          category: SpendCategory.income,
          merchant: 'Salary',
        ),
      ]);

    expect(store.monthlyIncome, 50000);
  });

  test('card spend counts; CCBP and card payment-received are excluded', () {
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'card_spend',
          amount: 1000,
          isCredit: false,
          category: SpendCategory.shopping,
          kind: AccountKind.creditCard,
          merchant: 'Amazon',
          mask: '••••1111',
        ),
        tx(
          id: 'ccbp',
          amount: 1000,
          isCredit: false,
          category: SpendCategory.transfer,
          kind: AccountKind.creditCard,
          merchant: 'Credit card bill payment',
          mask: '••••1111',
          offset: const Duration(minutes: 30),
        ),
        tx(
          id: 'card_credit',
          amount: 1000,
          isCredit: true,
          category: SpendCategory.transfer,
          kind: AccountKind.creditCard,
          merchant: 'Credit card payment',
          mask: '••••1111',
          offset: const Duration(minutes: 31),
        ),
      ]);

    expect(store.monthlySpent, 1000); // only the real card spend
    expect(store.monthlyIncome, 0); // CC payment-received is not income
  });

  test('two same-amount purchases from one account both count (no false net)',
      () {
    // Only a matching CREDIT nets a transfer debit; two debits must not.
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'chai1',
          amount: 100,
          isCredit: false,
          category: SpendCategory.transfer,
          merchant: 'Chai A',
        ),
        tx(
          id: 'chai2',
          amount: 100,
          isCredit: false,
          category: SpendCategory.transfer,
          merchant: 'Chai B',
          offset: const Duration(minutes: 1),
        ),
      ]);

    expect(store.monthlySpent, 200);
  });

  group('cross-source de-duplication', () {
    final store = FinanceStore();

    Transaction hit({
      required String id,
      required String bank,
      String mask = '',
      double amount = 500,
      Duration offset = Duration.zero,
    }) =>
        Transaction(
          id: id,
          smsId: id,
          merchant: 'Swiggy',
          bank: bank,
          maskedAccount: mask,
          category: SpendCategory.food,
          amount: amount,
          isCredit: false,
          timestamp: month.add(offset),
        );

    test('bank + wallet SMS for one payment collapse to a single row', () {
      final kept = store.debugDropCrossSourceDuplicates(
        [
          hit(id: 'bank', bank: 'HDFC', mask: '••••4321'),
          hit(
            id: 'wallet',
            bank: 'Paytm',
            offset: const Duration(seconds: 30),
          ),
        ],
        const [],
      );
      expect(kept.length, 1);
      expect(kept.single.bank, 'HDFC'); // bank row preferred over wallet
    });

    test('same-source same-amount distinct purchases are both kept', () {
      final kept = store.debugDropCrossSourceDuplicates(
        [
          hit(id: 'a', bank: 'HDFC', mask: '••••4321'),
          hit(
            id: 'b',
            bank: 'HDFC',
            mask: '••••4321',
            offset: const Duration(minutes: 1),
          ),
        ],
        const [],
      );
      expect(kept.length, 2);
    });

    test('wallet mirror of an already-stored bank row is dropped', () {
      final existing = [hit(id: 'bank', bank: 'HDFC', mask: '••••4321')];
      final kept = store.debugDropCrossSourceDuplicates(
        [hit(id: 'wallet', bank: 'Paytm', offset: const Duration(seconds: 20))],
        existing,
      );
      expect(kept, isEmpty);
    });
  });
}
