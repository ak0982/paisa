import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';

import 'package:paisa_app/providers/finance_store.dart';

/// ISSUE-8: scan failures must show a short, friendly message — never a raw
/// PlatformException / stack dump.
void main() {
  test('PlatformException maps to a friendly inbox message', () {
    final msg = FinanceStore.friendlyScanError(
      PlatformException(
        code: 'READ_FAILED',
        message: 'content://sms read denied',
        details: {'stack': 'com.paisa...'},
      ),
    );
    expect(msg, isNot(contains('PlatformException')));
    expect(msg, isNot(contains('READ_FAILED')));
    expect(msg, isNot(contains('content://')));
    expect(msg.toLowerCase(), contains('sms'));
  });

  test('generic error maps to a friendly retry message', () {
    final msg = FinanceStore.friendlyScanError(
      StateError('bad state: internal detail 0xDEAD'),
    );
    expect(msg, isNot(contains('StateError')));
    expect(msg, isNot(contains('0xDEAD')));
    expect(msg.toLowerCase(), contains('try again'));
  });
}
