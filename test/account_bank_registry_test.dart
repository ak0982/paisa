import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/services/sms/account_bank_registry.dart';
import 'package:paisa_app/services/sms/parsed_sms_transaction.dart';
import 'package:paisa_app/services/sms/sms_parser.dart';

void main() {
  group('AccountBankRegistry', () {
    test('learns SBI from UPI debit on X0429', () {
      final registry = AccountBankRegistry();
      registry.learn(
        'JK-SBIUPI-S',
        'Dear UPI user A/C X0429 debited by 3250.00 on date 04Jun26 trf to INNOFIN SOLUTION Refno 726571152867 If not u? call-1800111109 for other services-18001234-SBI',
      );
      expect(registry.lookup('0429'), 'SBI');
    });

    test('maps ICICI LenDenClub relay credit to learned SBI account', () {
      final registry = AccountBankRegistry();
      registry.learn(
        'JK-SBIUPI-S',
        'Dear UPI user A/C X0429 debited by 3250.00 on date 04Jun26 trf to INNOFIN SOLUTION Refno 726571152867 If not u? call-1800111109 for other services-18001234-SBI',
      );
      registry.learn(
        'VM-SBIINB-S',
        'Dear Customer, Your a/c no. XXXXXXXX0429 is credited by Rs.19882.00 on 10-09-25 by a/c linked to mobile 7XXXXXX060-AK INFOPARK PRIVATE (IMPS Ref no 525319289666).If not done by you, call 1800111109. -SBI',
      );

      final parsed = SmsParser.parseTransaction(
        SmsMessageInput(
          id: 'icici-lenden',
          sender: 'JD-ICICIT-S',
          body:
              'Dear  BELI  DEVI ,Your account  XXXXXXXX0429  has been credited with amount  2948.45 .Reference no-  CMS5760782566 .Thanks,  LENDENCLUB BORROWER REPAYMENT ISP LTD ACCOUNT',
          timestamp: DateTime(2026, 6, 4),
        ),
        registry: registry,
      );

      expect(parsed, isNotNull);
      expect(parsed!.bank, 'SBI');
      expect(parsed.maskedAccount, '••••0429');
      expect(parsed.amount, 2948.45);
    });

    test('detects SBI from NEFT credit footer', () {
      final registry = AccountBankRegistry();
      registry.learn(
        'AX-SBIPSG-S',
        'Dear Customer, INR 2,782.61 credited to your A/c No XX0429 on 22/05/2026 through NEFT with UTR IN22614203717040 by LENDENCLUB BORROWER REPAYMENT ISP LTD ACCOUNT, INFO: BATCHID:0038 LENDENCLUB BORROWER REPAYMENT ISP L TD ACCOUNT-SBI',
      );
      expect(registry.lookup('0429'), 'SBI');
    });
  });
}
