import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/services/sms/parsed_sms_transaction.dart';
import 'package:paisa_app/services/sms/sms_parser.dart';
import 'package:paisa_app/services/sms/sms_scan_pipeline.dart';
import 'package:paisa_app/services/sms/transaction_enrichment.dart';

/// Anonymized templates taken from the offline analysis DB
/// (`paisa_sms_analysis.db` / Redmi dump) — no real personal data.
void main() {
  group('evidence-based parser fixes (schema 24)', () {
    test('HSBC creditcard used-at parses via pipeline', () {
      const body =
          'HSBC creditcard xxxxx3740 used at zepto marketplace private for INR 9975.00 on 28/07/26.Limit Rs 826770.18 Due Rs 21229.82.Report fraud on +910000000000';
      final result = SmsScanPipeline.process(
        SmsMessageInput(
          id: '1',
          sender: 'JM-HSBCIN-S',
          body: body,
          timestamp: DateTime(2026, 7, 28),
        ),
      );
      expect(result.outcome, SmsPipelineOutcome.parsed);
      expect(result.transaction!.bank, 'HSBC');
      expect(result.transaction!.amount, 9975.0);
      expect(result.transaction!.isCredit, isFalse);
      expect(result.transaction!.maskedAccount, contains('3740'));
      expect(
        TransactionEnrichment.looksLikeCreditCardTransaction(body.toLowerCase()),
        isTrue,
      );
    });

    test('HSBC CBDT merchant with digits still parses', () {
      const body =
          'HSBC creditcard xxxxx3740 used at cbdt tin 2 0 for INR 145460.30 on 31/07/26.Limit Rs 682316.88 Due Rs 165683.12.Report fraud on +910000000000';
      final parsed = SmsParser.parseTransaction(
        SmsMessageInput(
          id: '2',
          sender: 'JM-HSBCIN-S',
          body: body,
          timestamp: DateTime(2026, 7, 31),
        ),
      );
      expect(parsed, isNotNull);
      expect(parsed!.amount, 145460.30);
      expect(parsed.merchant.toLowerCase(), contains('cbdt'));
    });

    test('HSBC statement due is not a transaction', () {
      const body =
          'HSBC Credit Card ending 3740 : Total due: 11254.82, minimum due: 1000.00; pay by 05-Aug-26. Payment modes- https://example.com';
      final result = SmsScanPipeline.process(
        SmsMessageInput(
          id: '3',
          sender: 'JM-HSBCIN-S',
          body: body,
          timestamp: DateTime(2026, 8, 1),
        ),
      );
      expect(result.isParsed, isFalse);
    });

    test('ICICI USD card spend parses', () {
      const body =
          'USD 23.60 spent using ICICI Bank Card XX2009 on 30-Jul-26 on ANTHROPIC* CLAU. Avl Limit: INR 4,39,259.33. If not you, call 1800 2662/SMS BLOCK 2009 to 9215676766.';
      final result = SmsScanPipeline.process(
        SmsMessageInput(
          id: '4',
          sender: 'JX-ICICIT-S',
          body: body,
          timestamp: DateTime(2026, 7, 30),
        ),
      );
      expect(result.outcome, SmsPipelineOutcome.parsed);
      expect(result.transaction!.bank, 'ICICI');
      expect(result.transaction!.amount, 23.60);
      expect(result.transaction!.maskedAccount, contains('2009'));
    });

    test('ICICI CC refund credit parses', () {
      const body =
          'IRCTC Rail APP refund of Rs 80.36 credited to ICICI Bank Credit Card XX0003 on 29-JUL-26. Revised total due Rs 21,340.81, minimum due Rs 988.31';
      final result = SmsScanPipeline.process(
        SmsMessageInput(
          id: '5',
          sender: 'AD-ICICIT-S',
          body: body,
          timestamp: DateTime(2026, 7, 29),
        ),
      );
      expect(result.outcome, SmsPipelineOutcome.parsed);
      expect(result.transaction!.isCredit, isTrue);
      expect(result.transaction!.amount, 80.36);
    });

    test('Axis cashback credit parses', () {
      const body =
          "Congratulations! Cashback of INR 83 has been credited to your Axis Bank Flipkart Visa Credit Card XX8341 towards your last month spends - Axis Bank";
      final result = SmsScanPipeline.process(
        SmsMessageInput(
          id: '6',
          sender: 'VK-AXISBK-S',
          body: body,
          timestamp: DateTime(2026, 7, 15),
        ),
      );
      expect(result.outcome, SmsPipelineOutcome.parsed);
      expect(result.transaction!.isCredit, isTrue);
      expect(result.transaction!.amount, 83.0);
      expect(result.transaction!.maskedAccount, contains('8341'));
    });

    test('Axis payment-due reminder is not a transaction', () {
      const body =
          'Payment of INR 3246 for Axis Bank Credit Card no. XX9867 is due on 01-08-26 with minimum amount due of INR 100. Ignore if paid.';
      final result = SmsScanPipeline.process(
        SmsMessageInput(
          id: '7',
          sender: 'JK-AXISBK-S',
          body: body,
          timestamp: DateTime(2026, 7, 28),
        ),
      );
      expect(result.isParsed, isFalse);
    });

    test('Axis live multiline Card no. spend parses', () {
      const body =
          'Spent INR 663\nAxis Bank Card no. XX8341\n10-12-25 20:42:01 IST\nMYNTRA\nAvl Limit: INR 96568.75\nNot you? SMS BLOCK 8341 to 919951860002';
      final result = SmsScanPipeline.process(
        SmsMessageInput(
          id: '8',
          sender: 'JK-AXISBK-S',
          body: body,
          timestamp: DateTime(2025, 12, 10),
        ),
      );
      expect(result.outcome, SmsPipelineOutcome.parsed);
      expect(result.transaction!.bank, 'Axis');
      expect(result.transaction!.amount, 663.0);
      expect(result.transaction!.isCredit, isFalse);
      expect(result.transaction!.maskedAccount, contains('8341'));
      expect(result.transaction!.merchant.toUpperCase(), contains('MYNTRA'));
      expect(
        TransactionEnrichment.looksLikeCreditCardTransaction(body.toLowerCase()),
        isTrue,
      );
    });
  });
}
