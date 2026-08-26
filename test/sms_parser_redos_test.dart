import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:paisa_app/services/sms/parsed_sms_transaction.dart';
import 'package:paisa_app/services/sms/sms_parser.dart';
import 'package:paisa_app/services/sms/sms_scan_pipeline.dart';

/// A crafted SMS is remote, attacker-chosen input to the regex parser. Several
/// patterns pair two `.*`/`.+` runs, and a concatenated multipart SMS can be
/// tens of thousands of characters, so before the cap one message could hold a
/// whole scan hostage. Measured against the pre-cap parser, full pipeline:
///
///   `payment of INR 1.00 received towards your ` ×n   8kB 0.6s ·  34kB 33s
///   `credited with Rs 1,00 against reversa ` ×n        30kB 5.7s · 122kB 93s
///   `cashback of INR 1.00 credited to you ` ×n         30kB 1.5s · 118kB 24s
///
/// Post-cap every one of them is flat at a few tens of ms regardless of size.
void main() {
  SmsMessageInput craft(String body) => SmsMessageInput(
        id: '1',
        sender: 'AD-HDFCBK-S',
        body: body,
        timestamp: DateTime(2026, 1, 1),
      );

  group('scan body cap', () {
    test('leaves anything a real bank sends untouched', () {
      const real =
          'HDFC Bank: Rs. 2,450.00 debited from a/c **5300 on 12/07/26 to '
          'SWIGGY (UPI Ref 936522754342). Not you? Call 18002586161.';
      expect(SmsParser.capScanBody(real), real);
      expect(SmsParser.capScanBody(''), '');
    });

    test('truncates oversized bodies to the cap', () {
      final huge = 'x' * 40000;
      expect(
        SmsParser.capScanBody(huge).length,
        SmsParser.maxScanBodyLength,
      );
      final exact = 'y' * SmsParser.maxScanBodyLength;
      expect(SmsParser.capScanBody(exact), exact);
    });

    test('cap leaves headroom over the longest message in the live corpus', () {
      // Longest body observed in the private dump is 1,696 characters, so the
      // cap must stay clear of it or a real alert could lose its tail.
      expect(SmsParser.maxScanBodyLength, greaterThanOrEqualTo(1800));

      for (final path in ['my_sms_live.txt', '${Platform.environment['HOME']}/Downloads/my_sms.txt']) {
        final file = File(path);
        if (!file.existsSync()) continue;
        final longest = file
            .readAsLinesSync()
            .fold<int>(0, (max, line) => line.length > max ? line.length : max);
        expect(
          longest,
          lessThan(SmsParser.maxScanBodyLength),
          reason: '$path has a $longest-char line — raise the cap',
        );
      }
    });

    test('the scan boundary caps bodies too', () {
      // Discovery and enrichment regex over the same rows without going
      // through SmsParser, so the reader must cap what it hands to Dart.
      final reader =
          File('lib/services/sms/sms_reader_service.dart').readAsStringSync();
      expect(reader.contains('SmsParser.capScanBody'), isTrue);
    });
  });

  group('adversarial bodies stay bounded', () {
    // The first three are the shapes that actually blew up pre-cap; the rest
    // are cheap neighbours kept so a future pattern edit that makes one of
    // them quadratic is caught too.
    final shapes = <String, String Function(int)>{
      'paired .* patterns': (n) =>
          'HDFC Bank debited ${'payment of INR 1.00 received towards your ' * n}',
      'credited-with-rs pair': (n) =>
          'HDFC Bank ${'credited with Rs 1,00 against reversa ' * n}',
      'cashback .+ pair': (n) =>
          'HDFC Bank ${'cashback of INR 1.00 credited to you ' * n}',
      'unbounded word run': (n) =>
          'HDFC Bank: Rs. 500.00 debited spent using ${'word ' * n}X',
      'refund/transfer pair': (n) =>
          'HDFC Bank debited ${'refund of INR 1.00 credited to savings account ' * n}',
      'comma amount run': (n) => 'HDFC Bank: Rs. ${'1,' * n}debited from a/c',
    };

    for (final shape in shapes.entries) {
      test('${shape.key} parse stays under a second at scale', () {
        final body = shape.value(4000);
        expect(body.length, greaterThan(SmsParser.maxScanBodyLength * 3));

        final sw = Stopwatch()..start();
        SmsScanPipeline.process(craft(body));
        sw.stop();

        expect(
          sw.elapsedMilliseconds,
          lessThan(1000),
          reason: 'super-linear parse cost is back (${sw.elapsedMilliseconds}ms)',
        );
      });
    }

    test('a genuine alert still parses after the cap', () {
      final result = SmsScanPipeline.process(
        craft(
          'HDFC Bank: Rs. 2,450.00 debited from a/c **5300 on 12/07/26 to '
          'SWIGGY (UPI Ref 936522754342). Not you? Call 18002586161.',
        ),
      );
      expect(result.outcome, SmsPipelineOutcome.parsed);
      expect(result.transaction?.amount, 2450.0);
    });

    test('an oversized crafted body cannot become a transaction', () {
      final result = SmsScanPipeline.process(
        craft('HDFC Bank debited ${'payment of INR 1.00 received towards your ' * 4000}'),
      );
      expect(result.isParsed, isFalse);
    });
  });
}
