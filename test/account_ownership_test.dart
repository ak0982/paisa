import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/models/transaction.dart';
import 'package:paisa_app/providers/finance_store.dart';
import 'package:paisa_app/services/sms/account_bank_registry.dart';
import 'package:paisa_app/services/sms/account_discovery.dart';
import 'package:paisa_app/services/sms/transaction_enrichment.dart';

void main() {
  group('AccountBankRegistry ownership', () {
    test('learns Slice from SLCEIT sender; skips ICICI settlement learn', () {
      final registry = AccountBankRegistry();
      registry.learn(
        'AX-SLCEIT-S',
        'Rs. 100 sent from a/c xx0856 on 01-Jan-26 to X (UPI Ref: 1) - slice',
      );
      registry.learn(
        'VM-ICICI-S',
        'Account XXXXXXXX0856 has been credited with amount Rs.5000.00. '
            'Info: LENDENCLUB BORROWER REPAYMENT.',
      );

      expect(registry.lookup('0856'), 'Slice');
    });

    test('resolveBank maps ICICI settlement to known Slice owner', () {
      final registry = AccountBankRegistry()
        ..seedVotes({
          '0856': {'Slice': 10},
        });

      final bank = registry.resolveBank(
        sender: 'VM-ICICI-S',
        body:
            'Account XXXXXXXX0856 has been credited with amount Rs.5000.00. '
            'Info: LENDENCLUB BORROWER REPAYMENT.',
        accountLast4: '0856',
        parsedBank: 'Bank',
      );
      expect(bank, 'Slice');
    });

    test('explicit - slice body wins', () {
      expect(
        AccountBankRegistry.detectExplicitAccountBank(
          'Rs. 10 received in a/c XXX856 from X on 01-Jan-26 - slice',
        ),
        'Slice',
      );
    });
  });

  group('You bucket rematch', () {
    test('Bank + Slice same last-4 fold into Slice account list', () {
      final store = FinanceStore()
        ..seedDiscoveredAccounts([
          const DiscoveredAccount(
            bank: 'Slice',
            mask: '••••0856',
            kind: AccountKind.savings,
            smsHits: 20,
          ),
        ])
        ..seedTransactions([
          Transaction(
            id: 'slice1',
            smsId: 'slice1',
            merchant: 'Crew',
            bank: 'Slice',
            maskedAccount: '••••0856',
            category: SpendCategory.food,
            amount: 550,
            isCredit: false,
            timestamp: DateTime(2026, 5, 18),
            accountKind: AccountKind.savings,
          ),
          Transaction(
            id: 'relay1',
            smsId: 'relay1',
            merchant: 'Lendenclub Borrower Repayment',
            bank: 'Bank',
            maskedAccount: '••••0856',
            category: SpendCategory.income,
            amount: 5000,
            isCredit: true,
            timestamp: DateTime(2026, 5, 19),
            accountKind: AccountKind.savings,
          ),
          Transaction(
            id: 'relay2',
            smsId: 'relay2',
            merchant: 'Lendenclub Borrower Repayment',
            bank: 'ICICI',
            maskedAccount: '••••0856',
            category: SpendCategory.income,
            amount: 3000,
            isCredit: true,
            timestamp: DateTime(2026, 5, 20),
            accountKind: AccountKind.savings,
          ),
        ]);

      final accounts = store.bankAccounts().where((a) => a.mask == '••••0856');
      expect(accounts.length, 1);
      expect(accounts.first.bank, 'Slice');

      final txns = store.transactionsForAccount(
        evidenceKey: accounts.first.evidenceKey,
      );
      expect(txns.map((t) => t.id).toSet(), {'slice1', 'relay1', 'relay2'});
      expect(accounts.first.activityCount, 3);
      expect(accounts.first.receivedTotal, 8000);
      expect(accounts.first.spentTotal, 550);
    });

    test('two real banks same last-4 stay split', () {
      final store = FinanceStore()
        ..seedTransactions([
          Transaction(
            id: '1',
            smsId: '1',
            merchant: 'A',
            bank: 'HDFC',
            maskedAccount: '••••1234',
            category: SpendCategory.food,
            amount: 10,
            isCredit: false,
            timestamp: DateTime(2026, 7, 1),
            accountKind: AccountKind.savings,
          ),
          Transaction(
            id: '2',
            smsId: '2',
            merchant: 'B',
            bank: 'SBI',
            maskedAccount: '••••1234',
            category: SpendCategory.income,
            amount: 20,
            isCredit: true,
            timestamp: DateTime(2026, 7, 2),
            accountKind: AccountKind.savings,
          ),
        ]);

      final matching =
          store.bankAccounts().where((a) => a.mask == '••••1234').toList();
      expect(matching.length, 2);
    });
  });

  group('CCBP funding', () {
    test('CCBP with last4 does not remap onto discovered card', () {
      final result = TransactionEnrichment.resolveCreditCardDisplay(
        body: 'A/c X0429 debited by 500 for MBK CCBP toward card xx9999',
        parsedBank: 'SBI',
        parsedMask: '••••0429',
        discoveries: [
          const DiscoveredAccount(
            bank: 'HDFC',
            mask: '••••9999',
            kind: AccountKind.creditCard,
            smsHits: 3,
          ),
          const DiscoveredAccount(
            bank: 'SBI',
            mask: '••••0429',
            kind: AccountKind.savings,
            smsHits: 5,
          ),
        ],
      );
      expect(result.bank, 'SBI');
      expect(result.mask, '••••0429');
    });
  });
}
