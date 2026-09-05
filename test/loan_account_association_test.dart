import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/models/transaction.dart';
import 'package:paisa_app/providers/finance_store.dart';
import 'package:paisa_app/services/sms/account_discovery.dart';
import 'package:paisa_app/services/sms/transaction_enrichment.dart';

void main() {
  group('loan discovery', () {
    test('Personal Loan XX1041 wins over linked savings Account XX3649', () {
      final d = AccountDiscovery.discover(
        sender: 'VK-ICICI-S',
        body:
            'EMI of Rs.12,345.00 for ICICI Bank Personal Loan XX1041 is due. '
            'Linked Account XX3649. -ICICI Bank',
      );
      expect(d, isNotNull);
      expect(d!.kind, AccountKind.loan);
      expect(d.mask, '••••1041');
      expect(d.bank, 'ICICI');
    });

    test('Loan Ac XX0310 discovers as loan', () {
      final d = AccountDiscovery.discover(
        sender: 'AX-PNBSMS-S',
        body:
            'Thanks for depositing an amount Rs 5000 against Loan Ac XX0310. -PNB',
      );
      expect(d, isNotNull);
      expect(d!.kind, AccountKind.loan);
      expect(d.mask, '••••0310');
    });
  });

  group('resolveLoanDisplay keeps funding identity', () {
    test('NACH-HDFC keeps Kotak funding bank|mask', () {
      final result = TransactionEnrichment.resolveLoanDisplay(
        body: 'Rs.8500 debited from A/c XX3649 towards NACH-10-HDFC BANK LIMITED',
        parsedBank: 'Kotak',
        parsedMask: '••••3649',
        discoveries: [
          const DiscoveredAccount(
            bank: 'HDFC',
            mask: '••••0855',
            kind: AccountKind.loan,
            smsHits: 3,
            accountLabel: 'Home Loan',
          ),
        ],
      );
      expect(result.bank, 'Kotak');
      expect(result.mask, '••••3649');
    });

    test('NACH without loan discovery keeps funding identity', () {
      final result = TransactionEnrichment.resolveLoanDisplay(
        body: 'Rs.8500 debited from A/c XX3649 towards NACH-10-TP ACH ICICI',
        parsedBank: 'Kotak',
        parsedMask: '••••3649',
        discoveries: const [],
      );
      expect(result.bank, 'Kotak');
      expect(result.mask, '••••3649');
    });

    test('MBK EMI keeps funding identity even with unique loan', () {
      final result = TransactionEnrichment.resolveLoanDisplay(
        body: 'UPI payment of Rs 2000 from a/c XX5300 to MBK EMI is successful',
        parsedBank: 'HDFC',
        parsedMask: '••••5300',
        discoveries: [
          const DiscoveredAccount(
            bank: 'PNB',
            mask: '••••0310',
            kind: AccountKind.loan,
            smsHits: 4,
          ),
        ],
      );
      expect(result.bank, 'HDFC');
      expect(result.mask, '••••5300');
    });

    test('MBK EMI with multiple loans keeps funding identity (no bank guess)', () {
      final result = TransactionEnrichment.resolveLoanDisplay(
        body:
            'Sent Rs.5199.39\nFrom HDFC Bank A/C *5300\nTo MBK EMI\nOn 27/02/26',
        parsedBank: 'HDFC',
        parsedMask: '••••5300',
        discoveries: const [
          DiscoveredAccount(
            bank: 'HDFC',
            mask: '••••0855',
            kind: AccountKind.loan,
            smsHits: 5,
            accountLabel: 'Home Loan',
          ),
          DiscoveredAccount(
            bank: 'ICICI',
            mask: '••••1041',
            kind: AccountKind.loan,
            smsHits: 5,
            accountLabel: 'Personal Loan',
          ),
          DiscoveredAccount(
            bank: 'PNB',
            mask: '••••0310',
            kind: AccountKind.loan,
            smsHits: 4,
          ),
        ],
      );
      expect(result.bank, 'HDFC');
      expect(result.mask, '••••5300');
    });

    test('PNB loan deposit body last-4 keeps PNB funding identity', () {
      final result = TransactionEnrichment.resolveLoanDisplay(
        body:
            'Thanks for depositing an amount of Rs. 5199.39 against your '
            'Loan Ac XX0310. Register for e-statement,if not done.-PNB',
        parsedBank: 'PNB',
        parsedMask: '••••0310',
        discoveries: const [
          DiscoveredAccount(
            bank: 'HDFC',
            mask: '••••0855',
            kind: AccountKind.loan,
            smsHits: 5,
          ),
          DiscoveredAccount(
            bank: 'PNB',
            mask: '••••0310',
            kind: AccountKind.loan,
            smsHits: 4,
          ),
        ],
      );
      expect(result.bank, 'PNB');
      expect(result.mask, '••••0310');
    });

    test('NACH HDFC never remaps onto loan mask (unique or multi)', () {
      final multiAtHdfc = TransactionEnrichment.resolveLoanDisplay(
        body:
            'INR 25,797.00 is debited from your Account XXXXXX3649 on '
            '07/03/2026 towards NACH-10-HDFC BANK LIMITED Kotak Bank',
        parsedBank: 'Kotak',
        parsedMask: '••••3649',
        discoveries: const [
          DiscoveredAccount(
            bank: 'HDFC',
            mask: '••••0855',
            kind: AccountKind.loan,
            smsHits: 5,
          ),
          DiscoveredAccount(
            bank: 'HDFC',
            mask: '••••0999',
            kind: AccountKind.loan,
            smsHits: 2,
          ),
        ],
      );
      expect(multiAtHdfc.bank, 'Kotak');
      expect(multiAtHdfc.mask, '••••3649');

      final unique = TransactionEnrichment.resolveLoanDisplay(
        body:
            'INR 25,797.00 is debited from your Account XXXXXX3649 on '
            '07/03/2026 towards NACH-10-HDFC BANK LIMITED Kotak Bank',
        parsedBank: 'Kotak',
        parsedMask: '••••3649',
        discoveries: const [
          DiscoveredAccount(
            bank: 'HDFC',
            mask: '••••0855',
            kind: AccountKind.loan,
            smsHits: 5,
          ),
          DiscoveredAccount(
            bank: 'ICICI',
            mask: '••••1041',
            kind: AccountKind.loan,
            smsHits: 5,
          ),
        ],
      );
      expect(unique.bank, 'Kotak');
      expect(unique.mask, '••••3649');
    });

    test('UPI destination last-4 keeps funding identity', () {
      final result = TransactionEnrichment.resolveLoanDisplay(
        body:
            'HDFC Bank:Rs. 5200.00 debited from a/c *5300 on 21/12/25 to '
            'a/c **0310 (UPI Ref No. 874150616776).',
        parsedBank: 'HDFC',
        parsedMask: '••••5300',
        discoveries: const [
          DiscoveredAccount(
            bank: 'HDFC',
            mask: '••••0855',
            kind: AccountKind.loan,
            smsHits: 5,
          ),
          DiscoveredAccount(
            bank: 'PNB',
            mask: '••••0310',
            kind: AccountKind.loan,
            smsHits: 4,
          ),
        ],
      );
      expect(result.bank, 'HDFC');
      expect(result.mask, '••••5300');
    });
  });

  group('resolveAssociatedLoanProduct', () {
    test('NACH-HDFC associates unique HDFC loan without rewriting display', () {
      const discoveries = [
        DiscoveredAccount(
          bank: 'HDFC',
          mask: '••••0855',
          kind: AccountKind.loan,
          smsHits: 5,
          accountLabel: 'Home Loan',
        ),
        DiscoveredAccount(
          bank: 'ICICI',
          mask: '••••1041',
          kind: AccountKind.loan,
          smsHits: 5,
        ),
      ];
      const body =
          'INR 25,797.00 is debited from your Account XXXXXX3649 on '
          '07/03/2026 towards NACH-10-HDFC BANK LIMITED Kotak Bank';
      final linked = TransactionEnrichment.resolveAssociatedLoanProduct(
        body: body,
        discoveries: discoveries,
      );
      expect(linked?.bank, 'HDFC');
      expect(linked?.mask, '••••0855');
      final display = TransactionEnrichment.resolveLoanDisplay(
        body: body,
        parsedBank: 'Kotak',
        parsedMask: '••••3649',
        discoveries: discoveries,
      );
      expect(display.bank, 'Kotak');
      expect(display.mask, '••••3649');
    });

    test('NACH-ICICI associates unique ICICI loan', () {
      final linked = TransactionEnrichment.resolveAssociatedLoanProduct(
        body:
            'INR 12,345.00 is debited from your Account XXXXXX3649 towards '
            'NACH-10-TP ACH ICICI Kotak Bank',
        discoveries: const [
          DiscoveredAccount(
            bank: 'HDFC',
            mask: '••••0855',
            kind: AccountKind.loan,
            smsHits: 5,
          ),
          DiscoveredAccount(
            bank: 'ICICI',
            mask: '••••1041',
            kind: AccountKind.loan,
            smsHits: 5,
          ),
        ],
      );
      expect(linked?.bank, 'ICICI');
      expect(linked?.mask, '••••1041');
    });
  });

  group('loan account drilldown', () {
    test('multi-loan: MBK EMI stays off wrong loan; PNB deposit on PNB', () {
      final store = FinanceStore()
        ..seedDiscoveredAccounts([
          const DiscoveredAccount(
            bank: 'HDFC',
            mask: '••••0855',
            kind: AccountKind.loan,
            smsHits: 5,
            accountLabel: 'Home Loan',
          ),
          const DiscoveredAccount(
            bank: 'ICICI',
            mask: '••••1041',
            kind: AccountKind.loan,
            smsHits: 5,
            accountLabel: 'Personal Loan',
          ),
          const DiscoveredAccount(
            bank: 'PNB',
            mask: '••••0310',
            kind: AccountKind.loan,
            smsHits: 4,
          ),
          const DiscoveredAccount(
            bank: 'HDFC',
            mask: '••••5300',
            kind: AccountKind.savings,
            smsHits: 20,
          ),
        ])
        ..seedTransactions([
          Transaction(
            id: 'mbk5199',
            smsId: 'mbk5199',
            merchant: 'MBK EMI',
            bank: 'HDFC',
            maskedAccount: '••••5300',
            category: SpendCategory.emi,
            amount: 5199.39,
            isCredit: false,
            timestamp: DateTime(2026, 2, 27),
            accountKind: AccountKind.loan,
          ),
          Transaction(
            id: 'pnb5199',
            smsId: 'pnb5199',
            merchant: 'Loan payment',
            bank: 'PNB',
            maskedAccount: '••••0310',
            category: SpendCategory.emi,
            amount: 5199.39,
            isCredit: false,
            timestamp: DateTime(2026, 2, 27, 0, 5),
            accountKind: AccountKind.loan,
          ),
          Transaction(
            id: 'hdfc-emi',
            smsId: 'hdfc-emi',
            merchant: 'NACH debit',
            bank: 'HDFC',
            maskedAccount: '••••0855',
            category: SpendCategory.emi,
            amount: 25797,
            isCredit: false,
            timestamp: DateTime(2026, 3, 7),
            accountKind: AccountKind.loan,
          ),
        ]);

      final hdfcLoan =
          store.bankAccounts().firstWhere((a) => a.mask == '••••0855');
      final pnbLoan =
          store.bankAccounts().firstWhere((a) => a.mask == '••••0310');
      final hdfcTx =
          store.transactionsForAccount(evidenceKey: hdfcLoan.evidenceKey);
      final pnbTx =
          store.transactionsForAccount(evidenceKey: pnbLoan.evidenceKey);

      expect(hdfcTx.map((t) => t.id).toSet(), {'hdfc-emi'});
      expect(hdfcTx.any((t) => t.amount == 5199.39), isFalse);
      expect(pnbTx.map((t) => t.id).toSet(), {'pnb5199'});
      expect(pnbTx.where((t) => t.amount == 5199.39).length, 1);
      expect(pnbLoan.spentTotal, 5199.39);
      expect(pnbLoan.activityCount, 1);

      final hdfcSavings =
          store.bankAccounts().firstWhere((a) => a.mask == '••••5300');
      final savingsTx =
          store.transactionsForAccount(evidenceKey: hdfcSavings.evidenceKey);
      expect(savingsTx.map((t) => t.id).toSet(), {'mbk5199'});
    });

    test('multi-loan: MBK pairs only when product deposit anchors amount', () {
      final store = FinanceStore()
        ..seedDiscoveredAccounts([
          const DiscoveredAccount(
            bank: 'HDFC',
            mask: '••••0855',
            kind: AccountKind.loan,
            smsHits: 5,
          ),
          const DiscoveredAccount(
            bank: 'PNB',
            mask: '••••0310',
            kind: AccountKind.loan,
            smsHits: 4,
          ),
          const DiscoveredAccount(
            bank: 'HDFC',
            mask: '••••5300',
            kind: AccountKind.savings,
            smsHits: 20,
          ),
        ])
        ..seedTransactions([
          Transaction(
            id: 'mbk-orphan',
            merchant: 'MBK EMI',
            bank: 'HDFC',
            maskedAccount: '••••5300',
            category: SpendCategory.emi,
            amount: 1111.11,
            isCredit: false,
            timestamp: DateTime(2026, 2, 27),
            accountKind: AccountKind.loan,
          ),
          Transaction(
            id: 'pnb-other',
            merchant: 'Loan payment',
            bank: 'PNB',
            maskedAccount: '••••0310',
            category: SpendCategory.emi,
            amount: 5199.39,
            isCredit: false,
            timestamp: DateTime(2026, 2, 27),
            accountKind: AccountKind.loan,
          ),
        ]);

      final pnbLoan =
          store.bankAccounts().firstWhere((a) => a.mask == '••••0310');
      final pnbTx =
          store.transactionsForAccount(evidenceKey: pnbLoan.evidenceKey);
      expect(pnbTx.map((t) => t.id).toSet(), {'pnb-other'});
      expect(pnbTx.any((t) => t.id == 'mbk-orphan'), isFalse);
    });

    test('EMI on funding mask stays under Kotak, not under unique loan', () {
      final store = FinanceStore()
        ..seedDiscoveredAccounts([
          const DiscoveredAccount(
            bank: 'HDFC',
            mask: '••••0855',
            kind: AccountKind.loan,
            smsHits: 5,
            accountLabel: 'Home Loan',
          ),
          const DiscoveredAccount(
            bank: 'Kotak',
            mask: '••••3649',
            kind: AccountKind.savings,
            smsHits: 20,
          ),
        ])
        ..seedTransactions([
          Transaction(
            id: 'emi1',
            smsId: 'emi1',
            merchant: 'Home Loan EMI',
            bank: 'Kotak',
            maskedAccount: '••••3649',
            category: SpendCategory.emi,
            amount: 8500,
            isCredit: false,
            timestamp: DateTime(2026, 6, 1),
            accountKind: AccountKind.loan,
          ),
          Transaction(
            id: 'emi2',
            smsId: 'emi2',
            merchant: 'Home Loan EMI',
            bank: 'Kotak',
            maskedAccount: '••••3649',
            category: SpendCategory.emi,
            amount: 8500,
            isCredit: false,
            timestamp: DateTime(2026, 7, 1),
            accountKind: AccountKind.loan,
          ),
          Transaction(
            id: 'loan-credit',
            smsId: 'loan-credit',
            merchant: 'Loan disbursal',
            bank: 'HDFC',
            maskedAccount: '••••0855',
            category: SpendCategory.income,
            amount: 100000,
            isCredit: true,
            timestamp: DateTime(2026, 1, 1),
            accountKind: AccountKind.loan,
          ),
        ]);

      final loan = store.bankAccounts().firstWhere((a) => a.isLoan);
      expect(loan.mask, '••••0855');
      final loanTxns =
          store.transactionsForAccount(evidenceKey: loan.evidenceKey);
      expect(loanTxns.map((t) => t.id).toSet(), {'loan-credit'});
      expect(loan.spentTotal, 0);

      final kotak = store.bankAccounts().firstWhere((a) => a.mask == '••••3649');
      expect(kotak.kind, AccountKind.savings);
      final kotakTxns =
          store.transactionsForAccount(evidenceKey: kotak.evidenceKey);
      expect(kotakTxns.map((t) => t.id).toSet(), {'emi1', 'emi2'});
      expect(kotak.spentTotal, 17000);
    });

    test(
      'Kotak-funded HDFC+ICICI EMI stays under Kotak, not loan banks',
      () {
        final store = FinanceStore()
          ..seedDiscoveredAccounts([
            const DiscoveredAccount(
              bank: 'HDFC',
              mask: '••••0855',
              kind: AccountKind.loan,
              smsHits: 5,
              accountLabel: 'Home Loan',
            ),
            const DiscoveredAccount(
              bank: 'ICICI',
              mask: '••••1041',
              kind: AccountKind.loan,
              smsHits: 5,
              accountLabel: 'Personal Loan',
            ),
            const DiscoveredAccount(
              bank: 'Kotak',
              mask: '••••3649',
              kind: AccountKind.savings,
              smsHits: 30,
            ),
          ])
          ..seedTransactions([
            Transaction(
              id: 'kotak-hdfc-emi',
              smsId: 'kotak-hdfc-emi',
              merchant: 'NACH-10-HDFC BANK LIMITED',
              bank: 'Kotak',
              maskedAccount: '••••3649',
              category: SpendCategory.emi,
              amount: 25797,
              isCredit: false,
              timestamp: DateTime(2026, 3, 7),
              accountKind: AccountKind.loan,
            ),
            Transaction(
              id: 'kotak-icici-emi',
              smsId: 'kotak-icici-emi',
              merchant: 'NACH-10-TP ACH ICICI',
              bank: 'Kotak',
              maskedAccount: '••••3649',
              category: SpendCategory.emi,
              amount: 12345,
              isCredit: false,
              timestamp: DateTime(2026, 3, 8),
              accountKind: AccountKind.loan,
            ),
            Transaction(
              id: 'kotak-food',
              smsId: 'kotak-food',
              merchant: 'Swiggy',
              bank: 'Kotak',
              maskedAccount: '••••3649',
              category: SpendCategory.food,
              amount: 400,
              isCredit: false,
              timestamp: DateTime(2026, 3, 9),
              accountKind: AccountKind.savings,
            ),
          ]);

        final kotak =
            store.bankAccounts().firstWhere((a) => a.mask == '••••3649');
        expect(kotak.kind, AccountKind.savings);
        final kotakTx =
            store.transactionsForAccount(evidenceKey: kotak.evidenceKey);
        expect(
          kotakTx.map((t) => t.id).toSet(),
          {'kotak-hdfc-emi', 'kotak-icici-emi', 'kotak-food'},
        );
        expect(kotak.spentTotal, 25797 + 12345 + 400);

        final hdfcLoan =
            store.bankAccounts().where((a) => a.mask == '••••0855');
        final iciciLoan =
            store.bankAccounts().where((a) => a.mask == '••••1041');
        for (final loan in [...hdfcLoan, ...iciciLoan]) {
          final list =
              store.transactionsForAccount(evidenceKey: loan.evidenceKey);
          expect(list.any((t) => t.id.startsWith('kotak-')), isFalse);
          expect(loan.spentTotal, 0);
        }
      },
    );
  });
}
