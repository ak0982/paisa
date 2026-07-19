import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/services/sms/account_discovery.dart';
import 'package:paisa_app/services/sms/parsed_sms_transaction.dart';
import 'package:paisa_app/services/sms/sms_parser.dart';
import 'package:paisa_app/services/sms/transaction_enrichment.dart';

void main() {
  group('TransactionEnrichment', () {
    test('cleans unknown masks from body last4', () {
      final mask = TransactionEnrichment.resolveMaskedAccount(
        parsedMask: '••••????',
        sender: 'HDFCBK',
        body: 'Rs.500 debited from A/c **5300 on 05-07-26 at Swiggy',
      );
      expect(mask, '••••5300');
    });

    test('detects credit card kind from SMS body', () {
      final kind = TransactionEnrichment.resolveAccountKind(
        bank: 'SBI',
        mask: '••••3452',
        body: 'INR 2,499 spent on Credit Card ending 3452 at Amazon',
        discoveries: const [],
      );
      expect(kind, AccountKind.creditCard);
    });

    test('detects loan EMI kind', () {
      final kind = TransactionEnrichment.resolveAccountKind(
        bank: 'HDFC',
        mask: '••••0855',
        body: 'EMI of Rs 8500 towards HDFC Home Loan A/c 0855',
        discoveries: const [],
      );
      expect(kind, AccountKind.loan);
    });

    test('NACH debit from savings is loan not savings', () {
      final discoveries = [
        const DiscoveredAccount(
          bank: 'Kotak',
          mask: '••••3649',
          kind: AccountKind.savings,
          accountLabel: 'Savings',
        ),
        const DiscoveredAccount(
          bank: 'HDFC',
          mask: '••••0855',
          kind: AccountKind.loan,
          accountLabel: 'Home Loan',
        ),
      ];
      final body =
          'INR 25,797.00 is debited to your Account XXXXXX3649 on 07/12/2025 towards NACH-10-HDFC BANK LIMITED Kotak Bank';
      final kind = TransactionEnrichment.resolveAccountKind(
        bank: 'Kotak',
        mask: '••••3649',
        body: body,
        discoveries: discoveries,
      );
      expect(kind, AccountKind.loan);
    });

    test('PNB loan payment SMS parses', () {
      final body =
          'Thanks for depositing an amount of Rs. 5200 against your Loan Ac XX0310. Register for e-statement,if not done.-PNB';
      final parsed = SmsParser.parseTransaction(
        SmsMessageInput(
          id: '1',
          sender: 'PNBSMS',
          body: body,
          timestamp: DateTime(2025, 1, 1),
        ),
      );
      expect(parsed, isNotNull);
      expect(parsed!.amount, 5200);
      expect(parsed.maskedAccount, '••••0310');
    });

    test('CCBP debit from savings is credit card payment', () {
      final body =
          'Dear UPI user A/C X6675 debited by 1000.0 on date 29Sep25 trf to MBK CCBP Refno 101568018632';
      final kind = TransactionEnrichment.resolveAccountKind(
        bank: 'SBI',
        mask: '••••6675',
        body: body,
        discoveries: const [],
      );
      expect(kind, AccountKind.creditCard);
    });

    test('BBPS SBI credit card payment parses', () {
      final body =
          'We have received payment of Rs.2,400.68 via BBPS & the same has been credited to your SBI Credit Card. Your available limit is Rs.228,745.25.';
      final parsed = SmsParser.parseTransaction(
        SmsMessageInput(
          id: '1',
          sender: 'VM-SBICRD-S',
          body: body,
          timestamp: DateTime(2025, 12, 1),
        ),
      );
      expect(parsed, isNotNull);
      expect(parsed!.amount, 2400.68);
      expect(parsed.isCredit, isTrue);
    });

    test('CRED ICICI credit card payment parses', () {
      final body =
          'Payment of Rs.5,270 has been successfully credited towards your ICICI Bank Credit Card. Your payment was settled in 3 seconds - CRED';
      final parsed = SmsParser.parseTransaction(
        SmsMessageInput(
          id: '1',
          sender: 'VM-CREDIN-S',
          body: body,
          timestamp: DateTime(2025, 5, 1),
        ),
      );
      expect(parsed, isNotNull);
      expect(parsed!.amount, 5270);
      expect(parsed.isCredit, isTrue);
    });

    test('improves generic merchant labels', () {
      final merchant = TransactionEnrichment.improveMerchant(
        merchant: 'Transaction',
        body: 'Rs 486 debited at Swiggy on 05-07-26',
        isCredit: false,
        accountKind: AccountKind.savings,
      );
      expect(merchant.toLowerCase(), contains('swiggy'));
    });
  });
}
