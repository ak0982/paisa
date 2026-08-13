import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/services/sms/account_discovery.dart';
import 'package:paisa_app/services/sms/parsed_sms_transaction.dart';
import 'package:paisa_app/services/sms/sms_parser.dart';
import 'package:paisa_app/services/sms/sms_scan_pipeline.dart';
import 'package:paisa_app/utils/bank_assets.dart';

/// Anonymized Slice SFB templates from the offline analysis DB / public samples.
void main() {
  group('Slice Small Finance Bank', () {
    test('UPI debit sent-from parses', () {
      const body =
          'Rs. 550 sent from a/c xx0856 on 18-May-26 to CREW SPORTS (UPI Ref: 650468933013). Not you? Call 08048329999 - slice';
      final result = SmsScanPipeline.process(
        SmsMessageInput(
          id: '1',
          sender: 'AX-SLCEIT-S',
          body: body,
          timestamp: DateTime(2026, 5, 18),
        ),
      );
      expect(result.outcome, SmsPipelineOutcome.parsed);
      expect(result.transaction!.bank, 'Slice');
      expect(result.transaction!.amount, 550);
      expect(result.transaction!.isCredit, isFalse);
      expect(result.transaction!.maskedAccount, contains('0856'));
    });

    test('NEFT credit into a/c parses', () {
      const body =
          'Rs. 3,735.60 received in a/c XXX856 from LENDENCLUB BORROWER REPAYMENT  on 11-May-26 (NEFT Ref No. IN22613144316995). - slice';
      final result = SmsScanPipeline.process(
        SmsMessageInput(
          id: '2',
          sender: 'VM-SLCEIT-S',
          body: body,
          timestamp: DateTime(2026, 5, 11),
        ),
      );
      expect(result.outcome, SmsPipelineOutcome.parsed);
      expect(result.transaction!.bank, 'Slice');
      expect(result.transaction!.isCredit, isTrue);
      expect(result.transaction!.amount, 3735.60);
      // Live SMS uses XXX856 (3 digits); normalize pads to last4 0856.
      expect(result.transaction!.maskedAccount, contains('0856'));
    });

    test('received in slice A/c via UPI parses', () {
      const body =
          'Rs. 1,246 received in slice A/c xx0856 on 05-Jan-26 from TEST USER via UPI (Ref ID: 859763507963). Avl. Bal. Rs. 1,246.39 - slice';
      final result = SmsScanPipeline.process(
        SmsMessageInput(
          id: '3',
          sender: 'AD-SLCEIT-S',
          body: body,
          timestamp: DateTime(2026, 1, 5),
        ),
      );
      expect(result.outcome, SmsPipelineOutcome.parsed);
      expect(result.transaction!.bank, 'Slice');
      expect(result.transaction!.isCredit, isTrue);
      expect(result.transaction!.amount, 1246);
    });

    test('received in A/c via IMPS parses', () {
      const body =
          'Rs. 100 received in A/c xx0856 on 24-Jun-26 from CASHFREE PAYMENTS ES via IMPS (Ref ID: 617511688114). Avl. Bal. Rs. 2,787.61 - slice';
      final result = SmsScanPipeline.process(
        SmsMessageInput(
          id: '3b',
          sender: 'VA-SLCBNK-T',
          body: body,
          timestamp: DateTime(2026, 6, 24),
        ),
      );
      expect(result.outcome, SmsPipelineOutcome.parsed);
      expect(result.transaction!.bank, 'Slice');
      expect(result.transaction!.isCredit, isTrue);
      expect(result.transaction!.amount, 100);
      expect(result.transaction!.maskedAccount, contains('0856'));
    });

    test('IMPS successful payment parses as debit', () {
      const body =
          'IMPS payment of Rs. 10 from A/c xx0856 done on 29-Apr-26 to Paro Devi is successful (Ref ID: 611909688969). Not you? Call 08048329999 - slice';
      final result = SmsScanPipeline.process(
        SmsMessageInput(
          id: '4',
          sender: 'BG-SLCEIT-S',
          body: body,
          timestamp: DateTime(2026, 4, 29),
        ),
      );
      expect(result.outcome, SmsPipelineOutcome.parsed);
      expect(result.transaction!.isCredit, isFalse);
      expect(result.transaction!.amount, 10);
    });

    test('SLCBNK credit card spend parses', () {
      const body =
          'Rs. 124 spent on your credit card xx7185 at Test Merchant on 18-Jun-26 (UPI Ref: 616982957103). Not you? Call 080-4832-9999 - slice';
      final result = SmsScanPipeline.process(
        SmsMessageInput(
          id: '5',
          sender: 'VA-SLCBNK-S',
          body: body,
          timestamp: DateTime(2026, 6, 18),
        ),
      );
      expect(result.outcome, SmsPipelineOutcome.parsed);
      expect(result.transaction!.bank, 'Slice');
      expect(result.transaction!.amount, 124);
      expect(result.transaction!.maskedAccount, contains('7185'));
    });

    test('failed UPI that was refunded is not a transaction', () {
      const body =
          'UPI Payment of Rs. 28,300 from a/c xx0856 on 04-Jun-26 to BELI DEVI has failed. Any debited amount has been refunded - slice';
      final result = SmsScanPipeline.process(
        SmsMessageInput(
          id: '6',
          sender: 'AX-SLCEIT-S',
          body: body,
          timestamp: DateTime(2026, 6, 4),
        ),
      );
      expect(result.isParsed, isFalse);
    });

    test('failed UPI that will be retried is not a transaction (R2-8)', () {
      const body =
          'UPI Payment of Rs. 28,300 from a/c xx0856 on 04-Jun-26 to BELI DEVI has failed. Please retry - slice';
      expect(SmsParser.isRealTransactionSms('AX-SLCEIT-S', body), isFalse);
      final result = SmsScanPipeline.process(
        SmsMessageInput(
          id: '6c',
          sender: 'AX-SLCEIT-S',
          body: body,
          timestamp: DateTime(2026, 6, 4),
        ),
      );
      expect(result.isParsed, isFalse);
    });

    test('pending UPI status update is not a transaction', () {
      const body =
          'UPI payment of Rs. 28,300 from a/c xx0856 on 04-Jun-26 to BELI DEVI is pending. The status will be updated within 48 hours - slice';
      final result = SmsScanPipeline.process(
        SmsMessageInput(
          id: '6b',
          sender: 'AD-SLCBNK-S',
          body: body,
          timestamp: DateTime(2026, 6, 4),
        ),
      );
      expect(result.isParsed, isFalse);
      expect(result.outcome, SmsPipelineOutcome.noTransactionSignal);
    });

    test('discovery finds Slice savings mask', () {
      final d = AccountDiscovery.discover(
        sender: 'AX-SLCEIT-S',
        body:
            'Rs. 550 sent from a/c xx0856 on 18-May-26 to CREW SPORTS (UPI Ref: 650468933013). Not you? Call 08048329999 - slice',
      );
      expect(d, isNotNull);
      expect(d!.bank, 'Slice');
      expect(d.mask, contains('0856'));
      expect(d.kind, AccountKind.savings);
    });

    test('discovery pads XXX856 NEFT credit to ••••0856', () {
      final d = AccountDiscovery.discover(
        sender: 'VM-SLCEIT-S',
        body:
            'Rs. 3,735.60 received in a/c XXX856 from LENDENCLUB BORROWER REPAYMENT  on 11-May-26 (NEFT Ref No. IN22613144316995). - slice',
      );
      expect(d, isNotNull);
      expect(d!.bank, 'Slice');
      expect(d.mask, contains('0856'));
      expect(d.kind, AccountKind.savings);
    });

    test('logo asset resolves', () {
      expect(BankAssets.assetPathFor('Slice'), 'assets/banks/slice.svg');
    });
  });
}
