import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/models/transaction.dart';
import 'package:paisa_app/providers/finance_store.dart';
import 'package:paisa_app/services/sms/account_discovery.dart';

Transaction _txn({
  required String id,
  required String bank,
  required String mask,
  required double amount,
  bool isCredit = false,
  AccountKind kind = AccountKind.savings,
  SpendCategory category = SpendCategory.food,
  DateTime? at,
}) {
  return Transaction(
    id: id,
    smsId: id,
    merchant: id,
    bank: bank,
    maskedAccount: mask,
    category: category,
    amount: amount,
    isCredit: isCredit,
    timestamp: at ?? DateTime(2026, 7, 1),
    accountKind: kind,
  );
}

void main() {
  group('ledger bucket cache', () {
    test('bankAccounts and transactionsForAccount reuse until seed', () {
      final store = FinanceStore()
        ..seedTransactions([
          _txn(id: 'h1', bank: 'HDFC', mask: '••••5300', amount: 200),
          _txn(
            id: 's1',
            bank: 'SBI',
            mask: '••••0429',
            amount: 5000,
            isCredit: true,
            category: SpendCategory.income,
          ),
        ]);

      final first = store.bankAccounts();
      final second = store.bankAccounts();
      expect(identical(first, second), isTrue);
      expect(first.map((a) => a.mask).toSet(), {'••••5300', '••••0429'});

      final hdfc = first.firstWhere((a) => a.bank == 'HDFC');
      final listed = store.transactionsForAccount(evidenceKey: hdfc.evidenceKey);
      expect(listed.map((t) => t.id), ['h1']);
      expect(
        store.transactionsForAccount(evidenceKey: hdfc.evidenceKey).map((t) => t.id),
        listed.map((t) => t.id),
      );

      store.seedTransactions([
        _txn(id: 'h1', bank: 'HDFC', mask: '••••5300', amount: 200),
        _txn(id: 'h2', bank: 'HDFC', mask: '••••5300', amount: 50),
        _txn(
          id: 's1',
          bank: 'SBI',
          mask: '••••0429',
          amount: 5000,
          isCredit: true,
          category: SpendCategory.income,
        ),
      ]);
      final afterSeed = store.bankAccounts();
      expect(identical(first, afterSeed), isFalse);
      final hdfcAfter =
          afterSeed.firstWhere((a) => a.bank == 'HDFC');
      expect(
        store
            .transactionsForAccount(evidenceKey: hdfcAfter.evidenceKey)
            .map((t) => t.id)
            .toSet(),
        {'h1', 'h2'},
      );
    });

    test('hiddenMasks is part of the cache key and does not leak', () {
      final store = FinanceStore()
        ..seedTransactions([
          _txn(id: 'h1', bank: 'HDFC', mask: '••••5300', amount: 200),
          _txn(id: 'k1', bank: 'Kotak', mask: '••••3649', amount: 80),
        ]);

      final all = store.bankAccounts();
      expect(all.map((a) => a.mask).toSet(), {'••••5300', '••••3649'});
      expect(identical(store.bankAccounts(), all), isTrue);

      const hidden = {'••••5300'};
      final filtered = store.bankAccounts(hiddenMasks: hidden);
      expect(filtered.map((a) => a.mask).toSet(), {'••••3649'});
      expect(
        identical(store.bankAccounts(hiddenMasks: hidden), filtered),
        isTrue,
      );

      final unhidden = store.bankAccounts();
      expect(unhidden.map((a) => a.mask).toSet(), {'••••5300', '••••3649'});
    });

    test('seeded discoveries invalidate linked EMI buckets', () {
      final store = FinanceStore()
        ..seedTransactions([
          _txn(
            id: 'emi',
            bank: 'Kotak',
            mask: '••••3649',
            amount: 8500,
            kind: AccountKind.loan,
            category: SpendCategory.emi,
          ),
        ]);

      final before = store.bankAccounts();
      expect(
        store
            .transactionsForAccount(
              evidenceKey: before.firstWhere((a) => a.mask == '••••3649').evidenceKey,
            )
            .map((t) => t.id),
        ['emi'],
      );

      store.seedDiscoveredAccounts([
        const DiscoveredAccount(
          bank: 'HDFC',
          mask: '••••0855',
          kind: AccountKind.loan,
          smsHits: 5,
          accountLabel: 'Home Loan',
        ),
      ]);

      final after = store.bankAccounts();
      expect(identical(before, after), isFalse);
      final loan = after.firstWhere((a) => a.isLoan && a.mask == '••••0855');
      expect(
        store.transactionsForAccount(evidenceKey: loan.evidenceKey).map((t) => t.id),
        ['emi'],
      );
    });
  });
}
