import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/services/sms/account_bank_registry.dart';
import 'package:paisa_app/services/sms/account_discovery.dart';
import 'package:paisa_app/services/sms/parsed_sms_transaction.dart';
import 'package:paisa_app/services/sms/sms_parser.dart';
import 'package:paisa_app/services/sms/sms_scan_pipeline.dart';
import 'package:paisa_app/utils/bank_assets.dart';

SmsPipelineResult _parse(String sender, String body) {
  return SmsScanPipeline.process(
    SmsMessageInput(
      id: 't1_${sender.hashCode}_${body.hashCode}',
      sender: sender,
      body: body,
      timestamp: DateTime(2026, 7, 12),
    ),
  );
}

void main() {
  group('Tier-1 DLT sender mapping', () {
    test('CANBNK maps to Canara (not CANARA substring)', () {
      expect(SmsParser.isFinancialSender('VK-CANBNK-S'), isTrue);
      expect(SmsScanPipeline.isFinancialSender('VK-CANBNK-S'), isTrue);
      final r = _parse(
        'VK-CANBNK-S',
        'Dear Customer, Acct XXX5510 Dr. INR 320.00 on 11/07/26 to PHONEPE MART; UPI: 111222333444; Bal INR 4,100.00.-CanaraBank',
      );
      expect(r.outcome, SmsPipelineOutcome.parsed);
      expect(r.transaction!.bank, 'Canara');
    });

    test('BOBSMS / BOBTXN / BOBCRD map to Bank of Baroda', () {
      expect(SmsParser.isFinancialSender('VM-BOBSMS-S'), isTrue);
      expect(SmsParser.isFinancialSender('AX-BOBTXN-S'), isTrue);
      expect(SmsParser.isFinancialSender('JD-BOBCRD-S'), isTrue);
    });

    test('UNIONB / BOIIND / INDBNK / INDUSB map correctly', () {
      final union = _parse(
        'VM-UNIONB-S',
        'A/c *7788 Debited for Rs:1500.00 on 12-07-2026 18:28:02 by Mob Bk ref no 123456789000 Avl Bal Rs:8200.00',
      );
      expect(union.transaction!.bank, 'Union Bank');

      final boi = _parse(
        'JX-BOIIND-S',
        'Rs.200.00 debited A/cXX5468 and credited to SAI MISAL via UPI Ref No 315439383341 on 23Aug25. -BOI',
      );
      expect(boi.transaction!.bank, 'Bank of India');

      final indian = _parse(
        'VM-INDBNK-S',
        'Sent Rs.250.00 from A/c XX3344 to SWIGGY.RRN 987654321012. Avl Bal Rs.9,000.00 -Indian Bank',
      );
      expect(indian.transaction!.bank, 'Indian Bank');

      final indus = _parse(
        'VM-INDUSB-S',
        'INR 499.00 spent on IndusInd Card XX4821 on 14-06-2026 04:21:45 pm at INSTAMART. Avl Lmt: INR 45000.00.',
      );
      expect(indus.transaction!.bank, 'IndusInd');
    });

    test('INDBNK does not collide with IndusInd INDUSB', () {
      final indian = _parse(
        'AX-INDBNK-S',
        'A/c XX3344 debited Rs. 100.00 on 01-07-2026. Avl Bal Rs.500.00 -Indian Bank',
      );
      expect(indian.transaction!.bank, 'Indian Bank');
      expect(indian.transaction!.bank, isNot('IndusInd'));
    });
  });

  group('Canara', () {
    test('compact Dr. INR debit + mask + merchant', () {
      final r = _parse(
        'VK-CANBNK-S',
        'Dear Customer, Acct XXX5510 Dr. INR 320.00 on 11/07/26 to PHONEPE MART; UPI: 111222333444; Bal INR 4,100.00.-CanaraBank',
      );
      expect(r.isParsed, isTrue);
      expect(r.transaction!.amount, 320);
      expect(r.transaction!.isCredit, isFalse);
      expect(r.transaction!.maskedAccount, contains('5510'));
      expect(r.transaction!.merchant.toLowerCase(), contains('phonepe'));
    });

    test('Cr. credit parses', () {
      final r = _parse(
        'VK-CANBNK-S',
        'Dear Customer, Acct XXX5510 Cr. INR 5,000.00 on 12/07/26 by NEFT; Bal INR 9,100.00.-CanaraBank',
      );
      expect(r.isParsed, isTrue);
      expect(r.transaction!.isCredit, isTrue);
      expect(r.transaction!.amount, 5000);
      expect(r.transaction!.maskedAccount, contains('5510'));
    });

    test('discovery finds Canara savings mask', () {
      final d = AccountDiscovery.discover(
        sender: 'VK-CANBNK-S',
        body:
            'Dear Customer, Acct XXX5510 Dr. INR 320.00 on 11/07/26 to PHONEPE MART; UPI: 111222333444; Bal INR 4,100.00.-CanaraBank',
      );
      expect(d, isNotNull);
      expect(d!.bank, 'Canara');
      expect(d.mask, contains('5510'));
      expect(d.kind, AccountKind.savings);
    });
  });

  group('Bank of Baroda', () {
    test('savings Dr. from A/c', () {
      final r = _parse(
        'VM-BOBSMS-S',
        'Rs.750.00 Dr. from A/c XX7788 on 12-07-26. AvlBal:Rs8200.00 -Bank of Baroda',
      );
      expect(r.isParsed, isTrue);
      expect(r.transaction!.bank, 'Bank of Baroda');
      expect(r.transaction!.amount, 750);
      expect(r.transaction!.isCredit, isFalse);
      expect(r.transaction!.maskedAccount, contains('7788'));
    });

    test('savings Cr. to A/c', () {
      final r = _parse(
        'VM-BOBTXN-S',
        'Rs.2,000.00 Cr. to A/c XX7788 on 12-07-26 via IMPS. AvlBal:Rs10200.00',
      );
      expect(r.isParsed, isTrue);
      expect(r.transaction!.isCredit, isTrue);
      expect(r.transaction!.amount, 2000);
    });

    test('BOBCARD spend still parses', () {
      final r = _parse(
        'JD-BOBCRD-S',
        "INR 1,299.00 is spent on your BOBCARD ending 4455 at AMAZON PAY on 12-07-26.",
      );
      expect(r.isParsed, isTrue);
      expect(r.transaction!.bank, 'Bank of Baroda');
      expect(r.transaction!.amount, 1299);
      expect(r.transaction!.maskedAccount, contains('4455'));
    });

    test('discovery finds BOB savings and BOBCARD', () {
      final savings = AccountDiscovery.discover(
        sender: 'VM-BOBSMS-S',
        body:
            'Rs.750.00 Dr. from A/c XX7788 on 12-07-26. AvlBal:Rs8200.00 -Bank of Baroda',
      );
      expect(savings?.bank, 'Bank of Baroda');
      expect(savings?.kind, AccountKind.savings);

      final card = AccountDiscovery.discover(
        sender: 'JD-BOBCRD-S',
        body:
            'INR 1,299.00 is spent on your BOBCARD ending 4455 at AMAZON PAY on 12-07-26.',
      );
      expect(card?.bank, 'Bank of Baroda');
      expect(card?.kind, AccountKind.creditCard);
      expect(card?.mask, contains('4455'));
    });
  });

  group('Union Bank', () {
    test('Debited for Rs: debit', () {
      final r = _parse(
        'VM-UNIONB-S',
        'A/c *7788 Debited for Rs:1500.00 on 12-07-2026 18:28:02 by Mob Bk ref no 123456789000 Avl Bal Rs:8200.00',
      );
      expect(r.isParsed, isTrue);
      expect(r.transaction!.bank, 'Union Bank');
      expect(r.transaction!.amount, 1500);
      expect(r.transaction!.isCredit, isFalse);
      expect(r.transaction!.maskedAccount, contains('7788'));
    });

    test('Credited for Rs: credit', () {
      final r = _parse(
        'VM-UNIONB-S',
        'A/c *7788 Credited for Rs:500.00 on 12-07-2026 by NEFT ref no 999 Avl Bal Rs:8700.00',
      );
      expect(r.isParsed, isTrue);
      expect(r.transaction!.isCredit, isTrue);
      expect(r.transaction!.amount, 500);
    });

    test('discovery + registry learn UNIONB', () {
      final d = AccountDiscovery.discover(
        sender: 'VM-UNIONB-S',
        body:
            'A/c *7788 Debited for Rs:1500.00 on 12-07-2026 18:28:02 by Mob Bk ref no 123456789000 Avl Bal Rs:8200.00',
      );
      expect(d?.bank, 'Union Bank');
      expect(d?.mask, contains('7788'));

      final registry = AccountBankRegistry();
      registry.learn(
        'VM-UNIONB-S',
        'A/c *7788 Debited for Rs:1500.00 on 12-07-2026 Avl Bal Rs:8200.00',
      );
      expect(registry.lookup('7788'), 'Union Bank');
    });

    test('letter avatar fallback (no bundled logo)', () {
      expect(BankAssets.assetPathFor('Union Bank'), isNull);
      expect(BankAssets.fallbackLetter('Union Bank'), 'U');
    });
  });

  group('Bank of India', () {
    test('UPI debit and credited to merchant', () {
      final r = _parse(
        'JX-BOIIND-S',
        'Rs.200.00 debited A/cXX5468 and credited to SAI MISAL via UPI Ref No 315439383341 on 23Aug25. -BOI',
      );
      expect(r.isParsed, isTrue);
      expect(r.transaction!.bank, 'Bank of India');
      expect(r.transaction!.amount, 200);
      expect(r.transaction!.maskedAccount, contains('5468'));
      expect(r.transaction!.merchant.toLowerCase(), contains('sai'));
    });

    test('NEFTINWARD credit', () {
      final r = _parse(
        'VM-BOIIND-S',
        'BOI - Rs 3,500.00 Credited in your Ac XX5468 on 12-07-26 By NEFTINWARD ABC123/PAYROLL .Avl Bal 12000.00',
      );
      expect(r.isParsed, isTrue);
      expect(r.transaction!.isCredit, isTrue);
      expect(r.transaction!.amount, 3500);
      expect(r.transaction!.maskedAccount, contains('5468'));
    });

    test('discovery finds BOI savings', () {
      final d = AccountDiscovery.discover(
        sender: 'JX-BOIIND-S',
        body:
            'Rs.200.00 debited A/cXX5468 and credited to SAI MISAL via UPI Ref No 315439383341 on 23Aug25. -BOI',
      );
      expect(d?.bank, 'Bank of India');
      expect(d?.mask, contains('5468'));
      expect(d?.kind, AccountKind.savings);
    });
  });

  group('Indian Bank', () {
    test('Sent Rs … RRN UPI debit', () {
      final r = _parse(
        'VM-INDBNK-S',
        'Sent Rs.250.00 from A/c XX3344 to SWIGGY.RRN 987654321012. Avl Bal Rs.9,000.00 -Indian Bank',
      );
      expect(r.isParsed, isTrue);
      expect(r.transaction!.bank, 'Indian Bank');
      expect(r.transaction!.amount, 250);
      expect(r.transaction!.maskedAccount, contains('3344'));
    });

    test('debited Rs credit/debit verbs', () {
      final debit = _parse(
        'VM-INDBNK-S',
        'A/c XX3344 debited Rs. 80.00 on 01-07-2026. -Indian Bank',
      );
      expect(debit.transaction!.isCredit, isFalse);
      expect(debit.transaction!.amount, 80);

      final credit = _parse(
        'VM-INDBNK-S',
        'A/c XX3344 credited Rs. 1,200.00 on 01-07-2026. -Indian Bank',
      );
      expect(credit.transaction!.isCredit, isTrue);
      expect(credit.transaction!.amount, 1200);
    });
  });

  group('PNB deepen', () {
    test('a/c no is debited for Rs', () {
      final r = _parse(
        'VM-PNBSMS-S',
        'Dear Customer, a/c no XX4720 is debited for Rs 450.00 on 12-07-26 thru UPI Ref ID 123456789012. Aval Bal Rs.1,200.00-PNB',
      );
      expect(r.isParsed, isTrue);
      expect(r.transaction!.bank, 'PNB');
      expect(r.transaction!.amount, 450);
      expect(r.transaction!.maskedAccount, contains('4720'));
      expect(r.transaction!.isCredit, isFalse);
    });

    test('a/c no is credited by Rs', () {
      final r = _parse(
        'VM-PNBSMS-S',
        'Dear Customer, a/c no XX4720 is credited by Rs 2,000.00 on 12-07-26 IMPS Ref 999. Aval Bal Rs.3,200.00-PNB',
      );
      expect(r.isParsed, isTrue);
      expect(r.transaction!.isCredit, isTrue);
      expect(r.transaction!.amount, 2000);
    });

    test('Rs debited from a/c no', () {
      final r = _parse(
        'AX-PNBSMS-S',
        'Rs.99.00 debited from a/c no XXXXXXXX4720 on 12-07-26. UPI Ref 111. Aval Bal Rs.100.00-PNB',
      );
      expect(r.isParsed, isTrue);
      expect(r.transaction!.amount, 99);
      expect(r.transaction!.maskedAccount, contains('4720'));
    });
  });

  group('IndusInd deepen', () {
    test('Card spend with Avl Lmt', () {
      final r = _parse(
        'VM-INDUSB-S',
        'INR 499.00 spent on IndusInd Card XX4821 on 14-06-2026 04:21:45 pm at INSTAMART. Avl Lmt: INR 45000.00. To dispute, call 18602677777',
      );
      expect(r.isParsed, isTrue);
      expect(r.transaction!.bank, 'IndusInd');
      expect(r.transaction!.amount, 499);
      expect(r.transaction!.maskedAccount, contains('4821'));
      expect(r.transaction!.merchant.toLowerCase(), contains('instamart'));
    });

    test('savings debit Avl Bal', () {
      final r = _parse(
        'VM-INDUSB-S',
        'INR 600.00 debited from your A/c XX9911 on 12-07-26 via UPI. Avl Bal: INR 8,400.00 -IndusInd Bank',
      );
      expect(r.isParsed, isTrue);
      expect(r.transaction!.isCredit, isFalse);
      expect(r.transaction!.amount, 600);
      expect(r.transaction!.maskedAccount, contains('9911'));
    });

    test('savings credit Avl Bal', () {
      final r = _parse(
        'VM-INDUSB-S',
        'INR 1,500.00 credited to your A/c XX9911 on 12-07-26. Avl Bal: INR 9,900.00 -IndusInd Bank',
      );
      expect(r.isParsed, isTrue);
      expect(r.transaction!.isCredit, isTrue);
      expect(r.transaction!.amount, 1500);
    });

    test('discovery finds IndusInd Card as credit card', () {
      final d = AccountDiscovery.discover(
        sender: 'VM-INDUSB-S',
        body:
            'INR 499.00 spent on IndusInd Card XX4821 on 14-06-2026 04:21:45 pm at INSTAMART. Avl Lmt: INR 45000.00.',
      );
      expect(d?.bank, 'IndusInd');
      expect(d?.kind, AccountKind.creditCard);
      expect(d?.mask, contains('4821'));
    });
  });
}
