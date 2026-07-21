import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/services/sms/parsed_sms_transaction.dart';
import 'package:paisa_app/services/sms/sms_parser.dart';

/// ISSUE-14: amounts with a single decimal digit must not be truncated.
void main() {
  test('parses single-decimal paise amount Rs 500.5 as 500.5', () {
    final parsed = SmsParser.parseTransaction(
      SmsMessageInput(
        id: '1',
        sender: 'VM-HDFCBK',
        body:
            'Sent Rs.500.5 from a/c **4321 to Swiggy on 07-Jul-26 UPI ref 5521.',
        timestamp: DateTime(2026, 7, 7, 12),
      ),
    );
    expect(parsed, isNotNull);
    expect(parsed!.amount, 500.5);
  });

  test('still parses two-decimal amounts', () {
    final parsed = SmsParser.parseTransaction(
      SmsMessageInput(
        id: '2',
        sender: 'VM-HDFCBK',
        body:
            'Sent Rs.486.00 from a/c **4321 to Swiggy on 07-Jul-26 UPI ref 5521.',
        timestamp: DateTime(2026, 7, 7, 12),
      ),
    );
    expect(parsed, isNotNull);
    expect(parsed!.amount, 486);
  });
}
