import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/models/transaction.dart';
import 'package:paisa_app/services/sms/account_discovery.dart';
import 'package:paisa_app/services/sms/product_payment_linker.dart';

void main() {
  group('ProductPaymentLinker', () {
    Transaction debit({
      required String id,
      required String merchant,
      SpendCategory category = SpendCategory.other,
      AccountKind kind = AccountKind.savings,
    }) =>
        Transaction(
          id: id,
          merchant: merchant,
          bank: 'HDFC',
          maskedAccount: '••••5300',
          category: category,
          amount: 1000,
          isCredit: false,
          timestamp: DateTime(2026, 3, 1),
          accountKind: kind,
        );

    test('LIC Premium is not a loan-funding payment (R2-3)', () {
      expect(
        ProductPaymentLinker.looksLikeLoanFundingPayment(
          debit(id: 'lic', merchant: 'LIC Premium'),
        ),
        isFalse,
      );
      expect(
        ProductPaymentLinker.looksLikeLoanFundingPayment(
          debit(id: 'chem', merchant: 'Wellness Chemist'),
        ),
        isFalse,
      );
    });

    test('MBK EMI and word-bound NACH still look like loan funding', () {
      expect(
        ProductPaymentLinker.looksLikeLoanFundingPayment(
          debit(id: 'mbk', merchant: 'MBK EMI'),
        ),
        isTrue,
      );
      expect(
        ProductPaymentLinker.looksLikeLoanFundingPayment(
          debit(id: 'nach', merchant: 'NACH-10-HDFC BANK LIMITED'),
        ),
        isTrue,
      );
    });

    const loans = [
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
    ];

    test('does not attach funding when product deposit already covers amount', () {
      final all = [
        Transaction(
          id: 'mbk',
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
          id: 'pnb',
          merchant: 'Loan payment',
          bank: 'PNB',
          maskedAccount: '••••0310',
          category: SpendCategory.emi,
          amount: 5199.39,
          isCredit: false,
          timestamp: DateTime(2026, 2, 27, 1),
          accountKind: AccountKind.loan,
        ),
      ];

      final linked = ProductPaymentLinker.linkedFundingTransactions(
        productBank: 'PNB',
        productMask: '••••0310',
        productKind: AccountKind.loan,
        all: all,
        discoveries: loans,
      );
      expect(linked, isEmpty);

      final hdfcLinked = ProductPaymentLinker.linkedFundingTransactions(
        productBank: 'HDFC',
        productMask: '••••0855',
        productKind: AccountKind.loan,
        all: all,
        discoveries: loans,
      );
      expect(hdfcLinked, isEmpty);
    });

    test('orphan funding still links when no product SMS covers the amount', () {
      const onlyPnb = [
        DiscoveredAccount(
          bank: 'PNB',
          mask: '••••0310',
          kind: AccountKind.loan,
          smsHits: 4,
        ),
      ];
      final all = [
        Transaction(
          id: 'mbk',
          merchant: 'MBK EMI',
          bank: 'HDFC',
          maskedAccount: '••••5300',
          category: SpendCategory.emi,
          amount: 5199.39,
          isCredit: false,
          timestamp: DateTime(2026, 2, 27),
          accountKind: AccountKind.loan,
        ),
      ];

      final linked = ProductPaymentLinker.linkedFundingTransactions(
        productBank: 'PNB',
        productMask: '••••0310',
        productKind: AccountKind.loan,
        all: all,
        discoveries: onlyPnb,
      );
      expect(linked.map((t) => t.id), ['mbk']);
    });

    test('orphan CCBP still links to unique card when no product ack exists', () {
      const onlyCard = [
        DiscoveredAccount(
          bank: 'HDFC',
          mask: '••••9999',
          kind: AccountKind.creditCard,
          smsHits: 3,
        ),
      ];
      final all = [
        Transaction(
          id: 'ccbp',
          merchant: 'MBK CCBP',
          bank: 'SBI',
          maskedAccount: '••••0429',
          category: SpendCategory.bills,
          amount: 12000,
          isCredit: false,
          timestamp: DateTime(2026, 7, 1),
          accountKind: AccountKind.creditCard,
        ),
      ];

      final linked = ProductPaymentLinker.linkedFundingTransactions(
        productBank: 'HDFC',
        productMask: '••••9999',
        productKind: AccountKind.creditCard,
        all: all,
        discoveries: onlyCard,
      );
      expect(linked.map((t) => t.id), ['ccbp']);
    });

    test('does not attach CCBP when card payment-received covers amount', () {
      const onlyCard = [
        DiscoveredAccount(
          bank: 'HDFC',
          mask: '••••9999',
          kind: AccountKind.creditCard,
          smsHits: 3,
        ),
      ];
      final all = [
        Transaction(
          id: 'ccbp',
          merchant: 'MBK CCBP',
          bank: 'SBI',
          maskedAccount: '••••0429',
          category: SpendCategory.bills,
          amount: 12000,
          isCredit: false,
          timestamp: DateTime(2026, 7, 1),
          accountKind: AccountKind.creditCard,
        ),
        Transaction(
          id: 'ack',
          merchant: 'Payment received',
          bank: 'HDFC',
          maskedAccount: '••••9999',
          category: SpendCategory.bills,
          amount: 12000,
          isCredit: true,
          timestamp: DateTime(2026, 7, 1, 2),
          accountKind: AccountKind.creditCard,
        ),
      ];

      expect(
        ProductPaymentLinker.linkedFundingTransactions(
          productBank: 'HDFC',
          productMask: '••••9999',
          productKind: AccountKind.creditCard,
          all: all,
          discoveries: onlyCard,
        ),
        isEmpty,
      );
    });

    test('refuses ambiguous same-amount anchors on two loans', () {
      final all = [
        Transaction(
          id: 'mbk',
          merchant: 'MBK EMI',
          bank: 'HDFC',
          maskedAccount: '••••5300',
          category: SpendCategory.emi,
          amount: 5000,
          isCredit: false,
          timestamp: DateTime(2026, 2, 27),
          accountKind: AccountKind.loan,
        ),
        Transaction(
          id: 'pnb',
          merchant: 'Loan payment',
          bank: 'PNB',
          maskedAccount: '••••0310',
          category: SpendCategory.emi,
          amount: 5000,
          isCredit: false,
          timestamp: DateTime(2026, 2, 27, 1),
          accountKind: AccountKind.loan,
        ),
        Transaction(
          id: 'hdfc',
          merchant: 'Loan payment',
          bank: 'HDFC',
          maskedAccount: '••••0855',
          category: SpendCategory.emi,
          amount: 5000,
          isCredit: false,
          timestamp: DateTime(2026, 2, 27, 2),
          accountKind: AccountKind.loan,
        ),
      ];

      expect(
        ProductPaymentLinker.linkedFundingTransactions(
          productBank: 'PNB',
          productMask: '••••0310',
          productKind: AccountKind.loan,
          all: all,
          discoveries: loans,
        ),
        isEmpty,
      );
      expect(
        ProductPaymentLinker.linkedFundingTransactions(
          productBank: 'HDFC',
          productMask: '••••0855',
          productKind: AccountKind.loan,
          all: all,
          discoveries: loans,
        ),
        isEmpty,
      );
    });

    test('ignores funding outside pairing window', () {
      final all = [
        Transaction(
          id: 'mbk',
          merchant: 'MBK EMI',
          bank: 'HDFC',
          maskedAccount: '••••5300',
          category: SpendCategory.emi,
          amount: 5199.39,
          isCredit: false,
          timestamp: DateTime(2026, 1, 1),
          accountKind: AccountKind.loan,
        ),
        Transaction(
          id: 'pnb',
          merchant: 'Loan payment',
          bank: 'PNB',
          maskedAccount: '••••0310',
          category: SpendCategory.emi,
          amount: 5199.39,
          isCredit: false,
          timestamp: DateTime(2026, 2, 27),
          accountKind: AccountKind.loan,
        ),
      ];

      expect(
        ProductPaymentLinker.linkedFundingTransactions(
          productBank: 'PNB',
          productMask: '••••0310',
          productKind: AccountKind.loan,
          all: all,
          discoveries: loans,
        ),
        isEmpty,
      );
    });

    test('multi-loan orphan funding does not guess a product', () {
      final all = [
        Transaction(
          id: 'mbk',
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
          id: 'pnb',
          merchant: 'Loan payment',
          bank: 'PNB',
          maskedAccount: '••••0310',
          category: SpendCategory.emi,
          amount: 5199.39,
          isCredit: false,
          timestamp: DateTime(2026, 2, 27),
          accountKind: AccountKind.loan,
        ),
      ];

      expect(
        ProductPaymentLinker.linkedFundingTransactions(
          productBank: 'PNB',
          productMask: '••••0310',
          productKind: AccountKind.loan,
          all: all,
          discoveries: loans,
        ),
        isEmpty,
      );
    });
  });

  group('indexed pairing matches nested scan', () {
    void expectParity({
      required String productBank,
      required String productMask,
      required AccountKind productKind,
      required List<Transaction> all,
      required Iterable<DiscoveredAccount> discoveries,
    }) {
      final indexed = ProductPaymentLinker.linkedFundingTransactions(
        productBank: productBank,
        productMask: productMask,
        productKind: productKind,
        all: all,
        discoveries: discoveries,
      );
      final scan = ProductPaymentLinker.linkedFundingTransactionsScan(
        productBank: productBank,
        productMask: productMask,
        productKind: productKind,
        all: all,
        discoveries: discoveries,
      );
      expect(indexed.map((t) => t.id).toList(), scan.map((t) => t.id).toList());

      for (final t in all) {
        expect(
          ProductPaymentLinker.productSideCoversFunding(
            funding: t,
            productBank: productBank,
            productMask: productMask,
            all: all,
          ),
          ProductPaymentLinker.productSideCoversFundingScan(
            funding: t,
            productBank: productBank,
            productMask: productMask,
            all: all,
          ),
        );
      }
    }

    test('existing loan and card fixtures stay equivalent', () {
      const loans = [
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
      ];
      final covered = [
        Transaction(
          id: 'mbk',
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
          id: 'pnb',
          merchant: 'Loan payment',
          bank: 'PNB',
          maskedAccount: '••••0310',
          category: SpendCategory.emi,
          amount: 5199.39,
          isCredit: false,
          timestamp: DateTime(2026, 2, 27, 1),
          accountKind: AccountKind.loan,
        ),
      ];
      expectParity(
        productBank: 'PNB',
        productMask: '••••0310',
        productKind: AccountKind.loan,
        all: covered,
        discoveries: loans,
      );
      expectParity(
        productBank: 'HDFC',
        productMask: '••••0855',
        productKind: AccountKind.loan,
        all: covered,
        discoveries: loans,
      );

      const onlyPnb = [
        DiscoveredAccount(
          bank: 'PNB',
          mask: '••••0310',
          kind: AccountKind.loan,
          smsHits: 4,
        ),
      ];
      expectParity(
        productBank: 'PNB',
        productMask: '••••0310',
        productKind: AccountKind.loan,
        all: [covered.first],
        discoveries: onlyPnb,
      );

      const onlyCard = [
        DiscoveredAccount(
          bank: 'HDFC',
          mask: '••••9999',
          kind: AccountKind.creditCard,
          smsHits: 3,
        ),
      ];
      final ccbp = [
        Transaction(
          id: 'ccbp',
          merchant: 'MBK CCBP',
          bank: 'SBI',
          maskedAccount: '••••0429',
          category: SpendCategory.bills,
          amount: 12000,
          isCredit: false,
          timestamp: DateTime(2026, 7, 1),
          accountKind: AccountKind.creditCard,
        ),
        Transaction(
          id: 'ack',
          merchant: 'Payment received',
          bank: 'HDFC',
          maskedAccount: '••••9999',
          category: SpendCategory.bills,
          amount: 12000,
          isCredit: true,
          timestamp: DateTime(2026, 7, 1, 2),
          accountKind: AccountKind.creditCard,
        ),
      ];
      expectParity(
        productBank: 'HDFC',
        productMask: '••••9999',
        productKind: AccountKind.creditCard,
        all: ccbp,
        discoveries: onlyCard,
      );
      expectParity(
        productBank: 'HDFC',
        productMask: '••••9999',
        productKind: AccountKind.creditCard,
        all: [ccbp.first],
        discoveries: onlyCard,
      );
    });

    test('amount ±0.015 and 48h window boundaries match nested scan', () {
      const loan = [
        DiscoveredAccount(
          bank: 'PNB',
          mask: '••••0310',
          kind: AccountKind.loan,
          smsHits: 4,
        ),
      ];
      final anchorTime = DateTime(2026, 2, 27);
      Transaction product(double amount, DateTime at) => Transaction(
            id: 'p-$amount-${at.millisecondsSinceEpoch}',
            merchant: 'Loan payment',
            bank: 'PNB',
            maskedAccount: '••••0310',
            category: SpendCategory.emi,
            amount: amount,
            isCredit: false,
            timestamp: at,
            accountKind: AccountKind.loan,
          );
      Transaction funding(double amount, DateTime at) => Transaction(
            id: 'f-$amount-${at.millisecondsSinceEpoch}',
            merchant: 'MBK EMI',
            bank: 'HDFC',
            maskedAccount: '••••5300',
            category: SpendCategory.emi,
            amount: amount,
            isCredit: false,
            timestamp: at,
            accountKind: AccountKind.loan,
          );

      final cases = <List<Transaction>>[
        [funding(100, anchorTime), product(100.014, anchorTime)],
        [funding(100, anchorTime), product(100.015, anchorTime)],
        [funding(100, anchorTime), product(100.016, anchorTime)],
        [
          funding(5199.39, anchorTime),
          product(5199.39, anchorTime.add(const Duration(hours: 48))),
        ],
        [
          funding(5199.39, anchorTime),
          product(
            5199.39,
            anchorTime.add(const Duration(hours: 48, milliseconds: 1)),
          ),
        ],
        [
          funding(88.88, anchorTime),
          product(88.88, anchorTime.subtract(const Duration(hours: 24))),
          product(12.50, anchorTime),
        ],
      ];
      for (final all in cases) {
        expectParity(
          productBank: 'PNB',
          productMask: '••••0310',
          productKind: AccountKind.loan,
          all: all,
          discoveries: loan,
        );
      }
    });

    test('large mixed corpus stays equivalent (no funding-bank guess)', () {
      const loans = [
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
      ];
      final all = <Transaction>[
        for (var i = 0; i < 80; i++)
          Transaction(
            id: 'spend-$i',
            merchant: 'Swiggy',
            bank: 'HDFC',
            maskedAccount: '••••5300',
            category: SpendCategory.food,
            amount: 100 + i * 0.01,
            isCredit: false,
            timestamp: DateTime(2026, 1, 1).add(Duration(hours: i)),
            accountKind: AccountKind.savings,
          ),
        Transaction(
          id: 'mbk-covered',
          merchant: 'MBK EMI',
          bank: 'HDFC',
          maskedAccount: '••••5300',
          category: SpendCategory.emi,
          amount: 3333.33,
          isCredit: false,
          timestamp: DateTime(2026, 3, 1),
          accountKind: AccountKind.loan,
        ),
        Transaction(
          id: 'pnb-ack',
          merchant: 'Loan payment',
          bank: 'PNB',
          maskedAccount: '••••0310',
          category: SpendCategory.emi,
          amount: 3333.33,
          isCredit: false,
          timestamp: DateTime(2026, 3, 1, 3),
          accountKind: AccountKind.loan,
        ),
        Transaction(
          id: 'orphan',
          merchant: 'MBK EMI',
          bank: 'HDFC',
          maskedAccount: '••••5300',
          category: SpendCategory.emi,
          amount: 111.11,
          isCredit: false,
          timestamp: DateTime(2026, 4, 1),
          accountKind: AccountKind.loan,
        ),
      ];

      expectParity(
        productBank: 'PNB',
        productMask: '••••0310',
        productKind: AccountKind.loan,
        all: all,
        discoveries: loans,
      );
      expectParity(
        productBank: 'HDFC',
        productMask: '••••0855',
        productKind: AccountKind.loan,
        all: all,
        discoveries: loans,
      );
    });
  });
}
