import 'package:flutter_test/flutter_test.dart';

import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/services/sms/merchant_categorizer.dart';

void main() {
  group('MerchantCategorizer', () {
    test('classifies Kotak NACH without loan wording as bills not emi', () {
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

    test('classifies IRCTC credit card spend as travel', () {
      expect(
        MerchantCategorizer.categorize(
          merchant: 'IRCTCAutoPe',
          smsBody:
              'Rs.605.29 spent on your SBI Credit Card ending 3452 at IRCTCAutoPe on 07/12/25.',
          isCredit: false,
        ),
        SpendCategory.travel,
      );
    });

    test('classifies P2P NEFT with generic merchant as transfer', () {
      expect(
        MerchantCategorizer.categorize(
          merchant: 'Transfer',
          smsBody: 'neft dr to account',
          isCredit: false,
        ),
        SpendCategory.transfer,
      );
    });

    test('classifies HDFC to beneficiary account UPI as transfer', () {
      expect(
        MerchantCategorizer.categorize(
          merchant: 'Transaction',
          smsBody:
              'HDFC Bank:Rs. 52000.00 debited from a/c *5300 on 28/11/25 to a/c **3649 (UPI Ref No. 568362879750).',
          isCredit: false,
        ),
        SpendCategory.transfer,
      );
    });

    test('classifies UPI trf-to merchant debit as transfer (generic)', () {
      expect(
        MerchantCategorizer.categorize(
          merchant: 'Innofin Solution',
          smsBody:
              'Dear UPI user A/C X0429 debited by 3250.00 on date 04Jun26 trf to INNOFIN SOLUTION Refno 726571152867',
          isCredit: false,
        ),
        SpendCategory.transfer,
      );
    });

    test('classifies wallet platform credit as transfer (generic)', () {
      expect(
        MerchantCategorizer.categorize(
          merchant: 'Lendenclub',
          smsBody:
              'Dear BELI, Rs. 2500.00 has been credited to your LenDenClub account. The amount is available for lending.',
          isCredit: true,
        ),
        SpendCategory.transfer,
      );
    });

    test('keeps Swiggy UPI spend as food', () {
      expect(
        MerchantCategorizer.categorize(
          merchant: 'Swiggy',
          smsBody:
              'Sent Rs.486.00 from a/c **4321 to Swiggy on 07-Jul UPI ref 5521',
          isCredit: false,
        ),
        SpendCategory.food,
      );
    });

    test('SBI trf-to brand merchant stays food not transfer (R2-1)', () {
      expect(
        MerchantCategorizer.categorize(
          merchant: 'SWIGGY',
          smsBody:
              'Dear UPI user A/C X0429 debited by 500.00 on date 04Jun26 '
              'trf to SWIGGY Refno 726571152867',
          isCredit: false,
        ),
        SpendCategory.food,
      );
    });

    test('SBI trf-to CCBP stays transfer (R2-1 / ISSUE-13)', () {
      expect(
        MerchantCategorizer.categorize(
          merchant: 'MBK CCBP',
          smsBody:
              'Dear UPI user A/C X0429 debited by 500.00 on date 04Jun26 '
              'trf to MBK CCBP Refno 101568018632',
          isCredit: false,
        ),
        SpendCategory.transfer,
      );
    });
  });
}
