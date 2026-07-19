import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/services/sms/parsed_sms_transaction.dart';
import 'package:paisa_app/services/sms/sms_parser.dart';
import 'package:paisa_app/services/sms/sms_scan_pipeline.dart';

void main() {
  SmsMessageInput msg({
    required String id,
    required String sender,
    required String body,
  }) {
    return SmsMessageInput(
      id: id,
      sender: sender,
      body: body,
      timestamp: DateTime(2024, 10, 11),
    );
  }

  group('scam and promo loan offers', () {
    test('blocks Rs 542000 loan approval scam from personal number', () {
      const body =
          'Congrats, Y0UR Received Rs.542000 L0AN is Approve on 11-10-2O24. '
          'Zero document. Withdraw direct T0 Y0UR A/c. SR3.in/O25i64i-1i71D85i15i5';
      expect(
        SmsParser.isPromoOrOfferSms(body, sender: '+918780671098'),
        isTrue,
      );
      expect(
        SmsParser.isRealTransactionSms('+918780671098', body),
        isFalse,
      );
      expect(
        SmsScanPipeline.process(msg(
          id: 'scam1',
          sender: '+918780671098',
          body: body,
        )).isParsed,
        isFalse,
      );
    });

    test('blocks wallet phishing Finance Guru SMS', () {
      const body =
          'Dear Consumer, Received Rs.15,000 to your Wallet A/c Click to check now '
          'http://Kx7.in/FINGUR/aS9Vzm Finance Guru';
      expect(SmsParser.isPromoOrOfferSms(body, sender: 'VM-FINGUR'), isTrue);
      expect(SmsScanPipeline.process(msg(
        id: 'scam2',
        sender: 'VM-FINGUR',
        body: body,
      )).isParsed, isFalse);
    });

    test('blocks Vi talktime recharge as income', () {
      const body =
          "Rs20 recharged! You've received Rs14.95 Talktime. GST:18%. "
          'PF:Rs 2. Your new Main Balance: Rs16.40.';
      expect(SmsParser.isPromoOrOfferSms(body, sender: 'VB-ViCARE'), isTrue);
      expect(SmsScanPipeline.process(msg(
        id: 'vi',
        sender: 'VB-ViCARE',
        body: body,
      )).isParsed, isFalse);
    });

    test('parses wallet platform top-up as transaction', () {
      const body =
          'Dear BELI, Rs. 2500.00 has been credited to your LenDenClub account. '
          'The amount is available for lending. -LenDenClub';
      expect(SmsParser.isNonBankWalletMovement(body), isFalse);
      expect(SmsParser.isRealTransactionSms('JK-LENDEN-S', body), isTrue);
      expect(SmsScanPipeline.process(msg(
        id: 'wallet',
        sender: 'JK-LENDEN-S',
        body: body,
      )).isParsed, isTrue);
    });

    test('blocks phishing credited-to-wallet scam', () {
      const body =
          'Dear Consumer, Received Rs.15,000 credited to your wallet a/c Click now http://evil.example';
      expect(SmsParser.isNonBankWalletMovement(body), isTrue);
    });

    test('blocks Kotak pre-approved loan promo', () {
      const body =
          'Dear Amar, you are pre-approved for Rs. 1,25,000 Get instant Kotak '
          'Personal Loan with 0 paperwork. Tap now: https://1.kmbl.in/KOTAKB/UPkfzw T&C';
      expect(SmsParser.isPromoOrOfferSms(body, sender: 'TX-KOTAKB-P'), isTrue);
    });

    test('allows real Kotak UPI credit', () {
      const body =
          'Received Rs.49000.00 in your Kotak Bank AC X3649 from 6204969301@amazonpay '
          'on 12-02-25.UPI Ref:504306956917.';
      expect(SmsParser.isRealTransactionSms('VM-KOTAKB', body), isTrue);
      final parsed = SmsScanPipeline.process(msg(
        id: 'real1',
        sender: 'VM-KOTAKB',
        body: body,
      ));
      expect(parsed.isParsed, isTrue);
      expect(parsed.transaction?.amount, 49000);
      expect(parsed.transaction?.isCredit, isTrue);
    });

    test('allows real debit after promo keyword in completed txn', () {
      const body =
          'INR 25,797.00 is debited to your Account XXXXXX3649 on 07/12/2025 '
          'towards NACH-10-HDFC BANK LIMITED Kotak Bank';
      expect(SmsParser.isRealTransactionSms('VM-KOTAKB-S', body), isTrue);
      final parsed = SmsScanPipeline.process(msg(
        id: 'real2',
        sender: 'VM-KOTAKB-S',
        body: body,
      ));
      expect(parsed.isParsed, isTrue);
      expect(parsed.transaction?.amount, 25797);
    });
  });
}
