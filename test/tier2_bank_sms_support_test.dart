import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/services/sms/account_bank_registry.dart';
import 'package:paisa_app/services/sms/account_discovery.dart';
import 'package:paisa_app/services/sms/parsed_sms_transaction.dart';
import 'package:paisa_app/services/sms/sms_parser.dart';
import 'package:paisa_app/services/sms/sms_scan_pipeline.dart';

SmsPipelineResult _parse(String sender, String body) {
  return SmsScanPipeline.process(
    SmsMessageInput(
      id: 't2_${sender.hashCode}_${body.hashCode}',
      sender: sender,
      body: body,
      timestamp: DateTime(2026, 7, 12),
    ),
  );
}

void main() {
  group('Tier-2 DLT sender mapping', () {
    test('BDNSMS / IDBIBK / AUBANK / EQUTAS map correctly', () {
      expect(SmsParser.isFinancialSender('XY-BDNSMS-S'), isTrue);
      expect(SmsParser.isFinancialSender('VM-IDBIBK-S'), isTrue);
      expect(SmsParser.isFinancialSender('VM-AUBANK'), isTrue);
      expect(SmsParser.isFinancialSender('CP-EQUTAS-S'), isTrue);
      expect(SmsScanPipeline.isFinancialSender('VM-SIBSMS-S'), isTrue);
    });

    test('SIBSMS maps to South Indian Bank (not SBI substring)', () {
      final r = _parse(
        'VM-SIBSMS-S',
        'UPI debit:Rs.250.50 in A/c X2468. Info:UPI/ICIC/222333444555/Demo Merchant on 26-12-25 19:05:01. Final balance is Rs.34317.17 -South Indian Bank',
      );
      expect(r.isParsed, isTrue);
      expect(r.transaction!.bank, 'South Indian Bank');
      expect(r.transaction!.bank, isNot('SBI'));
    });

    test('IPBMSG / CENTBK / KBLBNK map correctly', () {
      expect(SmsParser.isFinancialSender('AX-IPBMSG-S'), isTrue);
      expect(SmsParser.isFinancialSender('JD-CENTBK-S'), isTrue);
      expect(SmsParser.isFinancialSender('VM-KBLBNK-S'), isTrue);
    });
  });

  group('Bandhan', () {
    test('UPI debit from A/c towards UPI/DR', () {
      final r = _parse(
        'XY-BDNSMS-S',
        'INR 180.00 debited from A/c XXXXXXXXXX1234 towards UPI/DR/D123013240123/Amazon Pa Value 16-NOV-2025 . Clear Bal is INR 9999.99. Bandhan Bank',
      );
      expect(r.isParsed, isTrue);
      expect(r.transaction!.bank, 'Bandhan');
      expect(r.transaction!.amount, 180);
      expect(r.transaction!.isCredit, isFalse);
      expect(r.transaction!.maskedAccount, contains('1234'));
      expect(r.transaction!.merchant.toLowerCase(), contains('amazon'));
    });

    test('UPI deposit credit', () {
      final r = _parse(
        'XY-BDNSMS-S',
        'INR 25,000.00 deposited to A/c XXXXXXXXXX1234 towards UPI/CR/C224513287910/JOHN DOE/u on 03-OCT-2025 . Clear Bal is INR 30,123.00 . Bandhan Bank.',
      );
      expect(r.isParsed, isTrue);
      expect(r.transaction!.isCredit, isTrue);
      expect(r.transaction!.amount, 25000);
      expect(r.transaction!.maskedAccount, contains('1234'));
    });

    test('discovery finds Bandhan savings', () {
      final d = AccountDiscovery.discover(
        sender: 'XY-BDNSMS-S',
        body:
            'INR 180.00 debited from A/c XXXXXXXXXX1234 towards UPI/DR/D123013240123/Amazon Pa Value 16-NOV-2025 . Clear Bal is INR 9999.99. Bandhan Bank',
      );
      expect(d?.bank, 'Bandhan');
      expect(d?.mask, contains('1234'));
      expect(d?.kind, AccountKind.savings);
    });
  });

  group('AU Bank', () {
    test('Debited INR from A/c', () {
      final r = _parse(
        'VM-AUBANK',
        'Debited INR 165.00 from A/c X7013 on 01-MAR-2026 UPI/DR/651122781360/UK FOOD/UTIB/9180201 Bal INR 9000.00 -AU Bank',
      );
      expect(r.isParsed, isTrue);
      expect(r.transaction!.bank, 'AU Bank');
      expect(r.transaction!.amount, 165);
      expect(r.transaction!.maskedAccount, contains('7013'));
    });

    test('Dr / Cr compact forms', () {
      final debit = _parse(
        'VM-AUBANK-S',
        'Dr INR 29,000.00 from A/c X7661 on 05-MAY-2026 UPI/DR/012345678901/Bank Account XXXXX Bal INR 10,952.10 -AU Bank',
      );
      expect(debit.transaction!.amount, 29000);
      expect(debit.transaction!.isCredit, isFalse);

      final credit = _parse(
        'VM-AUBANK-S',
        'Cr INR 5,000.00 to A/c X4541 12-MAY-2026 UPI/CR/424941009999/JANE DOE/Y Bal INR 23,838.10 -AU Bank',
      );
      expect(credit.transaction!.isCredit, isTrue);
      expect(credit.transaction!.amount, 5000);
    });

    test('AU Bank Credit Card spend', () {
      final r = _parse(
        'VM-AUBANK',
        'INR 259.90 spent at TELEGRAM PREMIUM on AU Bank Credit Card x1234 21-03-2026 05:49:40 PM. Not you? Call 180012001500 or SMS PBLOCK 1234 to 5676767',
      );
      expect(r.isParsed, isTrue);
      expect(r.transaction!.bank, 'AU Bank');
      expect(r.transaction!.amount, 259.90);
      expect(r.transaction!.maskedAccount, contains('1234'));
      expect(r.transaction!.merchant.toLowerCase(), contains('telegram'));

      final d = AccountDiscovery.discover(
        sender: 'VM-AUBANK',
        body:
            'INR 259.90 spent at TELEGRAM PREMIUM on AU Bank Credit Card x1234 21-03-2026 05:49:40 PM.',
      );
      expect(d?.kind, AccountKind.creditCard);
      expect(d?.bank, 'AU Bank');
    });
  });

  group('Equitas', () {
    test('UPI debit via Equitas A/c', () {
      final r = _parse(
        'CP-EQUTAS-S',
        'INR 500.00 debited via UPI from Equitas A/c 1234 -Ref:571987071234 on 19-12-25 to JOHN DOE. Avl Bal is INR 15,000.50.Not U?Call 18001031222.',
      );
      expect(r.isParsed, isTrue);
      expect(r.transaction!.bank, 'Equitas');
      expect(r.transaction!.amount, 500);
      expect(r.transaction!.maskedAccount, contains('1234'));
      expect(r.transaction!.merchant.toLowerCase(), contains('john'));
    });

    test('UPI credit via Equitas A/c', () {
      final r = _parse(
        'VM-EQUTAS-S',
        'INR 2,000.00 credited via UPI to Equitas A/c 9012 -Ref:123456789012 on 18-01-26 from EMPLOYER NAME. Avl Bal is INR 25,000.00.Not U?Call 18001031222.',
      );
      expect(r.isParsed, isTrue);
      expect(r.transaction!.isCredit, isTrue);
      expect(r.transaction!.amount, 2000);
      expect(r.transaction!.maskedAccount, contains('9012'));
    });

    test('discovery finds Equitas savings', () {
      final d = AccountDiscovery.discover(
        sender: 'CP-EQUTAS-S',
        body:
            'INR 500.00 debited via UPI from Equitas A/c 1234 -Ref:571987071234 on 19-12-25 to JOHN DOE. Avl Bal is INR 15,000.50.',
      );
      expect(d?.bank, 'Equitas');
      expect(d?.mask, contains('1234'));
    });
  });

  group('IDBI', () {
    test('Acct debited for Rs', () {
      final r = _parse(
        'VM-IDBIBK-S',
        'IDBI Bank Acct XX7788 debited for Rs 1,040.00 on 12-07-26. UPI:521687538121 Bal Rs 3,694.38 -IDBI Bank',
      );
      expect(r.isParsed, isTrue);
      expect(r.transaction!.bank, 'IDBI');
      expect(r.transaction!.amount, 1040);
      expect(r.transaction!.maskedAccount, contains('7788'));
    });

    test('Acct credited with Rs', () {
      final r = _parse(
        'AX-IDBIBK-S',
        'IDBI Bank Acct XX7788 credited with Rs 500.00 on 12-07-26. Bal Rs 4,194.38 -IDBI Bank',
      );
      expect(r.isParsed, isTrue);
      expect(r.transaction!.isCredit, isTrue);
      expect(r.transaction!.amount, 500);
    });
  });

  group('South Indian Bank', () {
    test('IMPS credit Your A/c', () {
      final r = _parse(
        'SIBSMS',
        'Dear Customer, Your A/c X7377 is credited with Rs.792.02 Info: IMPS/FDRL/528005821348/EPIFI ACCOUN. Final balance is Rs.793.02-South Indian Bank',
      );
      expect(r.isParsed, isTrue);
      expect(r.transaction!.bank, 'South Indian Bank');
      expect(r.transaction!.isCredit, isTrue);
      expect(r.transaction!.amount, 792.02);
      expect(r.transaction!.maskedAccount, contains('7377'));
    });

    test('UPI debit and POS DEBIT', () {
      final upi = _parse(
        'VM-SIBSMS-S',
        'UPI debit:Rs.599.00 A/c X7477, 16-10-25 16:25:29 RRN: 565526068910 Bal:Rs.12345.89 Block A/c? Call18004251809-South Indian Bank',
      );
      expect(upi.isParsed, isTrue);
      expect(upi.transaction!.amount, 599);
      expect(upi.transaction!.maskedAccount, contains('7477'));

      final pos = _parse(
        'VM-SIBSMS-S',
        'A/c X7477 DEBIT:Rs.983.75 SPICE KITCHEN MCT Bal:Rs.1234.67 Block A/c? call 18004251809-South Indian Bank',
      );
      expect(pos.isParsed, isTrue);
      expect(pos.transaction!.amount, 983.75);
      expect(pos.transaction!.merchant.toLowerCase(), contains('spice'));
    });

    test('registry learns SIBSMS', () {
      final registry = AccountBankRegistry();
      registry.learn(
        'VM-SIBSMS-S',
        'UPI debit:Rs.599.00 A/c X7477, 16-10-25 Bal:Rs.12345.89 -South Indian Bank',
      );
      expect(registry.lookup('7477'), 'South Indian Bank');
    });
  });

  group('Central Bank', () {
    test('NEFT credited to your A/c … -CBoI', () {
      final r = _parse(
        'JD-CENTBK-S',
        'Rs. 500.00 credited to your A/c xxxxxx1234 on 03/01/2026 through NEFT vide Ref No./XUTR/IN22XX...XX24 By.SAMPLE TECH PRIVATE LIMI-CBoI',
      );
      expect(r.isParsed, isTrue);
      expect(r.transaction!.bank, 'Central Bank');
      expect(r.transaction!.isCredit, isTrue);
      expect(r.transaction!.amount, 500);
      expect(r.transaction!.maskedAccount, contains('1234'));
    });
  });

  group('IPPB', () {
    test('Debit Rs from A/C for UPI', () {
      final r = _parse(
        'AX-IPBMSG-S',
        'Debit Rs.50.00 from A/C X4321 for UPI to samplemart@oksbi. Avl Bal Rs.1,000.00 Ref 560002638161 -IPPB',
      );
      expect(r.isParsed, isTrue);
      expect(r.transaction!.bank, 'IPPB');
      expect(r.transaction!.amount, 50);
      expect(r.transaction!.isCredit, isFalse);
      expect(r.transaction!.maskedAccount, contains('4321'));
    });

    test('received a payment thru IPPB', () {
      final r = _parse(
        'VM-IPBMSG-T',
        'You have received a payment of Rs.200.00 from SAMPLE PAYER thru IPPB. Avl Bal Rs.1,200.00 Info: UPI/CREDIT/523498793035',
      );
      expect(r.isParsed, isTrue);
      expect(r.transaction!.isCredit, isTrue);
      expect(r.transaction!.amount, 200);
      expect(r.transaction!.merchant.toLowerCase(), contains('sample'));
    });
  });

  group('Karnataka Bank', () {
    test('Account has been DEBITED for Rs', () {
      final r = _parse(
        'VM-KBLBNK-S',
        'Your Account x001234x has been DEBITED for Rs.6,368.00/- on 12-07-26. UPI Ref no 441877242175. Balance is Rs.705.92 -Karnataka Bank',
      );
      expect(r.isParsed, isTrue);
      expect(r.transaction!.bank, 'Karnataka Bank');
      expect(r.transaction!.amount, 6368);
      expect(r.transaction!.maskedAccount, contains('1234'));
    });

    test('a/c credited by Rs', () {
      final r = _parse(
        'AX-KTKBANK-S',
        'Your a/c XX1234 is credited by Rs.6,600.00 on 12-07-26. Balance is Rs.7,305.92 -Karnataka Bank',
      );
      expect(r.isParsed, isTrue);
      expect(r.transaction!.isCredit, isTrue);
      expect(r.transaction!.amount, 6600);
    });
  });
}
