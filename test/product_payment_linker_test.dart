import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/models/transaction.dart';
import 'package:paisa_app/services/sms/account_discovery.dart';
import 'package:paisa_app/services/sms/product_payment_linker.dart';

void main() {
  group('ProductPaymentLinker', () {
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
}
