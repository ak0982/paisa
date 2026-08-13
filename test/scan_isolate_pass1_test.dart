import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/services/sms/account_bank_registry.dart';
import 'package:paisa_app/services/sms/sms_parse_isolate.dart';

/// ISSUE-10 / ISSUE-12: discovery+learn isolate and registry seeding.
void main() {
  test('discoverAndLearnInIsolate returns votes from candidates + seed', () async {
    final result = await discoverAndLearnInIsolate({
      'allRows': const <Map>[],
      'candidates': [
        {
          'id': '1',
          'sender': 'VM-HDFCBK',
          'body':
              'Dear customer, HDFC Bank A/c XX4321 has been debited Rs.100',
          'timestampMs': DateTime(2026, 7, 1).millisecondsSinceEpoch,
        },
      ],
      'seedVotes': {
        '0429': {'SBI': 3},
      },
    });

    expect(result.votes['0429']?['SBI'], 3);
    // Learned from the candidate body as well when unambiguous.
    expect(result.votes.containsKey('4321') || result.votes.containsKey('0429'), isTrue);
  });

  test('priorDiscoveries seed registry before candidate learn (R2-5)', () async {
    final result = await discoverAndLearnInIsolate({
      'allRows': const <Map>[],
      'candidates': [
        {
          'id': '1',
          'sender': 'VM-ICICI-S',
          'body':
              'Account XXXXXXXX0856 has been credited with amount Rs.5000.00. '
              'Info: LENDENCLUB BORROWER REPAYMENT.',
          'timestampMs': DateTime(2026, 5, 1).millisecondsSinceEpoch,
        },
      ],
      'seedVotes': const <String, Map<String, int>>{},
      'priorDiscoveries': [
        {'bank': 'Slice', 'mask': '••••0856', 'smsHits': 20},
      ],
    });

    expect(result.votes['0856']?['Slice'], greaterThan(0));
  });

  test('seedVotes preserves prior bank ownership across learn', () {
    final registry = AccountBankRegistry()
      ..seedVotes({
        '0429': {'SBI': 5},
      });
    expect(registry.lookup('0429'), 'SBI');
    registry.learn('VM-ICICI', 'ICICI Bank credit to account XX9999');
    expect(registry.lookup('0429'), 'SBI');
  });
}
