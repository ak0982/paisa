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
  });

  group('loan account drilldown', () {
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
