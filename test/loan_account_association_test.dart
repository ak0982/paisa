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

  group('resolveLoanDisplay', () {
    test('NACH-HDFC remaps onto discovered loan mask', () {
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
      expect(result.bank, 'HDFC');
      expect(result.mask, '••••0855');
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

    test('MBK EMI attaches to unique loan', () {
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
      expect(result.bank, 'PNB');
      expect(result.mask, '••••0310');
    });

    test('MBK EMI with multiple loans keeps funding identity (no bank guess)', () {
      // Live shape: HDFC UPI "To MBK EMI" pays PNB loan ••••0310 — must NOT
      // land on HDFC home loan ••••0855 just because funding bank is HDFC.
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

    test('PNB loan deposit body last-4 wins with multiple loans', () {
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

    test('NACH HDFC remaps only when HDFC loan is unique at that bank', () {
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
      expect(unique.bank, 'HDFC');
      expect(unique.mask, '••••0855');
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
          // Ambiguous funding UPI — must not appear under HDFC loan.
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
      // Product SMS already covers ₹5199.39 — show only that row on PNB.
      // Funding MBK debit stays on HDFC savings.
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
      // No product SMS for 1111.11 → funding EMI must not invent a link.
      expect(pnbTx.map((t) => t.id).toSet(), {'pnb-other'});
      expect(pnbTx.any((t) => t.id == 'mbk-orphan'), isFalse);
    });

    test('UPI destination last-4 remaps onto unique loan', () {
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
      expect(result.bank, 'PNB');
      expect(result.mask, '••••0310');
    });

    test('EMI on funding mask appears under unique loan account', () {
      final store = FinanceStore()
        ..seedDiscoveredAccounts([
          const DiscoveredAccount(
            bank: 'HDFC',
            mask: '••••0855',
            kind: AccountKind.loan,
            smsHits: 5,
            accountLabel: 'Home Loan',
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
      final txns = store.transactionsForAccount(evidenceKey: loan.evidenceKey);
      expect(txns.map((t) => t.id).toSet(), {'emi1', 'emi2', 'loan-credit'});
      expect(loan.spentTotal, 17000);
    });
  });
}
