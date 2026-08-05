import 'package:flutter_test/flutter_test.dart';

import 'package:paisa_app/services/sms/account_discovery.dart';

void main() {
  group('AccountDiscovery', () {
    test('detects SBI credit card ending 3452', () {
      final found = AccountDiscovery.discover(
        sender: 'AD-SBICRD-S',
        body:
            'Rs.605.29 spent on your SBI Credit Card ending 3452 at IRCTCAutoPe on 07/12/25.',
      );
      expect(found, isNotNull);
      expect(found!.kind, AccountKind.creditCard);
      expect(found.bank, 'SBI');
      expect(found.mask, '••••3452');
    });

    test('detects HDFC savings salary deposit', () {
      final found = AccountDiscovery.discover(
        sender: 'VM-HDFCBK-S',
        body:
            'INR 2,02,284.00 deposited in HDFC Bank A/c XX5300 on 28-NOV-25 for NEFT Cr salary Amar Kumar',
      );
      expect(found, isNotNull);
      expect(found!.kind, AccountKind.savings);
      expect(found.mask, '••••5300');
    });

    test('detects ICICI personal loan from EMI reminder', () {
      final found = AccountDiscovery.discover(
        sender: 'VA-ICICIT-S',
        body:
            'EMI of Rs 26408.00 for ICICI Bank Personal Loan XX1041 is due on 05-Dec-25.',
      );
      expect(found, isNotNull);
      expect(found!.kind, AccountKind.loan);
      expect(found.mask, '••••1041');
      expect(found.accountLabel, 'Personal Loan');
    });

    test('detects Kotak savings from NACH debit account', () {
      final found = AccountDiscovery.discover(
        sender: 'VM-KOTAKB-S',
        body:
            'INR 25,797.00 is debited to your Account XXXXXX3649 on 07/12/2025 towards NACH-10-HDFC BANK LIMITED Kotak Bank',
      );
      expect(found, isNotNull);
      expect(found!.kind, AccountKind.savings);
      expect(found.bank, 'Kotak');
      expect(found.mask, '••••3649');
    });

    test('detects SBI savings from NACH credit mask', () {
      final found = AccountDiscovery.discover(
        sender: 'VM-CBSSBI-S',
        body:
            'Dear Customer,Your A/C XXXXX286675 has a credit by NACH- POWER GRID CORPORATI of Rs 733.50 on 01/12/25.',
      );
      expect(found, isNotNull);
      expect(found!.kind, AccountKind.savings);
      expect(found.bank, 'SBI');
      expect(found.mask, '••••6675');
    });

    test('detects Yes Bank credit card X9757', () {
      final found = AccountDiscovery.discover(
        sender: 'AD-YESBNK-S',
        body:
            'INR 449.54 spent on YES BANK Card X9757 @UPI_MCDONALDS HARDCAST 07-12-2025',
      );
      expect(found, isNotNull);
      expect(found!.kind, AccountKind.creditCard);
      expect(found.bank, 'Yes Bank');
      expect(found.mask, '••••9757');
    });

    // --- Coverage: savings accounts known only from balance/interest/info SMS ---

    test('detects Federal Bank savings from Jupiter interest SMS', () {
      final found = AccountDiscovery.discover(
        sender: 'VM-MYJPTR',
        body:
            'Rs.1 quarterly interest credited to your Federal Bank Savings '
            'Account XXXX3455 on Jupiter! Save it in a Pot & earn 3.05% '
            'interest p.a.',
      );
      expect(found, isNotNull);
      expect(found!.kind, AccountKind.savings);
      expect(found.bank, 'Federal');
      expect(found.mask, '••••3455');
    });

    test('detects Federal Bank savings from Fi credit SMS', () {
      final found = AccountDiscovery.discover(
        sender: 'VM-FedFiB',
        body:
            'You received INR 29,200.00 in your Account XXXXXXXX7953. Sent by '
            'BHARAT | Date: December 27, 2023 Mode: UPI 9570455351@ybl'
            '-Federal Bank',
      );
      expect(found, isNotNull);
      expect(found!.kind, AccountKind.savings);
      expect(found.bank, 'Federal');
      expect(found.mask, '••••7953');
    });

    test('detects Federal Bank savings from Fi interest info SMS', () {
      final found = AccountDiscovery.discover(
        sender: 'TX-FedFiB',
        body:
            "Great news! We've added INR 1.00 as interest to your account "
            'XXXXXXXX7953. Date: March 22, 2025 | Check Fi app for details. '
            '-Federal Bank',
      );
      expect(found, isNotNull);
      expect(found!.kind, AccountKind.savings);
      expect(found.bank, 'Federal');
      expect(found.mask, '••••7953');
    });

    test('detects PNB savings from a long-mask UPI credit SMS', () {
      final found = AccountDiscovery.discover(
        sender: 'VK-PNBSMS-S',
        body:
            'Ac XXXXXXXX00134720 Credited with Rs.5200.00 01-11-2025 08:30:12 '
            'thru UPI . Aval Bal Rs.5284.01 CR. (UPI Ref ID:032929510967) '
            'Helpline 18001800-PNB',
      );
      expect(found, isNotNull);
      expect(found!.kind, AccountKind.savings);
      expect(found.bank, 'PNB');
      expect(found.mask, '••••4720');
    });

    test('detects PNB savings from a bank-charges debit SMS', () {
      final found = AccountDiscovery.discover(
        sender: 'BG-PNBSMS-S',
        body:
            'Dear Customer,your A/c XXXX4720 debited with Rs.1.77 towards bank '
            'charges on 10-10-2025.Available balance: Rs.74.01-PNB',
      );
      expect(found, isNotNull);
      expect(found!.kind, AccountKind.savings);
      expect(found.bank, 'PNB');
      expect(found.mask, '••••4720');
    });

    test('extracts savings mask written as "A/c XX1234" in a balance SMS', () {
      final found = AccountDiscovery.discover(
        sender: 'VM-IDFCFB-S',
        body:
            'Monthly interest of Rs.2.00 earned on your Savings A/c XX0070 has '
            'been credited to your A/C on 30/11/25. New bal: Rs.821.18. '
            'IDFC FIRST Bank',
      );
      expect(found, isNotNull);
      expect(found!.kind, AccountKind.savings);
      expect(found.bank, 'IDFC');
      expect(found.mask, '••••0070');
    });

    test('a credit-card SMS is NOT discovered as savings', () {
      // The broadened savings wording must never swallow a credit-card SMS.
      final found = AccountDiscovery.discover(
        sender: 'AD-SBICRD-S',
        body:
            'Rs.2,499.00 spent on your SBI Credit Card ending 3452 at AMAZON '
            'on 05-Jul-26. Avl Lmt Rs.1,20,000.',
      );
      expect(found, isNotNull);
      expect(found!.kind, AccountKind.creditCard);
      expect(found.mask, '••••3452');
    });

    test('a counterparty "to A/c 1234" transfer is not a savings account', () {
      // Money SENT to someone else's account must not create an account for the
      // destination mask — only the sender's own account (5300) is discovered.
      final found = AccountDiscovery.discover(
        sender: 'JM-HDFCBK',
        body:
            'HDFC Bank: Rs. 10000.00 debited from a/c **5300 on 06-02-24 to '
            'a/c **2470 (UPI Ref No. 403700467735). Not you? Call 18002586161',
      );
      // Whatever is discovered must not be the counterparty mask.
      expect(found?.mask, isNot('••••2470'));
    });

    test('detects HSBC savings from hyphen/star A/c mask', () {
      final found = AccountDiscovery.discover(
        sender: 'VM-HSBCIN-S',
        body:
            'HSBC: INR 1,234.56 is paid from your A/c 074-260***-006 to AMAZON '
            'on 20-Dec-25. Your Avl Bal is INR 98,765.44 .',
      );
      expect(found, isNotNull);
      expect(found!.kind, AccountKind.savings);
      expect(found.bank, 'HSBC');
      expect(found.mask, '••••0006');
    });

    test('detects HSBC credit card from creditcard used-at SMS', () {
      final found = AccountDiscovery.discover(
        sender: 'AD-HSBCIN-S',
        body:
            'Your HSBC creditcard xxxxx4821 used at AMAZON for INR 305.00 on 15-04-25.',
      );
      expect(found, isNotNull);
      expect(found!.kind, AccountKind.creditCard);
      expect(found.bank, 'HSBC');
      expect(found.mask, '••••4821');
    });
  });
}
