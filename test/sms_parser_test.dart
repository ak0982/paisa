import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/services/sms/account_bank_registry.dart';
import 'package:paisa_app/services/sms/parsed_sms_transaction.dart';
import 'package:paisa_app/services/sms/sms_parser.dart';

void main() {
  group('SmsParser', () {
    test('parses HDFC UPI debit', () {
      final parsed = SmsParser.parse(_msg(
        sender: 'VM-HDFCBK',
        body:
            'Sent Rs.486.00 from a/c **4321 to Swiggy on 07-Jul-26 UPI ref 5521.',
      ));
      expect(parsed, isNotNull);
      expect(parsed!.amount, 486);
      expect(parsed.isCredit, false);
      expect(parsed.merchant, 'Swiggy');
      expect(parsed.maskedAccount, '••••4321');
    });

    test('parses SBI debit with Info merchant', () {
      final parsed = SmsParser.parse(_msg(
        sender: 'SBIINB',
        body:
            'Dear SBI User, Rs.2,499.00 debited from A/c XX8890 on 06Jul26. Info: AMAZON.IN',
      ));
      expect(parsed, isNotNull);
      expect(parsed!.amount, 2499);
      expect(parsed.merchant.toLowerCase(), contains('amazon'));
    });

    test('parses ICICI debit', () {
      final parsed = SmsParser.parse(_msg(
        sender: 'ICICIT',
        body:
            'ICICI Bank Acct XX4321 debited for Rs 8500.00 on 03-Jul-26; HDFC Home Loan EMI credited',
      ));
      expect(parsed, isNotNull);
      expect(parsed!.amount, 8500);
    });

    test('parses Axis INR debit', () {
      final parsed = SmsParser.parse(_msg(
        sender: 'AXISBK',
        body: 'INR 312.00 debited on 07-07-26. Info: Ola',
      ));
      expect(parsed, isNotNull);
      expect(parsed!.merchant, 'Ola');
    });

    test('parses Kotak towards merchant', () {
      final parsed = SmsParser.parse(_msg(
        sender: 'KOTAKB',
        body:
            'Rs.645.00 debited from Kotak Bank a/c XXXX7756 towards Zomato on 06/07/26',
      ));
      expect(parsed, isNotNull);
      expect(parsed!.merchant, 'Zomato');
    });

    test('parses Paytm payment', () {
      final parsed = SmsParser.parse(_msg(
        sender: 'VM-PAYTMB',
        body: 'Rs.299 paid to Jio Recharge via Paytm on 06-Jul',
      ));
      expect(parsed, isNotNull);
      expect(parsed!.merchant, contains('Jio'));
    });

    test('parses credit to account', () {
      final parsed = SmsParser.parse(_msg(
        sender: 'AXISBK',
        body: 'Rs. 68000.00 credited to your a/c **2015 on 01-Jul-26',
      ));
      expect(parsed, isNotNull);
      expect(parsed!.isCredit, true);
      expect(parsed.amount, 68000);
    });

    test('ignores personal chat', () {
      final parsed = SmsParser.parse(_msg(
        sender: 'FRIEND',
        body: 'Hey, are we meeting for lunch tomorrow?',
      ));
      expect(parsed, isNull);
    });

    test('ignores OTP-only SMS', () {
      final parsed = SmsParser.parse(_msg(
        sender: 'HDFCBK',
        body: 'Your OTP for login is 482910. Do not share with anyone.',
      ));
      expect(parsed, isNull);
    });

    test('ignores HDFC pre-approved loan offer', () {
      expect(
        SmsParser.isLikelyBankSms(
          'VM-HDFCBK',
          'Dear Customer, Get pre-approved Personal Loan of Rs.5,00,000 on your '
          'HDFC Bank A/c. Interest rate starts 10.5%. Apply now.',
        ),
        isFalse,
      );
      expect(
        SmsParser.parse(_msg(
          sender: 'VM-HDFCBK',
          body:
              'Dear Customer, Get pre-approved Personal Loan of Rs.5,00,000 on your '
              'HDFC Bank A/c. Interest rate starts 10.5%. Apply now.',
        )),
        isNull,
      );
    });

    test('ignores ICICI loan eligibility SMS', () {
      final parsed = SmsParser.parse(_msg(
        sender: 'ICICIT',
        body:
            'You are eligible for instant loan up to Rs.10,00,000. '
            'Zero processing fee offer. Click here to apply. T&C apply.',
      ));
      expect(parsed, isNull);
    });

    test('ignores SBI credit card offer with amount', () {
      final parsed = SmsParser.parse(_msg(
        sender: 'SBIINB',
        body:
            'Exclusive offer for you! SBI Credit Card with limit Rs.3,00,000. '
            'Apply now on SBI Card app. Limited period offer.',
      ));
      expect(parsed, isNull);
    });

    test('still parses real Home Loan EMI debit with loan keyword', () {
      final parsed = SmsParser.parse(_msg(
        sender: 'HDFCBK',
        body:
            'Rs.8,500.00 debited from a/c **4321 on 03-Jul-26. '
            'Info: HDFC Home Loan EMI. Avl Bal Rs.32,000',
      ));
      expect(parsed, isNotNull);
      expect(parsed!.amount, 8500);
      expect(parsed.isCredit, false);
    });

    test('ignores HDFC SmartEMI offer', () {
      expect(
        SmsParser.parse(_msg(
          sender: 'VM-HDFCBK',
          body:
              'Dear Customer, convert your spends to SmartEMI on HDFC Bank '
              'Credit Card. Enjoy easy repayment on Rs.25,000. T&C apply.',
        )),
        isNull,
      );
    });

    test('ignores SBI YONO offer', () {
      expect(
        SmsParser.parse(_msg(
          sender: 'SBIINB',
          body:
              'SBI YONO offer! Get SimplyCLICK credit card with limit '
              'Rs.2,00,000. Apply now on YONO app.',
        )),
        isNull,
      );
    });

    test('ignores ICICI iMobile card offer', () {
      expect(
        SmsParser.parse(_msg(
          sender: 'ICICIT',
          body:
              'ICICI Bank iMobile offer: Amazon Pay ICICI Credit Card with '
              'Rs.5,000 welcome benefit. Apply today.',
        )),
        isNull,
      );
    });

    test('ignores Axis Grab Deals promo', () {
      expect(
        SmsParser.parse(_msg(
          sender: 'AXISBK',
          body:
              'Axis Bank Grab Deals! Axis Neo offer on Flipkart Axis card. '
              'Earn 5X rewards. Limited period offer on your account.',
        )),
        isNull,
      );
    });

    test('ignores Kotak 811 offer', () {
      expect(
        SmsParser.parse(_msg(
          sender: 'KOTAKB',
          body:
              'Kotak 811 offer! Dream Different with Kotak 811 Super offer. '
              'Open account and get Rs.500 cashback. Apply now.',
        )),
        isNull,
      );
    });

    test('ignores Paytm scratch card promo', () {
      expect(
        SmsParser.parse(_msg(
          sender: 'VM-PAYTMB',
          body:
              'Paytm offer! Scratch card unlocked. Refer and earn Rs.100 '
              'cashback offer. Claim your reward now.',
        )),
        isNull,
      );
    });

    test('ignores PhonePe refer and earn', () {
      expect(
        SmsParser.parse(_msg(
          sender: 'PHONEPE',
          body:
              'PhonePe rewards! Refer and earn up to Rs.200. Win upto Rs.500 '
              'with PhonePe cashback offer. Invite friends today.',
        )),
        isNull,
      );
    });

    test('parses Indian lakh amount Rs.1,25,000', () {
      final parsed = SmsParser.parse(_msg(
        sender: 'HDFCBK',
        body:
            'Rs.1,25,000.00 debited from a/c **4321 on 07-Jul-26. Info: CAR DEALER',
      ));
      expect(parsed, isNotNull);
      expect(parsed!.amount, 125000);
    });

    test('parses unicode rupee ₹ amount', () {
      final parsed = SmsParser.parse(_msg(
        sender: 'HDFCBK',
        body: '₹1,299.00 debited from a/c **4321 on 07-Jul-26. Info: AMAZON',
      ));
      expect(parsed, isNotNull);
      expect(parsed!.amount, 1299);
    });

    test('rejects short SMS from bank sender', () {
      expect(
        SmsParser.parse(_msg(sender: 'HDFCBK', body: 'Hi')),
        isNull,
      );
    });

    test('parses SBI UPI debited by format', () {
      final parsed = SmsParser.parse(_msg(
        sender: 'JK-SBIUPI-S',
        body:
            'Dear UPI user A/C X0429 debited by 3250.00 on date 04Jun26 trf to INNOFIN SOLUTION Refno 726571152867 If not u? call-1800111109',
      ));
      expect(parsed, isNotNull);
      expect(parsed!.amount, 3250);
      expect(parsed.isCredit, false);
      expect(parsed.merchant, 'Innofin Solution');
      expect(parsed.bank, 'SBI');
      expect(parsed.maskedAccount, '••••0429');
    });

    test('parses SBI UPI reversal credit', () {
      final parsed = SmsParser.parse(_msg(
        sender: 'AD-SBIUPI-S',
        body:
            'Dear SBI UPI User, ur A/cX0429 credited with Rs500.00 on 04Jun26 against reversal of txn (Ref no 215710312511)',
      ));
      expect(parsed, isNotNull);
      expect(parsed!.isCredit, true);
      expect(parsed.amount, 500);
    });

    test('parses HDFC Sent From Bank A/C format', () {
      final parsed = SmsParser.parse(_msg(
        sender: 'AD-HDFCBK-S',
        body:
            'Sent Rs.3000.00 From HDFC Bank A/C *5300 To AKASH AKASH On 09/12/25 Ref 534393045988 Not You? Call 18002586161',
      ));
      expect(parsed, isNotNull);
      expect(parsed!.amount, 3000);
      expect(parsed.merchant, contains('Akash'));
      expect(parsed.maskedAccount, '••••5300');
    });

    test('parses HDFC Credit Alert', () {
      final parsed = SmsParser.parse(_msg(
        sender: 'AD-HDFCBK-S',
        body:
            'Credit Alert! Rs.1000.00 credited to HDFC Bank A/c XX5300 on 05-12-25 from VPA diwakarbharti4-1@oksbi (UPI 533995897890)',
      ));
      expect(parsed, isNotNull);
      expect(parsed!.isCredit, true);
      expect(parsed.amount, 1000);
      expect(parsed.merchant.toLowerCase(), contains('diwakarbharti4'));
    });

    test('parses ICICI credited with amount format', () {
      final registry = AccountBankRegistry();
      registry.learn(
        'JK-SBIUPI-S',
        'Dear UPI user A/C X0429 debited by 3250.00 on date 04Jun26 trf to INNOFIN SOLUTION Refno 726571152867 If not u? call-1800111109 for other services-18001234-SBI',
      );

      final parsed = SmsParser.parseTransaction(
        _msg(
          sender: 'JD-ICICIT-S',
          body:
              'Dear BELI DEVI ,Your account  XXXXXXXX0429  has been credited with amount  2602.25 .Reference no- CMS5707356009 .Thanks,  LENDENCLUB BORROWER REPAYMENT ISP LTD ACCOUNT',
        ),
        registry: registry,
      );
      expect(parsed, isNotNull);
      expect(parsed!.isCredit, true);
      expect(parsed.amount, 2602.25);
      expect(parsed.maskedAccount, '••••0429');
      expect(parsed.bank, 'SBI');
      expect(
        parsed.merchant.toLowerCase(),
        contains('borrower repayment'),
      );
    });

    test('parses ICICI credited with amount 2948.45', () {
      final registry = AccountBankRegistry();
      registry.learn(
        'JK-SBIUPI-S',
        'Dear UPI user A/C X0429 debited by 3250.00 on date 04Jun26 trf to INNOFIN SOLUTION Refno 726571152867 If not u? call-1800111109 for other services-18001234-SBI',
      );

      final parsed = SmsParser.parseTransaction(
        _msg(
          sender: 'JD-ICICIT-S',
          body:
              'Dear  BELI  DEVI ,Your account  XXXXXXXX0429  has been credited with amount  2948.45 .Reference no-  CMS5760782566 .Thanks,  LENDENCLUB BORROWER REPAYMENT ISP LTD ACCOUNT',
        ),
        registry: registry,
      );
      expect(parsed, isNotNull);
      expect(parsed!.amount, 2948.45);
      expect(parsed.maskedAccount, '••••0429');
      expect(parsed.bank, 'SBI');
      expect(parsed.isCredit, true);
    });

    test('parses ICICI IMPS debit', () {
      final parsed = SmsParser.parse(_msg(
        sender: 'AD-ICICIT-S',
        body:
            'ICICI Bank Acct XX505 debited with Rs 74,000.00 on 01-Jun-26 & Acct XX675 credited.IMPS:615219049930. Call 18002662 for dispute',
      ));
      expect(parsed, isNotNull);
      expect(parsed!.amount, 74000);
      expect(parsed.isCredit, false);
    });

    test('HDFC UPI debit uses source account not amount digits', () {
      final parsed = SmsParser.parseTransaction(_msg(
        sender: 'JX-HDFCBK-S',
        body:
            'HDFC Bank:Rs. 52000.00 debited from a/c *5300 on 28/11/25 to a/c **3649 (UPI Ref No. 568362879750). Not you? Call on 18002586161 to report',
      ));
      expect(parsed, isNotNull);
      expect(parsed!.maskedAccount, '••••5300');
      expect(parsed.amount, 52000);
      expect(parsed.isCredit, false);
    });

    test('parses platform wallet top-up credit generically', () {
      final parsed = SmsParser.parseTransaction(_msg(
        sender: 'JK-LENDEN-S',
        body:
            'Dear BELI, Rs. 2500.00 has been credited to your LenDenClub account. The amount is available for lending. -LenDenClub',
      ));
      expect(parsed, isNotNull);
      expect(parsed!.amount, 2500);
      expect(parsed.isCredit, true);
      expect(parsed.merchant.toLowerCase(), contains('lenden'));
      expect(parsed.bank, 'LenDenClub');
    });

    test('self-transfer both legs parse independently', () {
      final debit = SmsParser.parseTransaction(_msg(
        sender: 'VM-SBIUPI',
        body:
            'Dear UPI user A/C X0429 debited by 5000.00 on date 11Jul26 trf to AMAR KUMAR Refno 719912345678 If not u? call-1800111109',
      ));
      final credit = SmsParser.parseTransaction(_msg(
        sender: 'AXISBK',
        body: 'Rs. 5000.00 credited to your a/c **9867 on 11-Jul-26',
      ));
      expect(debit, isNotNull);
      expect(credit, isNotNull);
      expect(debit!.amount, 5000);
      expect(debit.isCredit, false);
      expect(debit.maskedAccount, '••••0429');
      expect(credit!.amount, 5000);
      expect(credit.isCredit, true);
      expect(credit.maskedAccount, '••••9867');
    });

    test('parses Kotak NACH debit from account 3649', () {
      final parsed = SmsParser.parseTransaction(_msg(
        sender: 'VM-KOTAKB-S',
        body:
            'INR 25,797.00 is debited to your Account XXXXXX3649 on 07/12/2025 towards NACH-10-HDFC BANK LIMITED Kotak Bank',
      ));
      expect(parsed, isNotNull);
      expect(parsed!.bank, 'Kotak');
      expect(parsed.maskedAccount, '••••3649');
      expect(parsed.amount, 25797);
      expect(parsed.isCredit, false);
    });

    test('parses SBI NACH credit to account 6675', () {
      final parsed = SmsParser.parseTransaction(_msg(
        sender: 'VM-CBSSBI-S',
        body:
            'Dear Customer,Your A/C XXXXX286675 has a credit by NACH- POWER GRID CORPORATI of Rs 733.50 on 01/12/25.',
      ));
      expect(parsed, isNotNull);
      expect(parsed!.bank, 'SBI');
      expect(parsed.maskedAccount, '••••6675');
      expect(parsed.amount, 733.50);
      expect(parsed.isCredit, true);
    });

    test('parses Yes Bank credit card spend', () {
      final parsed = SmsParser.parseTransaction(_msg(
        sender: 'AD-YESBNK-S',
        body:
            'INR 449.54 spent on YES BANK Card X9757 @UPI_MCDONALDS HARDCAST 07-12-2025 05:01:14 pm.',
      ));
      expect(parsed, isNotNull);
      expect(parsed!.bank, 'Yes Bank');
      expect(parsed.maskedAccount, '••••9757');
      expect(parsed.amount, 449.54);
      expect(parsed.isCredit, false);
      expect(parsed.merchant.toLowerCase(), contains('mcdonalds'));
    });
  });
}

SmsMessageInput _msg({required String sender, required String body}) {
  return SmsMessageInput(
    id: 'test',
    sender: sender,
    body: body,
    timestamp: DateTime(2026, 7, 7),
  );
}
