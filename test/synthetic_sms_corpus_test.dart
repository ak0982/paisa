import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/services/sms/parsed_sms_transaction.dart';
import 'package:paisa_app/services/sms/sms_scan_pipeline.dart';

/// ISSUE-16: always-on gate coverage using a committed synthetic SMS corpus
/// (no personal dump required). Dump-dependent suites remain optional.
void main() {
  final fixture = File('test/fixtures/synthetic_sms_corpus.txt');

  test('synthetic corpus file is present', () {
    expect(fixture.existsSync(), isTrue);
  });

  test('pipeline accepts real templates and rejects promo/scam/OTP', () {
    final lines = fixture
        .readAsLinesSync()
        .where((l) => l.trim().isNotEmpty && !l.trimLeft().startsWith('#'))
        .toList();

    expect(lines, isNotEmpty);

    var parsed = 0;
    var rejected = 0;
    for (var i = 0; i < lines.length; i++) {
      final parts = lines[i].split('\t');
      expect(parts.length, greaterThanOrEqualTo(2),
          reason: 'line ${i + 1} must be sender\\tbody');
      final sender = parts[0].trim();
      final body = parts.sublist(1).join('\t').trim();
      final result = SmsScanPipeline.process(
        SmsMessageInput(
          id: 'syn_$i',
          sender: sender,
          body: body,
          timestamp: DateTime(2026, 7, 1),
        ),
      );
      if (result.isParsed) {
        parsed++;
        expect(result.transaction!.amount, greaterThan(0));
      } else {
        rejected++;
      }
    }

    // Corpus is balanced: several real alerts + several rejects.
    expect(parsed, greaterThanOrEqualTo(4));
    expect(rejected, greaterThanOrEqualTo(4));
  });
}
