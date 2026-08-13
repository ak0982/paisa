import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/services/sms/account_discovery.dart';
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

  group('evidence-based parser fixes (schema 33)', () {
    test('HDFC Spent On Bank Card parses CC spend with paise', () {
      const body =
          'Spent Rs.3035.4 On HDFC Bank Card 1949 At AIIMSOTHCRCARD On 2026-08-03:01:12:32.Not You? To Block+Reissue Call 18002586161/SMS BLOCK CC 1949 to 7308080808';
      final result = SmsScanPipeline.process(
        SmsMessageInput(
          id: 'hdfc-on',
          sender: 'AD-HDFCBK-S',
          body: body,
          timestamp: DateTime(2026, 8, 3),
        ),
      );
      expect(result.outcome, SmsPipelineOutcome.parsed);
      expect(result.transaction!.amount, 3035.4);
      expect(result.transaction!.isCredit, isFalse);
      expect(result.transaction!.maskedAccount, '••••1949');
      expect(result.transaction!.bank, 'HDFC');
    });

    test('HDFC Spent From Bank Card BLOCK DC is debit not CC', () {
      const body =
          'Spent Rs.31250 From HDFC Bank Card x3569 At CCBBPSNO On 2026-08-01:06:02:24 Bal Rs.55551.08 Not You? Call 18002586161/SMS BLOCK DC  3569 to 7308080808';
      final result = SmsScanPipeline.process(
        SmsMessageInput(
          id: 'hdfc-from',
          sender: 'JX-HDFCBK-S',
          body: body,
          timestamp: DateTime(2026, 8, 1),
        ),
      );
      expect(result.outcome, SmsPipelineOutcome.parsed);
      expect(result.transaction!.amount, 31250);
      expect(result.transaction!.maskedAccount, '••••3569');
      expect(
        TransactionEnrichment.looksLikeCreditCardTransaction(body.toLowerCase()),
        isFalse,
      );
    });

    test('ICICI cashback without mask parses credit', () {
      const body =
          'Congrats! Rs 134.09 cashback credited to ICICI Bank Credit Card on 16-Jul-26. For details check Card statement';
      final result = SmsScanPipeline.process(
        SmsMessageInput(
          id: 'icici-cb',
          sender: 'JD-ICICIT-S',
          body: body,
          timestamp: DateTime(2026, 7, 16),
        ),
      );
      expect(result.outcome, SmsPipelineOutcome.parsed);
      expect(result.transaction!.amount, 134.09);
      expect(result.transaction!.isCredit, isTrue);
    });

    test('ICICI merchant-prefix refund with your parses', () {
      const body =
          'app mpp juspay refund of Rs 1,715.36 credited to your ICICI Bank Credit Card XX0003 on 18-JUN-26.';
      final result = SmsScanPipeline.process(
        SmsMessageInput(
          id: 'icici-ref',
          sender: 'AX-ICICIT-S',
          body: body,
          timestamp: DateTime(2026, 6, 18),
        ),
      );
      expect(result.outcome, SmsPipelineOutcome.parsed);
      expect(result.transaction!.amount, 1715.36);
      expect(result.transaction!.isCredit, isTrue);
      expect(result.transaction!.maskedAccount, '••••0003');
    });

    test('SBI CC reversal/cashback and e-mandate parse', () {
      final reversal = SmsScanPipeline.process(
        SmsMessageInput(
          id: 'sbi-rev',
          sender: 'JM-SBICGV-S',
          body:
              'Rs. 1655.36 has been credited to your SBI Credit Card xxxx3452, towards reversal/cashback from PNB*IRCTC Ticketing Gurgaon IND for trxn. dated 02/08/2026',
          timestamp: DateTime(2026, 8, 2),
        ),
      );
      expect(reversal.transaction!.amount, 1655.36);
      expect(reversal.transaction!.isCredit, isTrue);
      expect(reversal.transaction!.maskedAccount, '••••3452');

      final mandate = SmsScanPipeline.process(
        SmsMessageInput(
          id: 'sbi-em',
          sender: 'VA-SBICRD-S',
          body:
              'Transaction of Rs.2,340.58 at CURSORAIPOWEREDIDE against E-mandate (SiHub ID - YX9dLE6YW2) registered by you at merchant has been debited to your SBI Credit Card ending 3452 on 07-07-26.',
          timestamp: DateTime(2026, 7, 7),
        ),
      );
      expect(mandate.transaction!.amount, 2340.58);
      expect(mandate.transaction!.isCredit, isFalse);
      expect(mandate.transaction!.maskedAccount, '••••3452');
    });

    test('IDFC interest INR.4.00 and Kotak CC spend parse', () {
      final interest = SmsScanPipeline.process(
        SmsMessageInput(
          id: 'idfc-int',
          sender: 'VM-IDFCFB-S',
          body:
              'Monthly interest of INR.4.00 earned on your Savings A/c XX0070 has been credited to your A/C on 31/07/26. New bal: INR.1,843.18. IDFC FIRST Bank',
          timestamp: DateTime(2026, 7, 31),
        ),
      );
      expect(interest.transaction!.amount, 4.00);
      expect(interest.transaction!.isCredit, isTrue);
      expect(interest.transaction!.maskedAccount, '••••0070');

      final kotak = SmsScanPipeline.process(
        SmsMessageInput(
          id: 'kotak-cc',
          sender: 'AD-KOTAKB-S',
          body:
              'INR 282 spent on Kotak Credit Card x4310 on 02-Aug-2026 at SWIGGY PVT LTD FOOD2. Avl limit INR 451718 Fraud? https://www.kotak.bank.in/KBANKT/querytxn',
          timestamp: DateTime(2026, 8, 2),
        ),
      );
      expect(kotak.transaction!.amount, 282);
      expect(kotak.transaction!.isCredit, isFalse);
      expect(kotak.transaction!.maskedAccount, '••••4310');
    });

    test('LenDenClub leading-dot amount .85 parses as 0.85; empty dot does not', () {
      final parsed = SmsScanPipeline.process(
        SmsMessageInput(
          id: 'ld-dot',
          sender: 'JD-ICICIT-S',
          body:
              'Dear TEST USER ,Your account XXXXXXXX0856 has been credited with amount .85 .Reference no- CMS5807350098 .Thanks, LENDENCLUB BORROWER REPAYMENT ISP LTD ACCOUNT',
          timestamp: DateTime(2026, 8, 3),
        ),
      );
      expect(parsed.outcome, SmsPipelineOutcome.parsed);
      expect(parsed.transaction!.amount, 0.85);
      expect(parsed.transaction!.maskedAccount, '••••0856');

      final empty = SmsScanPipeline.process(
        SmsMessageInput(
          id: 'ld-empty',
          sender: 'JD-ICICIT-S',
          body:
              'Dear TEST USER ,Your account XXXXXXXX0856 has been credited with amount . .Reference no- CMS5807350098 .Thanks, LENDENCLUB BORROWER REPAYMENT ISP LTD ACCOUNT',
          timestamp: DateTime(2026, 8, 3),
        ),
      );
      expect(empty.isParsed, isFalse);
    });

    test('ICICI Account XX credited:Rs. CMS credit parses', () {
      const body =
          'ICICI Bank Account XX1505 credited:Rs. 60,775.86 on 07-May-26. Info CMS* CC RBI 10 H*ICICI BANK . Available Balance is Rs. 74,202.07.';
      final result = SmsScanPipeline.process(
        SmsMessageInput(
          id: 'icici-cms',
          sender: 'VA-ICICIT-S',
          body: body,
          timestamp: DateTime(2026, 5, 7),
        ),
      );
      expect(result.outcome, SmsPipelineOutcome.parsed);
      expect(result.transaction!.amount, 60775.86);
      expect(result.transaction!.isCredit, isTrue);
      expect(result.transaction!.maskedAccount, '••••1505');
    });

    test('ICICI 3-digit XX505 CMS credit is not invented as an account', () {
      const body =
          'ICICI Bank Account XX505 credited:Rs. 60,775.86 on 07-May-26. Info CMS* CC RBI 10 H*ICICI BANK . Available Balance is Rs. 74,202.07.';
      final result = SmsScanPipeline.process(
        SmsMessageInput(
          id: 'icici-cms-3',
          sender: 'VA-ICICIT-S',
          body: body,
          timestamp: DateTime(2026, 5, 7),
        ),
      );
      expect(result.isParsed, isFalse);
      expect(
        AccountDiscovery.discover(sender: 'VA-ICICIT-S', body: body)?.mask,
        isNot(equals('••••0505')),
      );
    });

    test('ICICI CC refund transferred to savings XX1505 parses', () {
      const body =
          'Refund of Rs 1,715.36 from ICICI Bank Credit Card XX0003 to Savings Account XX1505 has been successfully transferred.';
      final result = SmsScanPipeline.process(
        SmsMessageInput(
          id: 'icici-sav-ref',
          sender: 'AD-ICICIT-S',
          body: body,
          timestamp: DateTime(2026, 8, 1),
        ),
      );
      expect(result.outcome, SmsPipelineOutcome.parsed, reason: body);
      expect(result.transaction!.amount, 1715.36);
      expect(result.transaction!.isCredit, isTrue);
      expect(result.transaction!.maskedAccount, '••••1505');
      expect(result.transaction!.bank, 'ICICI');
      expect(
        TransactionEnrichment.resolveAccountKind(
          bank: 'ICICI',
          mask: '••••1505',
          body: body,
          discoveries: const [],
        ),
        AccountKind.savings,
      );
      final d = AccountDiscovery.discover(sender: 'AD-ICICIT-S', body: body);
      expect(d, isNotNull);
      expect(d!.kind, AccountKind.savings);
      expect(d.mask, '••••1505');
    });

    test('HDFC ALERT spent via Debit Card CCBBPSNO is savings not CC', () {
      const body =
          'ALERT:Rs.31250.00 spent via HDFC BANK Debit Card xx3569 at CCBBPSNO on Aug 1 2026 6:02AM without PIN/OTP.Not you?Call 18002586161 / 18002586161.';
      final result = SmsScanPipeline.process(
        SmsMessageInput(
          id: 'hdfc-dc-alert',
          sender: 'AD-HDFCBK-S',
          body: body,
          timestamp: DateTime(2026, 8, 1),
        ),
      );
      expect(result.outcome, SmsPipelineOutcome.parsed, reason: body);
      expect(result.transaction!.amount, 31250);
      expect(result.transaction!.isCredit, isFalse);
      expect(result.transaction!.maskedAccount, '••••3569');
      expect(
        TransactionEnrichment.looksLikeDebitCardSpend(body.toLowerCase()),
        isTrue,
      );
      expect(
        TransactionEnrichment.looksLikeCreditCardTransaction(body.toLowerCase()),
        isFalse,
      );
      expect(
        TransactionEnrichment.resolveAccountKind(
          bank: 'HDFC',
          mask: '••••3569',
          body: body,
          discoveries: const [],
        ),
        AccountKind.savings,
      );
      final d = AccountDiscovery.discover(sender: 'AD-HDFCBK-S', body: body);
      expect(d, isNotNull);
      expect(d!.kind, AccountKind.savings);
      expect(d.mask, '••••3569');
    });

    test('HDFC Spent From Bank Card CCBBPSNO BLOCK DC kind is savings', () {
      const body =
          'Spent Rs.31250 From HDFC Bank Card x3569 At CCBBPSNO On 2026-08-01:06:02:24 Bal Rs.55551.08 Not You? Call 18002586161/SMS BLOCK DC  3569 to 7308080808';
      expect(
        TransactionEnrichment.resolveAccountKind(
          bank: 'HDFC',
          mask: '••••3569',
          body: body,
          discoveries: const [],
        ),
        AccountKind.savings,
      );
      expect(
        TransactionEnrichment.looksLikeCreditCardTransaction(body.toLowerCase()),
        isFalse,
      );
    });

    test('HDFC Rs spent on Bank Card CCBBPSNO BLOCK DC kind is savings', () {
      const body =
          'Rs.1365 spent on HDFC Bank Card x3569 at CCBBPSNO on 2026-08-01:06:02:24 Avl bal: 55551.0.Not You? Call 18002586161 / SMS BLOCK DC 3569 to 7308080808';
      final result = SmsScanPipeline.process(
        SmsMessageInput(
          id: 'hdfc-spent-on-dc',
          sender: 'AD-HDFCBK-S',
          body: body,
          timestamp: DateTime(2026, 8, 1),
        ),
      );
      expect(result.outcome, SmsPipelineOutcome.parsed, reason: body);
      expect(result.transaction!.maskedAccount, '••••3569');
      expect(
        TransactionEnrichment.resolveAccountKind(
          bank: 'HDFC',
          mask: '••••3569',
          body: body,
          discoveries: const [],
        ),
        AccountKind.savings,
      );
    });

    test('SmartPay Bill Paid receipt is not a transaction', () {
      final result = SmsScanPipeline.process(
        SmsMessageInput(
          id: 'bill-paid',
          sender: 'JM-HDFCBK-S',
          body:
              'Bill Paid: HSBCBankCC Bill 3740 of Rs. 11254.82 paid on 07-Aug-26 via SmartPay. From HDFC Bank.',
          timestamp: DateTime(2026, 8, 7),
        ),
      );
      expect(result.isParsed, isFalse);
      expect(
        result.outcome,
        anyOf(
          SmsPipelineOutcome.noTransactionSignal,
          SmsPipelineOutcome.parseFailed,
          SmsPipelineOutcome.promo,
        ),
      );
    });

    test('EMI due reminder and SmartPay failed debit do not parse', () {
      final due = SmsScanPipeline.process(
        SmsMessageInput(
          id: 'emi-due',
          sender: 'JX-ICICIT-S',
          body:
              'EMI of Rs 26408.00 for ICICI Bank Personal Loan XX1041 is due on 05-Aug-26. Please maintain sufficient funds in your linked Account XX3649 to avoid 5% per annum penal charges. EMI will be debited on holidays too.',
          timestamp: DateTime(2026, 8, 5),
        ),
      );
      expect(due.isParsed, isFalse);

      final smart = SmsScanPipeline.process(
        SmsMessageInput(
          id: 'smartpay',
          sender: 'JM-HDFCBK-S',
          body:
              "SmartPay Alert: IDFCBankCC Bill 6204969301 can't be auto debited as HDFC Bank received a bill of Rs. 0.00. Please pay via alternate method.",
          timestamp: DateTime(2026, 8, 1),
        ),
      );
      expect(smart.isParsed, isFalse);
    });
  });
}
