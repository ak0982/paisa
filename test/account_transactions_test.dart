import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/models/bank_account.dart';
import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/models/transaction.dart';
import 'package:paisa_app/providers/finance_store.dart';
import 'package:paisa_app/services/sms/account_discovery.dart';
import 'package:paisa_app/services/sms/transaction_enrichment.dart';

void main() {
  group('transactionsForAccount', () {
    test('same mask at two banks stays split and matches account totals', () {
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
          Transaction(
            id: '3',
            smsId: '3',
            merchant: 'Uber',
            bank: 'HDFC',
            maskedAccount: '••••1234',
            category: SpendCategory.travel,
            amount: 150,
            isCredit: false,
            timestamp: DateTime(2026, 7, 11),
            accountKind: AccountKind.savings,
          ),
        ]);

      final accounts = store.bankAccounts();
      final hdfc = accounts.firstWhere((a) => a.bank == 'HDFC');
      final sbi = accounts.firstWhere((a) => a.bank == 'SBI');

      final hdfcTxns = store.transactionsForAccount(
        evidenceKey: hdfc.evidenceKey,
      );
      final sbiTxns = store.transactionsForAccount(
        evidenceKey: sbi.evidenceKey,
      );

      expect(hdfcTxns.map((t) => t.id).toSet(), {'1', '3'});
      expect(sbiTxns.map((t) => t.id).toSet(), {'2'});
      _expectParity(hdfc, hdfcTxns);
      _expectParity(sbi, sbiTxns);
    });

    test('maskless same-bank attaches when unique savings account', () {
      final store = FinanceStore()
        ..seedTransactions([
          Transaction(
            id: 'masked',
            smsId: 'masked',
            merchant: 'Amazon',
            bank: 'HDFC',
            maskedAccount: '••••9999',
            category: SpendCategory.shopping,
            amount: 500,
            isCredit: false,
            timestamp: DateTime(2026, 7, 3),
            accountKind: AccountKind.savings,
          ),
          Transaction(
            id: 'orphan',
            smsId: 'orphan',
            merchant: 'Swiggy',
            bank: 'HDFC',
            maskedAccount: '',
            category: SpendCategory.food,
            amount: 220,
            isCredit: false,
            timestamp: DateTime(2026, 7, 4),
            accountKind: AccountKind.savings,
          ),
        ]);

      final hdfc = store.bankAccounts().firstWhere((a) => a.bank == 'HDFC');
      final txns = store.transactionsForAccount(evidenceKey: hdfc.evidenceKey);
      expect(txns.map((t) => t.id).toSet(), {'masked', 'orphan'});
      _expectParity(hdfc, txns);
    });

    test('maskless does not attach when two savings masks at same bank', () {
      final store = FinanceStore()
        ..seedTransactions([
          Transaction(
            id: 'a',
            smsId: 'a',
            merchant: 'A',
            bank: 'HDFC',
            maskedAccount: '••••1111',
            category: SpendCategory.food,
            amount: 10,
            isCredit: false,
            timestamp: DateTime(2026, 7, 1),
            accountKind: AccountKind.savings,
          ),
          Transaction(
            id: 'b',
            smsId: 'b',
            merchant: 'B',
            bank: 'HDFC',
            maskedAccount: '••••2222',
            category: SpendCategory.food,
            amount: 20,
            isCredit: false,
            timestamp: DateTime(2026, 7, 2),
            accountKind: AccountKind.savings,
          ),
          Transaction(
            id: 'orphan',
            smsId: 'orphan',
            merchant: 'C',
            bank: 'HDFC',
            maskedAccount: '',
            category: SpendCategory.food,
            amount: 30,
            isCredit: false,
            timestamp: DateTime(2026, 7, 3),
            accountKind: AccountKind.savings,
          ),
        ]);

      final accounts = store.bankAccounts().where((a) => a.bank == 'HDFC');
      for (final a in accounts) {
        final ids = store
            .transactionsForAccount(evidenceKey: a.evidenceKey)
            .map((t) => t.id)
            .toSet();
        expect(ids.contains('orphan'), isFalse);
        _expectParity(a, store.transactionsForAccount(evidenceKey: a.evidenceKey));
      }
    });

    test('BOB alias merges into Bank of Baroda bucket', () {
      final store = FinanceStore()
        ..seedTransactions([
          Transaction(
            id: '1',
            smsId: '1',
            merchant: 'Shop',
            bank: 'BOB',
            maskedAccount: '••••5555',
            category: SpendCategory.shopping,
            amount: 100,
            isCredit: false,
            timestamp: DateTime(2026, 7, 1),
            accountKind: AccountKind.savings,
          ),
          Transaction(
            id: '2',
            smsId: '2',
            merchant: 'Salary',
            bank: 'Bank of Baroda',
            maskedAccount: '••••5555',
            category: SpendCategory.income,
            amount: 1000,
            isCredit: true,
            timestamp: DateTime(2026, 7, 2),
            accountKind: AccountKind.savings,
          ),
        ]);

      final accounts = store.bankAccounts()
          .where((a) => a.mask == '••••5555')
          .toList();
      expect(accounts.length, 1);
      expect(accounts.first.bank, 'Bank of Baroda');
      final txns = store.transactionsForAccount(
        evidenceKey: accounts.first.evidenceKey,
      );
      expect(txns.map((t) => t.id).toSet(), {'1', '2'});
      _expectParity(accounts.first, txns);
    });

    test('CCBP funding debit stays on savings account', () {
      final store = FinanceStore()
        ..seedTransactions([
          Transaction(
            id: 'pay',
            smsId: 'pay',
            merchant: 'Credit card bill payment',
            bank: 'SBI',
            maskedAccount: '••••0429',
            category: SpendCategory.bills,
            amount: 12000,
            isCredit: false,
            timestamp: DateTime(2026, 7, 1),
            accountKind: AccountKind.creditCard,
          ),
          Transaction(
            id: 'upi',
            smsId: 'upi',
            merchant: 'Swiggy',
            bank: 'SBI',
            maskedAccount: '••••0429',
            category: SpendCategory.food,
            amount: 300,
            isCredit: false,
            timestamp: DateTime(2026, 7, 2),
            accountKind: AccountKind.savings,
          ),
        ]);

      final savings = store.bankAccounts().firstWhere(
        (a) => a.bank == 'SBI' && a.mask == '••••0429',
      );
      expect(savings.kind, AccountKind.savings);

      final txns = store.transactionsForAccount(
        evidenceKey: savings.evidenceKey,
      );
      expect(txns.map((t) => t.id).toSet(), {'pay', 'upi'});
      _expectParity(savings, txns);
    });

    test('CC discovery does not inflate ledger activityCount', () {
      final store = FinanceStore()
        ..seedTransactions([
          Transaction(
            id: 'cc1',
            smsId: 'cc1',
            merchant: 'Flipkart',
            bank: 'HDFC',
            maskedAccount: '••••8888',
            category: SpendCategory.shopping,
            amount: 900,
            isCredit: false,
            timestamp: DateTime(2026, 7, 1),
            accountKind: AccountKind.creditCard,
          ),
        ])
        ..seedDiscoveredAccounts([
          DiscoveredAccount(
            bank: 'HDFC',
            mask: '••••8888',
            kind: AccountKind.creditCard,
            smsHits: 5,
            spentTotal: 5000,
            receivedTotal: 0,
          ),
        ]);

      final card = store.bankAccounts().firstWhere(
        (a) => a.mask == '••••8888' && a.isCreditCard,
      );
      expect(card.activityCount, 1);
      expect(card.spentTotal, 900);
      final txns = store.transactionsForAccount(evidenceKey: card.evidenceKey);
      expect(txns.length, 1);
      _expectParity(card, txns);
    });

    test('empty mask query returns empty; wallets excluded', () {
      final store = FinanceStore()
        ..seedTransactions([
          Transaction(
            id: 'ok',
            smsId: 'ok',
            merchant: 'Amazon',
            bank: 'HDFC',
            maskedAccount: '••••9999',
            category: SpendCategory.shopping,
            amount: 500,
            isCredit: false,
            timestamp: DateTime(2026, 7, 3),
            accountKind: AccountKind.savings,
          ),
          Transaction(
            id: 'wallet',
            smsId: 'wallet',
            merchant: 'Recharge',
            bank: 'Paytm',
            maskedAccount: '••••1111',
            category: SpendCategory.bills,
            amount: 100,
            isCredit: false,
            timestamp: DateTime(2026, 7, 5),
            accountKind: AccountKind.savings,
          ),
        ]);

      expect(store.transactionsForAccount(bank: 'HDFC', mask: ''), isEmpty);
      expect(
        store.transactionsForAccount(bank: 'Paytm', mask: '••••1111'),
        isEmpty,
      );
    });

    test('accountEvidenceKey canonicalizes BOB', () {
      expect(
        FinanceStore.accountEvidenceKey('BOB', '••••1234'),
        FinanceStore.accountEvidenceKey('Bank of Baroda', '••••1234'),
      );
    });
  });

  group('resolveCreditCardDisplay CCBP', () {
    test('does not remap CCBP onto discovered card', () {
      final result = TransactionEnrichment.resolveCreditCardDisplay(
        body: 'A/c X0429 debited by 500 for MBK CCBP toward HDFC card',
        parsedBank: 'SBI',
        parsedMask: '••••0429',
        discoveries: [
          DiscoveredAccount(
            bank: 'HDFC',
            mask: '••••9999',
            kind: AccountKind.creditCard,
            smsHits: 3,
          ),
        ],
      );
      // Body has funding last4 0429 — stays on funding identity.
      expect(result.mask, '••••0429');
      expect(result.bank, 'SBI');
    });

    test('CCBP without last4 keeps parsed funding bank/mask', () {
      final result = TransactionEnrichment.resolveCreditCardDisplay(
        body: 'UPI payment for CCBP of Rs 1000 is successful',
        parsedBank: 'SBI',
        parsedMask: '••••0429',
        discoveries: [
          DiscoveredAccount(
            bank: 'HDFC',
            mask: '••••9999',
            kind: AccountKind.creditCard,
            smsHits: 3,
          ),
        ],
      );
      expect(result.bank, 'SBI');
      expect(result.mask, '••••0429');
    });
  });
}

void _expectParity(BankAccount account, List<Transaction> txns) {
  final received =
      txns.where((t) => t.isCredit).fold(0.0, (s, t) => s + t.amount);
  final sent =
      txns.where((t) => !t.isCredit).fold(0.0, (s, t) => s + t.amount);
  expect(txns.length, account.activityCount);
  expect(received, account.receivedTotal);
  expect(sent, account.spentTotal);
}
