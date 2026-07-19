import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/services/sms/account_discovery.dart';
import 'package:paisa_app/services/sms/parsed_sms_transaction.dart';
import 'package:paisa_app/services/sms/sms_keyword_lists.dart';
import 'package:paisa_app/services/sms/sms_parser.dart';
import 'package:paisa_app/services/sms/transaction_enrichment.dart';

void main() {
  group('SmsKeywordLists', () {
    test('extracts allowlisted UPI VPAs', () {
      expect(
        SmsKeywordLists.extractUpiVpa('paid to swiggy@ybl Ref 123'),
        'swiggy@ybl',
      );
      expect(
        SmsKeywordLists.extractUpiVpa(
          'from VPA merchant.store@okhdfcbank (UPI 99)',
        ),
        'merchant.store@okhdfcbank',
      );
      expect(
        SmsKeywordLists.extractUpiVpa('transfer to user@ibl done'),
        'user@ibl',
      );
    });

    test('ignores unknown email-like handles', () {
      expect(
        SmsKeywordLists.extractUpiVpa('mail us at help@notabank.example'),
        isNull,
      );
      expect(SmsKeywordLists.isKnownUpiVpa('help@gmail.com'), isFalse);
      expect(SmsKeywordLists.isKnownUpiVpa('cafe@ybl'), isTrue);
    });

    test('detects wallet providers', () {
      expect(SmsKeywordLists.detectWalletProvider('AD-MOBIKW-S'), 'MobiKwik');
      expect(
        SmsKeywordLists.detectWalletProvider('paid via Amazon Pay wallet'),
        'Amazon Pay',
      );
      expect(
        SmsKeywordLists.detectWalletProvider('Freecharge payment success'),
        'Freecharge',
      );
      expect(SmsKeywordLists.detectWalletProvider('HDFC Bank alert'), isNull);
    });

    test('detects card schemes', () {
      expect(
        SmsKeywordLists.detectCardScheme('spent on HDFC Visa Credit Card'),
        'Visa',
      );
      expect(
        SmsKeywordLists.detectCardScheme('RuPay card ending 1234'),
        'RuPay',
      );
      expect(
        SmsKeywordLists.detectCardScheme('American Express purchase'),
        'Amex',
      );
    });

    test('extracts available balance and limit', () {
      expect(
        SmsKeywordLists.extractAvailableBalance(
          'Txn done. Avl bal Rs.12,345.50. Not you?',
        ),
        12345.50,
      );
      expect(
        SmsKeywordLists.extractAvailableBalance(
          'Payment received. Your available limit is Rs.228,745.25.',
        ),
        228745.25,
      );
      expect(
        SmsKeywordLists.extractAvailableBalance(
          'Rs.10000.00 available bal after txn',
        ),
        10000.00,
      );
    });

    test('strips balance suffixes from merchant text', () {
      expect(
        SmsKeywordLists.stripBalanceSuffix('AMAZON. Avl Lmt Rs.50000'),
        'AMAZON',
      );
      expect(
        SmsKeywordLists.stripBalanceSuffix(
          'SWIGGY Available balance Rs.200',
        ),
        'SWIGGY',
      );
    });

    test('lightlyNormalizes currency and a/c tokens', () {
      final n = SmsKeywordLists.lightlyNormalize('Rs500 debited from a/c XX12');
      expect(n, contains('rs. 500'));
      expect(n, contains('ac xx12'));
      expect(n.contains('a/c'), isFalse);
    });
  });

  group('parser + enrichment wiring', () {
    SmsMessageInput msg({
      required String sender,
      required String body,
    }) {
      return SmsMessageInput(
        id: '1',
        sender: sender,
        body: body,
        timestamp: DateTime(2026, 7, 11),
      );
    }

    test('parses debit with allowlisted VPA merchant', () {
      final parsed = SmsParser.parse(
        msg(
          sender: 'AD-HDFCBK-S',
          body:
              'Sent Rs.120.00 from a/c **5300 to coffee.shop@ybl on 11-Jul-26 '
              'UPI ref 5511.',
        ),
      );
      expect(parsed, isNotNull);
      expect(parsed!.amount, 120);
      expect(parsed.merchant.toLowerCase(), contains('@ybl'));
    });

    test('detects MobiKwik as wallet bank from sender', () {
      final parsed = SmsParser.parse(
        msg(
          sender: 'VM-MOBIKW-S',
          body: 'Rs.99.00 paid to Jio Recharge via Mobikwik on 11-Jul',
        ),
      );
      expect(parsed, isNotNull);
      expect(parsed!.bank, 'MobiKwik');
      expect(parsed.merchant.toLowerCase(), contains('jio'));
    });

    test('enrichment prefers allowlisted VPA over generic credit label', () {
      final merchant = TransactionEnrichment.improveMerchant(
        merchant: 'Credit received',
        body:
            'Credit Alert! Rs.250 credited to A/c XX5300 from '
            'chaiwala@oksbi (UPI 99)',
        isCredit: true,
        accountKind: AccountKind.savings,
      );
      expect(merchant, 'chaiwala@oksbi');
    });

    test('scheme-aware credit-card detection', () {
      expect(
        TransactionEnrichment.looksLikeCreditCardTransaction(
          'inr 500 spent on your hdfc visa credit card ending 1234 at amazon',
        ),
        isTrue,
      );
    });

    test('does not weaken received Rs promo filter', () {
      expect(
        SmsParser.isRealTransactionSms(
          'AD-PROMO-S',
          "You've received Rs.100 cashback. Tap now to claim before offer expires!",
        ),
        isFalse,
      );
    });
  });
}
