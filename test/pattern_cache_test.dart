import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/services/sms/parsed_sms_transaction.dart';
import 'package:paisa_app/services/sms/sms_parser.dart';

/// ISSUE-9: parseTransaction must reuse a static pattern list, not rebuild
/// ~50 RegExps on every call. Behaviour must stay identical across calls.
void main() {
  test('repeated parseTransaction calls return identical results', () {
    final input = SmsMessageInput(
      id: '1',
      sender: 'VM-HDFCBK',
      body:
          'Rs.500.00 debited from a/c XX1234 on 21-07-26 to SWIGGY. Avl bal Rs.10000.00',
      timestamp: DateTime(2026, 7, 21, 12),
    );

    final first = SmsParser.parseTransaction(input);
    final second = SmsParser.parseTransaction(input);

    expect(first, isNotNull);
    expect(second, isNotNull);
    expect(first!.amount, second!.amount);
    expect(first.isCredit, second.isCredit);
    expect(first.maskedAccount, second.maskedAccount);
    expect(first.merchant, second.merchant);
  });
}
