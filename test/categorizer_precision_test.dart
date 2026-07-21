import 'package:flutter_test/flutter_test.dart';

import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/services/sms/merchant_categorizer.dart';
import 'package:paisa_app/services/sms/transaction_enrichment.dart';

/// ISSUE-13: categorizer precision + no personal NACH hardcoding.
void main() {
  group('MerchantCategorizer word boundaries', () {
    test('Cola does not match ola → travel', () {
      expect(
        MerchantCategorizer.categorize(
          merchant: 'Coca Cola Store',
          smsBody: 'Rs.100 spent at Coca Cola Store',
          isCredit: false,
        ),
        isNot(SpendCategory.travel),
      );
    });

    test('Jiomart does not match jio → bills', () {
      expect(
        MerchantCategorizer.categorize(
          merchant: 'Jiomart',
          smsBody: 'Rs.500 spent at Jiomart',
          isCredit: false,
        ),
        isNot(SpendCategory.bills),
      );
    });

    test('real Ola still matches travel', () {
      expect(
        MerchantCategorizer.categorize(
          merchant: 'Ola',
          smsBody: 'Rs.120 paid to Ola',
          isCredit: false,
        ),
        SpendCategory.travel,
      );
    });
  });

  group('BBPS / NACH classification', () {
    test('BBPS card-bill debit is transfer not bills', () {
      expect(
        MerchantCategorizer.categorize(
          merchant: 'BBPS',
          smsBody:
              'Rs.5000 debited for BBPS credit card bill payment towards SBI Card',
          isCredit: false,
        ),
        SpendCategory.transfer,
      );
    });

    test('generic NACH without loan wording is bills not emi', () {
      expect(
        MerchantCategorizer.categorize(
          merchant: 'NACH-10-HDFC BANK LIMITED Kotak Bank',
          smsBody:
              'INR 25,797.00 is debited to your Account XXXXXX3649 on 07/12/2025 towards NACH-10-HDFC BANK LIMITED Kotak Bank',
          isCredit: false,
        ),
        SpendCategory.bills,
      );
    });

    test('NACH with home loan wording stays emi', () {
      expect(
        MerchantCategorizer.categorize(
          merchant: 'HDFC Home Loan EMI',
          smsBody: 'Rs.8500 debited. Info: HDFC Home Loan EMI via NACH',
          isCredit: false,
        ),
        SpendCategory.emi,
      );
    });
  });

  group('loanLabelFromBody', () {
    test('generic NACH is labeled NACH debit not Home Loan EMI', () {
      expect(
        TransactionEnrichment.loanLabelFromBody(
          'towards NACH-10-HDFC BANK LIMITED Kotak Bank',
        ),
        'NACH debit',
      );
    });

    test('explicit home loan wording still labeled Home loan EMI', () {
      expect(
        TransactionEnrichment.loanLabelFromBody(
          'EMI of Rs 8500 towards HDFC Home Loan A/c 0855',
        ),
        'Home loan EMI',
      );
    });
  });
}
