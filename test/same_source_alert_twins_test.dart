import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/models/transaction.dart';
import 'package:paisa_app/providers/finance_store.dart';
import 'package:paisa_app/services/sms/account_discovery.dart';
import 'package:paisa_app/services/sms/merchant_categorizer.dart';
import 'package:paisa_app/services/sms/parsed_sms_transaction.dart';
import 'package:paisa_app/services/sms/sms_scan_pipeline.dart';
import 'package:paisa_app/services/sms/transaction_enrichment.dart';

/// Schema 35: HDFC Spent + ALERT debit-card / CCBBPSNO SMS are one event.
void main() {
  final store = FinanceStore();
  final t0 = DateTime(2026, 8, 7, 6, 2, 24);

  String amtToken(double amount) {
    if (amount == amount.roundToDouble()) return amount.toInt().toString();
    return amount.toStringAsFixed(2);
  }

  String spentBody(double amount) =>
      'Spent Rs.${amtToken(amount)} From HDFC Bank Card x3569 At CCBBPSNO '
      'On 2026-08-01:06:02:24 Bal Rs.55551.08 Not You? Call 18002586161/'
      'SMS BLOCK DC  3569 to 7308080808';

  String alertBody(double amount) {
    final token = amount == amount.roundToDouble()
        ? '${amount.toInt()}.00'
        : amount.toStringAsFixed(2);
    return 'ALERT:Rs.$token spent via HDFC BANK Debit Card xx3569 at CCBBPSNO '
        'on Aug 1 2026 6:02AM without PIN/OTP.Not you?Call 18002586161 / '
        '18002586161.';
  }

  Transaction fromSms({
    required String id,
    required String body,
    required DateTime timestamp,
    String sender = 'AD-HDFCBK-S',
  }) {
    final result = SmsScanPipeline.process(
      SmsMessageInput(
        id: id,
        sender: sender,
        body: body,
        timestamp: timestamp,
      ),
    );
    expect(result.outcome, SmsPipelineOutcome.parsed, reason: body);
    final parsed = result.transaction!;
    final kind = TransactionEnrichment.resolveAccountKind(
      bank: parsed.bank,
      mask: parsed.maskedAccount,
      body: body,
      discoveries: const [],
    );
    final merchant = TransactionEnrichment.improveMerchant(
      merchant: parsed.merchant,
      body: body,
      isCredit: parsed.isCredit,
      accountKind: kind,
    );
    final hints = TransactionEnrichment.cardAlertTwinHints(body);
    return Transaction(
      id: 'sms_$id',
      smsId: id,
      merchant: merchant,
      bank: FinanceStore.canonicalizeBank(parsed.bank),
      maskedAccount: parsed.maskedAccount,
      category: MerchantCategorizer.categorize(
        merchant: merchant,
        smsBody: body,
        isCredit: parsed.isCredit,
      ),
      amount: parsed.amount,
      isCredit: parsed.isCredit,
      timestamp: parsed.timestamp,
      accountKind: kind,
      isDebitCardAlertTwin: hints.isTwin,
      isLeanDebitCardAlert: hints.isLean,
    );
  }

  Transaction manual({
    required String id,
    required double amount,
    required String merchant,
    required String bank,
    required String mask,
    required bool isCredit,
    required DateTime timestamp,
    AccountKind kind = AccountKind.savings,
    bool isTwin = false,
    bool isLean = false,
  }) {
    return Transaction(
      id: id,
      smsId: id,
      merchant: merchant,
      bank: bank,
      maskedAccount: mask,
      category: SpendCategory.bills,
      amount: amount,
      isCredit: isCredit,
      timestamp: timestamp,
      accountKind: kind,
      isDebitCardAlertTwin: isTwin,
      isLeanDebitCardAlert: isLean,
    );
  }

  group('Spent + ALERT same-event collapse', () {
    test('11254.82 Spent + ALERT ~3s apart → one Spent row, exact paise', () {
      const amount = 11254.82;
      final spent = fromSms(
        id: 'spent-11254',
        body: spentBody(amount),
        timestamp: t0,
      );
      final alert = fromSms(
        id: 'alert-11254',
        body: alertBody(amount),
        timestamp: t0.add(const Duration(seconds: 3)),
      );

      expect(spent.isLeanDebitCardAlert, isFalse);
      expect(alert.isLeanDebitCardAlert, isTrue);

      final kept = store.debugDropSameSourceAlertTwins([alert, spent], const []);
      expect(kept, hasLength(1));
      expect(kept.single.id, spent.id);
      expect(kept.single.amount, 11254.82);
      expect(kept.single.isLeanDebitCardAlert, isFalse);
      expect(kept.single.maskedAccount, '••••3569');
    });

    test('historical SmartPay twin matrix collapses to one row', () {
      const amounts = [31250.0, 15076.54, 3246.0, 562.0];
      for (final amount in amounts) {
        final spent = fromSms(
          id: 'spent-$amount',
          body: spentBody(amount),
          timestamp: t0,
        );
        final alert = fromSms(
          id: 'alert-$amount',
          body: alertBody(amount),
          timestamp: t0.add(const Duration(seconds: 2)),
        );
        final kept =
            store.debugDropSameSourceAlertTwins([spent, alert], const []);
        expect(kept, hasLength(1), reason: 'amount $amount');
        expect(kept.single.id, spent.id, reason: 'amount $amount');
        expect(kept.single.amount, amount, reason: 'amount $amount');
      }
    });

    test('isolated ALERT still parses and is kept when no twin exists', () {
      final alert = fromSms(
        id: 'lone-alert',
        body: alertBody(31250),
        timestamp: t0,
      );
      expect(alert.isLeanDebitCardAlert, isTrue);
      expect(alert.amount, 31250);
      final kept = store.debugDropSameSourceAlertTwins([alert], const []);
      expect(kept, hasLength(1));
      expect(kept.single.id, alert.id);
    });

    test('ALERT twin of an already-stored Spent row is not inserted', () {
      final existing = fromSms(
        id: 'stored-spent',
        body: spentBody(15076.54),
        timestamp: t0,
      );
      final alert = fromSms(
        id: 'new-alert',
        body: alertBody(15076.54),
        timestamp: t0.add(const Duration(seconds: 4)),
      );
      final kept = store.debugDropSameSourceAlertTwins([alert], [existing]);
      expect(kept, isEmpty);
    });
  });

  group('must not collapse non-twins', () {
    test('two real spends same amount different merchants within 3 min → both kept',
        () {
      final a = manual(
        id: 'swiggy',
        amount: 499,
        merchant: 'Swiggy',
        bank: 'HDFC',
        mask: '••••3569',
        isCredit: false,
        timestamp: t0,
      );
      final b = manual(
        id: 'zomato',
        amount: 499,
        merchant: 'Zomato',
        bank: 'HDFC',
        mask: '••••3569',
        isCredit: false,
        timestamp: t0.add(const Duration(minutes: 1)),
      );
      final kept = store.debugDropSameSourceAlertTwins([a, b], const []);
      expect(kept, hasLength(2));
    });

    test('two rich CCBBPSNO Spent rows same amount stay both kept', () {
      final first = fromSms(
        id: 'spent-a',
        body: spentBody(562),
        timestamp: t0,
      );
      final second = fromSms(
        id: 'spent-b',
        body: spentBody(562),
        timestamp: t0.add(const Duration(minutes: 2)),
      );
      final kept =
          store.debugDropSameSourceAlertTwins([first, second], const []);
      expect(kept, hasLength(2));
    });

    test('HDFC CCBP debit + HSBC CC payment-received credit → both kept', () {
      final hdfcDebit = fromSms(
        id: 'hdfc-ccbp',
        body: spentBody(11254.82),
        timestamp: t0,
      );
      final hsbcCredit = manual(
        id: 'hsbc-in',
        amount: 11254.82,
        merchant: 'Credit card payment',
        bank: 'HSBC',
        mask: '••••3740',
        isCredit: true,
        timestamp: t0.add(const Duration(minutes: 1)),
        kind: AccountKind.creditCard,
      );
      final kept = store.debugDropSameSourceAlertTwins(
        [hdfcDebit, hsbcCredit],
        const [],
      );
      expect(kept, hasLength(2));
      expect(kept.map((t) => t.bank), containsAll(['HDFC', 'HSBC']));
    });

    test('ISSUE-4 wallet vs bank still uses cross-source helper only', () {
      final bank = manual(
        id: 'bank',
        amount: 486,
        merchant: 'Swiggy',
        bank: 'HDFC',
        mask: '••••4321',
        isCredit: false,
        timestamp: t0,
      );
      final wallet = manual(
        id: 'wallet',
        amount: 486,
        merchant: 'Swiggy',
        bank: 'Paytm',
        mask: '',
        isCredit: false,
        timestamp: t0.add(const Duration(seconds: 20)),
      );
      expect(
        store.debugDropSameSourceAlertTwins([bank, wallet], const []),
        hasLength(2),
      );
      final cross = store.debugDropCrossSourceDuplicates(
        [bank, wallet],
        const [],
      );
      expect(cross, hasLength(1));
      expect(cross.single.bank, 'HDFC');
    });
  });

  group('Bill Paid SmartPay stays unparsed', () {
    test('HSBCBankCC Bill Paid 11254.82 is not a transaction', () {
      final result = SmsScanPipeline.process(
        SmsMessageInput(
          id: 'bill-paid-11254',
          sender: 'JM-HDFCBK-S',
          body:
              'Bill Paid: HSBCBankCC Bill 3740 of Rs. 11254.82 paid on '
              '07-Aug-26 via SmartPay.',
          timestamp: DateTime(2026, 8, 7),
        ),
      );
      expect(result.isParsed, isFalse);
      expect(
        result.outcome,
        isNot(SmsPipelineOutcome.parsed),
      );
    });
  });
}
