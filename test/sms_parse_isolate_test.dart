import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/data/sms_scan_state.dart';
import 'package:paisa_app/services/sms/parsed_sms_transaction.dart';
import 'package:paisa_app/services/sms/sms_parse_isolate.dart';
import 'package:paisa_app/services/sms/sms_reader_service.dart';

void main() {
  group('SmsScanOptions', () {
    test('defaultSinceMs returns roughly 24 months ago', () {
      final since = SmsScanOptions.defaultSinceMs(months: 24);
      final sinceDate = DateTime.fromMillisecondsSinceEpoch(since);
      final now = DateTime.now();
      final diffMonths =
          (now.year - sinceDate.year) * 12 + (now.month - sinceDate.month);
      expect(diffMonths, greaterThanOrEqualTo(23));
      expect(diffMonths, lessThanOrEqualTo(25));
    });

    test('full scan reads the ENTIRE inbox (sinceMs == null, no lower bound)',
        () {
      final reader = SmsReaderService();
      // Fresh install / full rescan: no lower bound so all history is read.
      final fresh = reader.optionsFromState(const SmsScanState());
      expect(fresh.incremental, isFalse);
      expect(fresh.sinceMs, isNull);

      // Interrupted full scan resumes with no lower bound either.
      final resumed = reader.optionsFromState(
        const SmsScanState(fullScanComplete: false, resumeOffset: 2000),
      );
      expect(resumed.incremental, isFalse);
      expect(resumed.resumeOffset, 2000);
      expect(resumed.sinceMs, isNull);
    });

    test('incremental sync after full scan only fetches since last scan', () {
      final reader = SmsReaderService();
      final lastScan = DateTime(2026, 6, 1, 12);
      final opts = reader.optionsFromState(
        SmsScanState(
          fullScanComplete: true,
          resumeOffset: 0,
          lastScanAt: lastScan,
        ),
      );
      expect(opts.incremental, isTrue);
      expect(opts.sinceMs, isNotNull);
      // Bounded around the last scan (minus a 1h safety overlap), not epoch.
      final since = DateTime.fromMillisecondsSinceEpoch(opts.sinceMs!);
      expect(since.isBefore(lastScan) || since == lastScan, isTrue);
      expect(since.isAfter(DateTime(2026, 5, 1)), isTrue);
    });
  });

  group('parseCandidatesInIsolate', () {
    test('parses bank SMS off main thread', () async {
      final hits = await parseCandidatesInIsolate([
        {
          'id': '1',
          'sender': 'VM-HDFCBK',
          'body':
              'Sent Rs.486.00 from a/c **4321 to Swiggy on 07-Jul-26 UPI ref 5521.',
          'timestampMs': DateTime(2026, 7, 7).millisecondsSinceEpoch,
        },
      ]);

      expect(hits, hasLength(1));
      expect(hits.first.amount, 486);
      expect(hits.first.merchant, 'Swiggy');
    });

    test('skips promo SMS in isolate', () async {
      final hits = await parseCandidatesInIsolate([
        {
          'id': '2',
          'sender': 'VM-HDFCBK',
          'body':
              'Dear Customer, Get pre-approved Personal Loan of Rs.5,00,000. '
              'Apply now.',
          'timestampMs': DateTime(2026, 7, 7).millisecondsSinceEpoch,
        },
      ]);

      expect(hits, isEmpty);
    });
  });
}
