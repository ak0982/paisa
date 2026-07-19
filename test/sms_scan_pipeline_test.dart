import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/services/sms/parsed_sms_transaction.dart';
import 'package:paisa_app/services/sms/sms_scan_pipeline.dart';

void main() {
  group('SmsScanPipeline', () {
    test('stage 1 rejects personal chat instantly', () {
      expect(
        SmsScanPipeline.isFinancialSender('FRIEND'),
        isFalse,
      );
      expect(
        SmsScanPipeline.process(_msg(
          sender: 'FRIEND',
          body: 'Hey, are we meeting for lunch tomorrow at 1pm?',
        )).outcome,
        SmsPipelineOutcome.notFinancialSender,
      );
    });

    test('stage 1 accepts bank sender without body regex', () {
      expect(SmsScanPipeline.isFinancialSender('VM-HDFCBK'), isTrue);
      expect(SmsScanPipeline.isFinancialSender('SBIINB'), isTrue);
    });

    test('stage 2 accepts generic sender with txn body hint', () {
      expect(
        SmsScanPipeline.hasFinancialBodyHint(
          'Rs.500.00 debited from your account on 07-Jul. Info: SWIGGY',
        ),
        isTrue,
      );
    });

    test('stage 3 rejects promo after bank gate', () {
      final result = SmsScanPipeline.process(_msg(
        sender: 'VM-HDFCBK',
        body:
            'Dear Customer, convert your spends to SmartEMI on HDFC Bank '
            'Credit Card. Enjoy easy repayment on Rs.25,000. T&C apply.',
      ));
      expect(result.outcome, SmsPipelineOutcome.promo);
      expect(result.transaction, isNull);
    });

    test('stage 5 parses real debit after all gates', () {
      final result = SmsScanPipeline.process(_msg(
        sender: 'VM-HDFCBK',
        body:
            'Sent Rs.486.00 from a/c **4321 to Swiggy on 07-Jul-26 UPI ref 5521.',
      ));
      expect(result.outcome, SmsPipelineOutcome.parsed);
      expect(result.transaction?.amount, 486);
      expect(result.transaction?.merchant, 'Swiggy');
    });

    test('rejects OTP-only bank SMS', () {
      final result = SmsScanPipeline.process(_msg(
        sender: 'HDFCBK',
        body: 'Your OTP for login is 482910. Do not share with anyone.',
      ));
      expect(result.outcome, SmsPipelineOutcome.otpOnly);
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
