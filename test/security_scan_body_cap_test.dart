import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/models/transaction.dart';
import 'package:paisa_app/providers/app_settings.dart';
import 'package:paisa_app/services/sms/account_discovery.dart';
import 'package:paisa_app/services/sms/original_sms_lookup.dart';
import 'package:paisa_app/services/sms/parsed_sms_transaction.dart';
import 'package:paisa_app/services/sms/sms_parser.dart';
import 'package:paisa_app/services/sms/sms_scan_pipeline.dart';
import 'package:paisa_app/widgets/sms_coin_slab.dart';

import 'helpers/test_harness.dart';

/// SEC-8 — an SMS is remote, attacker-chosen input to a regex parser. Several
/// transaction patterns pair two `.*`/`.+` runs, and a concatenated multipart
/// message can be tens of thousands of characters, so before the cap a single
/// message someone sent the customer could hold an entire inbox scan hostage
/// (measured: 33 s at 34 kB, 93 s at 122 kB, worse than quadratic).
///
/// [sms_parser_redos_test.dart] holds the original repro shapes. This suite
/// covers the contract around them: the exact cap boundary, that every parser
/// entry point applies it, that scanning stays flat as bodies grow, and — the
/// other half of the requirement — that the Coin Flip reverse still shows the
/// customer their *whole* message.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const cap = SmsParser.maxScanBodyLength;
  const realAlert =
      'HDFC Bank: Rs. 2,450.00 debited from a/c **5300 on 12/07/26 to '
      'SWIGGY (UPI Ref 936522754342). Not you? Call 18002586161.';

  SmsMessageInput craft(String body, {String sender = 'AD-HDFCBK-S'}) =>
      SmsMessageInput(
        id: '1',
        sender: sender,
        body: body,
        timestamp: DateTime(2026, 1, 1),
      );

  group('the cap boundary', () {
    test('the cap leaves room for the longest message a bank actually sends',
        () {
      // Longest body in the live corpus is 1,696 characters.
      expect(cap, greaterThanOrEqualTo(1800));
    });

    for (final length in [0, 1, 19, 199, cap - 1, cap]) {
      test('a $length-character body is passed through whole', () {
        final body = 'a' * length;
        expect(SmsParser.capScanBody(body), body);
        expect(SmsParser.capScanBody(body).length, length);
      });
    }

    for (final length in [cap + 1, cap * 2, 40000, 200000]) {
      test('a $length-character body is cut to the cap', () {
        expect(SmsParser.capScanBody('a' * length).length, cap);
      });
    }

    test('a body at or below the cap is not even copied', () {
      expect(SmsParser.capScanBody(realAlert), same(realAlert));
    });

    test('what survives is always the leading edge of the message', () {
      // Bank alerts put the amount, account and merchant first; the tail is
      // "Not you? Call…" boilerplate. Truncating the tail is the safe end.
      final body = '${'b' * cap}TAIL';
      final capped = SmsParser.capScanBody(body);
      expect(body.startsWith(capped), isTrue);
      expect(capped.endsWith('TAIL'), isFalse);
    });

    test('capping is idempotent', () {
      final once = SmsParser.capScanBody('c' * 90000);
      expect(SmsParser.capScanBody(once), once);
    });

    test('capping never lengthens a body', () {
      for (final length in [0, 5, cap - 1, cap, cap + 1, 12345]) {
        final body = 'd' * length;
        expect(
          SmsParser.capScanBody(body).length,
          lessThanOrEqualTo(body.length),
        );
      }
    });

    test('an emoji straddling the boundary does not blow up', () {
      // Emoji are surrogate pairs, so the cut can land mid-character. It must
      // truncate, not throw, and the result must still be parseable.
      final body = '${'e' * (cap - 1)}😀 and more';
      final capped = SmsParser.capScanBody(body);
      expect(capped.length, cap);
      expect(() => SmsParser.isRealTransactionSms('AD-HDFCBK', capped),
          returnsNormally);
    });

    test('a body of nothing but newlines is handled', () {
      expect(SmsParser.capScanBody('\n' * 50000).length, cap);
      expect(SmsParser.capScanBody('\r\n' * 3), '\r\n\r\n\r\n');
    });
  });

  group('every scan entry point stops at the cap', () {
    /// A body that already fills the cap with a complete, genuine alert, so the
    /// only difference between two variants is what nobody should be reading.
    String headThenTail(String tail) =>
        '$realAlert${' filler' * 400}'.substring(0, cap) + tail;

    test('promo detection ignores everything past the cap', () {
      expect(
        SmsParser.isPromoOrOfferSms(headThenTail('pre-approved loan offer')),
        SmsParser.isPromoOrOfferSms(headThenTail('nothing to see here')),
      );
    });

    test('the real-transaction filter ignores everything past the cap', () {
      expect(
        SmsParser.isRealTransactionSms(
          'AD-HDFCBK-S',
          headThenTail('UPI payment has failed and is refunded'),
        ),
        SmsParser.isRealTransactionSms(
          'AD-HDFCBK-S',
          headThenTail('nothing to see here'),
        ),
      );
    });

    test('extraction ignores everything past the cap', () {
      final withTail = SmsParser.parseTransaction(
        craft(headThenTail(' Rs. 99,999.00 debited from a/c **1111')),
      );
      final withoutTail =
          SmsParser.parseTransaction(craft(headThenTail(' plain')));
      expect(withTail?.amount, withoutTail?.amount);
    });

    test('a genuine alert followed by a huge junk tail still parses', () {
      // The realistic shape: a concatenated multipart SMS whose first segment
      // is the alert. The facts are at the front, so nothing is lost.
      final result = SmsScanPipeline.process(
        craft('$realAlert ${'padding ' * 20000}'),
      );
      expect(result.outcome, SmsPipelineOutcome.parsed);
      expect(result.transaction?.amount, 2450.0);
      expect(result.transaction?.merchant, isNotEmpty);
    });

    test('facts pushed past the cap are simply not seen', () {
      // The accepted trade-off, asserted so it stays a decision rather than a
      // surprise: no bank buries the amount 2 kB into a message.
      final buried = craft('HDFC Bank a/c update. ${'filler ' * 400}$realAlert');
      expect(buried.body.length, greaterThan(cap));
      expect(SmsParser.parseTransaction(buried), isNull);
    });

    test('the same alert inside the cap does parse', () {
      expect(SmsParser.parseTransaction(craft(realAlert))?.amount, 2450.0);
    });
  });

  group('a crafted inbox cannot stall a scan', () {
    // The three shapes that measurably blew up pre-cap, now across sizes: the
    // point of the cap is that cost stops tracking body length at all.
    final shapes = <String, String Function(int)>{
      'paired .* patterns': (n) =>
          'HDFC Bank debited ${'payment of INR 1.00 received towards your ' * n}',
      'credited-with-rs pair': (n) =>
          'HDFC Bank ${'credited with Rs 1,00 against reversa ' * n}',
      'cashback .+ pair': (n) =>
          'HDFC Bank ${'cashback of INR 1.00 credited to you ' * n}',
    };

    for (final shape in shapes.entries) {
      test('${shape.key} costs the same at 8 kB as at 168 kB', () {
        // The invariant the cap buys is that cost stops tracking body length.
        // Comparing two sizes to each other rather than to a wall-clock budget
        // keeps this meaningful on a loaded machine: both measurements pay the
        // same contention, and pre-cap this ratio was ~50x, not ~1x.
        final small = shape.value(200);
        final large = shape.value(4000);
        expect(small.length, greaterThan(cap));
        expect(large.length, greaterThan(small.length * 15));

        final smallCost = _costOf(() => SmsScanPipeline.process(craft(small)));
        final largeCost = _costOf(() => SmsScanPipeline.process(craft(large)));

        expect(
          largeCost,
          lessThan(smallCost * 6 + 250000),
          reason: '20x the body cost ${largeCost}us against ${smallCost}us — '
              'parse cost is tracking body length again',
        );
      });
    }

    test('an inbox full of oversized messages costs what their prefixes cost',
        () {
      // One slow message is a stalled scan, so the guarantee is checked over a
      // batch: 100 oversized bodies must cost what their capped prefixes cost,
      // i.e. everything past the cap is free. Before the cap these hundred
      // messages took about ten minutes.
      final crafted =
          'HDFC Bank debited ${'payment of INR 1.00 received towards your ' * 1000}';
      final prefix = SmsParser.capScanBody(crafted);

      int costOfHundred(String body) => _costOf(() {
            for (var i = 0; i < 100; i++) {
              SmsScanPipeline.process(craft(body));
            }
          });

      final prefixCost = costOfHundred(prefix);
      final fullCost = costOfHundred(crafted);

      expect(fullCost, lessThan(prefixCost * 4 + 500000));
    });

    test('the gates that run before the cap stay linear too', () {
      // The OTP and sender checks see the raw body, so they have to be plain
      // `contains` / anchored matches rather than anything that backtracks.
      const otp = 'OTP is 123456. Do not share. ';
      final short = '$otp${'x' * 2000}';
      final huge = '$otp${'x' * 200000}';

      expect(
        SmsScanPipeline.process(craft(huge)).outcome,
        SmsPipelineOutcome.otpOnly,
      );

      final shortCost = _costOf(() => SmsScanPipeline.process(craft(short)));
      final hugeCost = _costOf(() => SmsScanPipeline.process(craft(huge)));

      expect(hugeCost, lessThan(shortCost * 25 + 250000));
    });

    test('account discovery stays bounded on a capped body', () {
      // Discovery runs its own `.*`-heavy patterns and does not cap by itself —
      // it relies on the reader boundary, so it must stay cheap at the cap.
      final crafted = SmsParser.capScanBody(
        'HDFC Bank ${'credited with Rs 1,00 against reversa ' * 4000}',
      );

      final realCost = _costOf(
        () => AccountDiscovery.discover(sender: 'AD-HDFCBK-S', body: realAlert),
      );
      final craftedCost = _costOf(
        () => AccountDiscovery.discover(sender: 'AD-HDFCBK-S', body: crafted),
      );

      expect(craftedCost, lessThan(realCost * 50 + 250000));
    });

    test('the cap changes the cost, not the verdict', () {
      // Whatever the pipeline decides about a crafted body, it must decide the
      // same thing for its capped prefix — the cap is a performance guard, not
      // a second, hidden classifier.
      for (final shape in shapes.entries) {
        final body = shape.value(4000);
        final full = SmsScanPipeline.process(craft(body));
        final capped = SmsScanPipeline.process(
          craft(SmsParser.capScanBody(body)),
        );

        expect(capped.outcome, full.outcome, reason: shape.key);
        expect(capped.transaction?.amount, full.transaction?.amount,
            reason: shape.key);
      }
    });
  });

  group('the scan boundary caps, the display path does not', () {
    final reader =
        File('lib/services/sms/sms_reader_service.dart').readAsStringSync();

    test('rows handed to the scan stages are capped at the boundary', () {
      // Discovery and enrichment regex over these rows without going through
      // SmsParser, so the guard has to sit at the reader, not only inside it.
      expect(reader.contains('SmsParser.capScanBody'), isTrue);
    });

    test('the cap is applied at exactly one place in the reader', () {
      expect(
        reader.split('SmsParser.capScanBody').length - 1,
        1,
        reason: 'an extra cap site is probably on a display path',
      );
    });

    test('the single-message read used by Coin Flip does not cap', () {
      final lookup = reader.indexOf('Future<SmsMessageInput?> getSmsById');
      final batch = reader.indexOf('fetchFilteredBatch');
      final capSite = reader.indexOf('SmsParser.capScanBody');

      expect(lookup, greaterThan(-1));
      expect(
        capSite,
        greaterThan(batch),
        reason: 'the cap must live in the batch scan path',
      );
      expect(
        reader.substring(lookup, batch).contains('capScanBody'),
        isFalse,
        reason: 'truncating here would show the customer a clipped SMS',
      );
    });

    // A real, if unusually chatty, concatenated alert: longer than the scan
    // cap, and the customer is entitled to read all of it.
    final longBody = '$realAlert ${'Terms and conditions. ' * 200}';

    Future<void> openReverse(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = await AppSettings.load();

      tester.view.physicalSize = const Size(400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildTestApp(
          settings: settings,
          child: TransactionCoinSlab(
            transaction: Transaction(
              id: 'txn-1',
              smsId: 'sms-1',
              merchant: 'Swiggy',
              bank: 'HDFC',
              maskedAccount: '••••5300',
              category: SpendCategory.food,
              amount: 2450,
              isCredit: false,
              timestamp: DateTime(2026, 7, 12, 9, 30),
            ),
            loader: (_) async => OriginalSmsLookup.loaded(
              OriginalSms(
                id: 'sms-1',
                sender: 'HDFCBK',
                body: longBody,
                timestamp: DateTime(2026, 7, 12, 9, 30),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('FLIP TO SMS'));
      await tester.pumpAndSettle();
    }

    testWidgets('the Coin Flip reverse shows an over-cap SMS in full',
        (tester) async {
      expect(longBody.length, greaterThan(cap));
      await openReverse(tester);

      expect(find.text(longBody), findsOneWidget);
    });

    testWidgets('copying the alert copies every character of it',
        (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await openReverse(tester);
      await tester.tap(find.text('COPY SMS'));
      await tester.pumpAndSettle();

      expect(copied, longBody);
    });
  });
}

/// Microseconds [work] takes, after one warm-up run so the pattern list and
/// the JIT are not being timed instead of the parse.
int _costOf(void Function() work) {
  work();
  final watch = Stopwatch()..start();
  work();
  return (watch..stop()).elapsedMicroseconds;
}
