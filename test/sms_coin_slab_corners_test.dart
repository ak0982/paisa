import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/models/transaction.dart';
import 'package:paisa_app/providers/app_settings.dart';
import 'package:paisa_app/providers/finance_store.dart';
import 'package:paisa_app/screens/day_strip_screen.dart';
import 'package:paisa_app/services/sms/account_discovery.dart';
import 'package:paisa_app/services/sms/original_sms_lookup.dart';
import 'package:paisa_app/services/sms/sms_reader_service.dart';
import 'package:paisa_app/theme/paisa_colors.dart';
import 'package:paisa_app/utils/formatters.dart';
import 'package:paisa_app/widgets/grouped_transaction_list.dart';
import 'package:paisa_app/widgets/paisa_coin.dart';
import 'package:paisa_app/widgets/sms_coin_slab.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/test_harness.dart';

/// Corner cases for the Coin Flip / Mint Slab transaction detail, written from
/// the customer's side of the glass: the face must state the *right money*, the
/// reverse must show the *real bank SMS* verbatim, and every way that read can
/// fail must land on struck copy instead of a blank field, a raw platform error
/// or a loading bar that never stops.
///
/// All fixtures are synthetic — no device inbox, no personal data.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppSettings settings;
  final when = DateTime(2026, 8, 15, 12, 4);

  // ── Synthetic bodies ──────────────────────────────────────────────────────

  const debitBody =
      'Dear Customer, Rs.320.58 debited from HDFC Bank A/c XX1234 on '
      '15-08-26 to VPA testmerchant@ybl. Not you? Call 18002586161. '
      'Avl Bal: Rs.11,204.12';

  const creditBody =
      'Rs.45,000.00 credited to A/c XX1234 on 15-08-26 by NEFT from '
      'TEST EMPLOYER LLP. Avl Bal Rs.61,204.12';

  const shortBody = 'Rs.5 debited A/c XX1234';

  const unicodeBody =
      'प्रिय ग्राहक, आपके खाते XX1234 से ₹320.58 डेबिट किए गए। '
      'शेष राशि: ₹11,204.12। धन्यवाद।';

  const specialCharsBody =
      'Txn of ₹1,234.56 @ "CAFE & CO." <ref#98-76/54> — 100% settled; '
      r'call +91-1800-000-000 [do not reply] {ref: a\b|c}';

  const multiParagraphBody =
      'Dear Customer,\n\n'
      'Rs.11,254.82 has been debited from your HDFC Bank Credit Card '
      'XX9012 on 15-08-26 at 12:04.\n\n'
      'Available limit: Rs.1,88,745.18\n'
      'Total limit: Rs.2,00,000.00\n\n'
      'If this was not you, call 1800 000 0000 immediately or block the card '
      'from the app.\n\n'
      'Regards,\nTest Bank';

  final longBody = List.generate(
    32,
    (i) => 'Line ${i + 1}: Rs.${(i + 1) * 11}.05 debited from A/c XX1234 '
        'towards synthetic test entry number ${i + 1} of thirty-two.',
  ).join('\n');

  // ── Fixtures ──────────────────────────────────────────────────────────────

  Transaction txn({
    String? smsId = 'sms-1',
    bool isCredit = false,
    double amount = 320.58,
    String merchant = 'Swiggy',
    String bank = 'HDFC',
    String mask = '••••1234',
    SpendCategory category = SpendCategory.food,
    AccountKind kind = AccountKind.savings,
    DateTime? timestamp,
  }) =>
      Transaction(
        id: 'txn-1',
        smsId: smsId,
        merchant: merchant,
        bank: bank,
        maskedAccount: mask,
        category: category,
        amount: amount,
        isCredit: isCredit,
        timestamp: timestamp ?? when,
        accountKind: kind,
      );

  OriginalSmsLookup loadedOf(
    String body, {
    String sender = 'HDFCBK',
    DateTime? at,
  }) =>
      OriginalSmsLookup.loaded(
        OriginalSms(
          id: 'sms-1',
          sender: sender,
          body: body,
          timestamp: at ?? when,
        ),
      );

  OriginalSmsLoader loaderOf(OriginalSmsLookup result) => (_) async => result;

  final debitLookup = loadedOf(debitBody);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await AppSettings.load();
  });

  // ── Harness ───────────────────────────────────────────────────────────────

  Future<void> pumpSlab(
    WidgetTester tester, {
    required Transaction transaction,
    OriginalSmsLoader? loader,
    bool isMove = false,
  }) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildTestApp(
        settings: settings,
        child: TransactionCoinSlab(
          transaction: transaction,
          isMove: isMove,
          loader: loader,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Opens the sheet the way the app does, through `showTransactionCoinSlab`.
  Future<void> openSheet(
    WidgetTester tester, {
    required Transaction transaction,
    OriginalSmsLoader? loader,
    bool isMove = false,
  }) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildTestApp(
        settings: settings,
        child: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => showTransactionCoinSlab(
              ctx,
              transaction,
              isMove: isMove,
              loader: loader,
            ),
            child: const Text('OPEN COIN'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('OPEN COIN'));
    await tester.pumpAndSettle();
  }

  Future<void> flipToSms(WidgetTester tester) async {
    await tester.tap(find.text('FLIP TO SMS'));
    await tester.pumpAndSettle();
  }

  Future<void> flipToCoin(WidgetTester tester) async {
    await tester.tap(find.text('FLIP TO COIN'));
    await tester.pumpAndSettle();
  }

  /// The COPY SMS chrome is a plain `GestureDetector`; a null `onTap` plus the
  /// muted label is exactly what the customer sees as "greyed out".
  bool copyEnabled(WidgetTester tester) {
    final button = tester.widget<GestureDetector>(
      find
          .ancestor(
            of: find.text('COPY SMS'),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    return button.onTap != null;
  }

  Color? amountColorOf(WidgetTester tester, double amount) =>
      tester.widget<Text>(find.text(formatInr(amount))).style?.color;

  PaisaCoinFace coinFace(WidgetTester tester) =>
      tester.widget<PaisaCoinFace>(find.byType(PaisaCoinFace));

  /// Captures whatever the sheet puts on the clipboard.
  List<String?> mockClipboard(WidgetTester tester) {
    final copied = <String?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String?);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    return copied;
  }

  // ══ A. The face states the exact money ═══════════════════════════════════

  group('face — money struck to the exact paise', () {
    const cases = <(double, String)>[
      (0.01, '₹0.01'),
      (0.50, '₹0.50'),
      (0.85, '₹0.85'),
      (1, '₹1.00'),
      (99.99, '₹99.99'),
      (444.00, '₹444.00'),
      (11254.82, '₹11,254.82'),
      (100000, '₹1,00,000.00'),
      (1234567.89, '₹12,34,567.89'),
      (50000000, '₹5,00,00,000.00'),
    ];

    for (final (amount, expected) in cases) {
      testWidgets('$amount is struck as $expected', (tester) async {
        await pumpSlab(
          tester,
          transaction: txn(amount: amount),
          loader: loaderOf(debitLookup),
        );

        expect(find.text(expected), findsOneWidget);
        expect(formatInr(amount), expected);
        // Never a rounded-away or truncated variant of the same money.
        expect(find.text(expected.split('.').first), findsNothing);
      });
    }
  });

  // ══ B. Direction: OUT white vs IN lime, and MOVE ═════════════════════════

  group('face — direction, gauge and MOVE', () {
    testWidgets('debit reads OUT and never IN', (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(),
        loader: loaderOf(debitLookup),
      );

      expect(find.text('OUT'), findsOneWidget);
      expect(find.text('IN'), findsNothing);
    });

    testWidgets('credit reads IN and never OUT', (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(isCredit: true, amount: 45000),
        loader: loaderOf(loadedOf(creditBody)),
      );

      expect(find.text('IN'), findsOneWidget);
      expect(find.text('OUT'), findsNothing);
    });

    testWidgets('debit amount is inked in the debit colour', (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(),
        loader: loaderOf(debitLookup),
      );

      expect(amountColorOf(tester, 320.58), PaisaColors.debit);
    });

    testWidgets('credit amount is inked lime', (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(isCredit: true, amount: 45000),
        loader: loaderOf(loadedOf(creditBody)),
      );

      expect(amountColorOf(tester, 45000), PaisaColors.credit);
    });

    testWidgets('internal movement mutes the amount instead of ink/lime',
        (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(merchant: 'CCBP HDFC card'),
        isMove: true,
        loader: loaderOf(debitLookup),
      );

      expect(amountColorOf(tester, 320.58), PaisaColors.mutedCaption);
      expect(amountColorOf(tester, 320.58), isNot(PaisaColors.debit));
    });

    testWidgets('debit strikes the gauge fully OUT', (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(),
        loader: loaderOf(debitLookup),
      );

      expect(coinFace(tester).outShare, 1.0);
      expect(coinFace(tester).hasFlow, isTrue);
    });

    testWidgets('credit strikes the gauge fully IN', (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(isCredit: true),
        loader: loaderOf(loadedOf(creditBody)),
      );

      expect(coinFace(tester).outShare, 0.0);
      expect(coinFace(tester).hasFlow, isTrue);
    });

    testWidgets('MOVE leaves the gauge idle and stamps the chip',
        (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(merchant: 'Credit card bill payment'),
        isMove: true,
        loader: loaderOf(debitLookup),
      );

      expect(coinFace(tester).hasFlow, isFalse);
      expect(find.text('MOVE'), findsOneWidget);
    });

    testWidgets('an ordinary spend is never stamped MOVE', (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(),
        loader: loaderOf(debitLookup),
      );

      expect(find.text('MOVE'), findsNothing);
    });

    testWidgets('credit-card spend carries the CC SPEND legend',
        (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(kind: AccountKind.creditCard),
        loader: loaderOf(debitLookup),
      );

      expect(coinFace(tester).topLegend, 'CC SPEND');
    });

    testWidgets('loan EMI carries the LOAN EMI PAID legend', (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(kind: AccountKind.loan, merchant: 'EMI'),
        loader: loaderOf(debitLookup),
      );

      expect(coinFace(tester).topLegend, 'LOAN EMI PAID');
    });
  });

  // ══ C. Whose money, and from where ══════════════════════════════════════

  group('face — account identity', () {
    testWidgets('bank and mask are struck together when the mask is real',
        (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(),
        loader: loaderOf(debitLookup),
      );

      expect(find.text('HDFC · ••••1234'), findsOneWidget);
    });

    testWidgets('an unknown ???? mask never reaches the customer',
        (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(mask: '••••????'),
        loader: loaderOf(debitLookup),
      );

      expect(find.textContaining('????'), findsNothing);
      expect(find.text('HDFC'), findsOneWidget);
    });

    testWidgets('a missing mask degrades to the bank name alone',
        (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(mask: ''),
        loader: loaderOf(debitLookup),
      );

      expect(find.text('HDFC'), findsOneWidget);
      expect(find.textContaining('·'), findsWidgets); // meta line still there
    });

    testWidgets('date and time of the transaction are shown below the coin',
        (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(),
        loader: loaderOf(debitLookup),
      );

      expect(find.text('15 Aug 2026 · 12:04'), findsOneWidget);
    });

    testWidgets('flow and category are spelled out under the date',
        (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(kind: AccountKind.creditCard),
        loader: loaderOf(debitLookup),
      );

      expect(find.text('CC spend · Food'), findsOneWidget);
    });

    testWidgets('a very long merchant is clamped to two lines, not cut mid-run',
        (tester) async {
      const long = 'PAYTM*SUPERMARKET AND GENERAL STORES PRIVATE LIMITED '
          'MUMBAI MAHARASHTRA IN';
      await pumpSlab(
        tester,
        transaction: txn(merchant: long),
        loader: loaderOf(debitLookup),
      );

      final label = tester.widget<Text>(find.text(long));
      expect(label.maxLines, 2);
      expect(label.overflow, TextOverflow.ellipsis);
    });

    testWidgets('a Unicode merchant name is struck as-is', (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(merchant: 'कैफे कॉफी'),
        loader: loaderOf(debitLookup),
      );

      expect(find.text('कैफे कॉफी'), findsOneWidget);
    });

    testWidgets('the sheet identifies itself as the PAISA MINT', (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(),
        loader: loaderOf(debitLookup),
      );

      expect(find.text('PAISA'), findsOneWidget);
      expect(find.text('MINT'), findsOneWidget);
    });
  });

  // ══ D. The reverse shows the real SMS, verbatim ═════════════════════════

  group('reverse — the original SMS, verbatim', () {
    testWidgets('the whole body is shown after the flip', (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(),
        loader: loaderOf(debitLookup),
      );
      await flipToSms(tester);

      expect(find.text('ORIGINAL SMS'), findsOneWidget);
      expect(find.text(debitBody), findsOneWidget);
    });

    testWidgets('the sender is stamped in caps', (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(),
        loader: loaderOf(loadedOf(debitBody, sender: 'VM-HdfcBk')),
      );
      await flipToSms(tester);

      expect(find.text('VM-HDFCBK'), findsOneWidget);
    });

    testWidgets('a missing sender simply leaves no stamp', (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(),
        loader: loaderOf(loadedOf(debitBody, sender: '')),
      );
      await flipToSms(tester);

      expect(find.text('ORIGINAL SMS'), findsOneWidget);
      expect(find.text(debitBody), findsOneWidget);
      expect(find.byType(Tooltip), findsWidgets); // chrome intact
    });

    testWidgets('a whitespace-only sender is treated as no sender',
        (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(),
        loader: loaderOf(loadedOf(debitBody, sender: '   ')),
      );
      await flipToSms(tester);

      expect(find.text('   '), findsNothing);
      expect(find.text(debitBody), findsOneWidget);
    });

    testWidgets('the receive time of the alert is stamped on the slab',
        (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(),
        loader: loaderOf(
          loadedOf(debitBody, at: DateTime(2026, 8, 15, 9, 7)),
        ),
      );
      await flipToSms(tester);

      expect(find.text('RECEIVED 15 AUG 2026 · 09:07'), findsOneWidget);
    });

    testWidgets('a missing date column never becomes RECEIVED 1 JAN 1970',
        (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(),
        loader: loaderOf(
          loadedOf(debitBody, at: DateTime.fromMillisecondsSinceEpoch(0)),
        ),
      );
      await flipToSms(tester);

      expect(find.textContaining('RECEIVED'), findsNothing);
      expect(find.textContaining('1970'), findsNothing);
      // The body still gets through — only the bogus stamp is dropped.
      expect(find.text(debitBody), findsOneWidget);
    });

    testWidgets('the body is selectable so it can be read out or shared',
        (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(),
        loader: loaderOf(debitLookup),
      );
      await flipToSms(tester);

      final field = tester.widget<SelectableText>(find.byType(SelectableText));
      expect(field.data, debitBody);
    });

    testWidgets('a long multi-paragraph alert is scrollable, not clipped away',
        (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(),
        loader: loaderOf(loadedOf(longBody)),
      );
      await flipToSms(tester);

      expect(find.byType(Scrollbar), findsOneWidget);
      expect(
        tester.widget<SelectableText>(find.byType(SelectableText)).data,
        longBody,
      );
      expect(longBody.length, greaterThan(1200));
    });

    testWidgets('newlines and blank lines in a bank alert are preserved',
        (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(amount: 11254.82, kind: AccountKind.creditCard),
        loader: loaderOf(loadedOf(multiParagraphBody)),
      );
      await flipToSms(tester);

      expect(
        tester.widget<SelectableText>(find.byType(SelectableText)).data,
        multiParagraphBody,
      );
      expect(multiParagraphBody, contains('\n\n'));
    });

    testWidgets('Hindi text and the ₹ symbol survive the round trip',
        (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(),
        loader: loaderOf(loadedOf(unicodeBody)),
      );
      await flipToSms(tester);

      expect(find.text(unicodeBody), findsOneWidget);
      expect(unicodeBody, contains('₹'));
    });

    testWidgets('quotes, braces and slashes are not escaped or dropped',
        (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(),
        loader: loaderOf(loadedOf(specialCharsBody)),
      );
      await flipToSms(tester);

      expect(
        tester.widget<SelectableText>(find.byType(SelectableText)).data,
        specialCharsBody,
      );
    });

    testWidgets('a one-line alert is shown without padding it out',
        (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(amount: 5),
        loader: loaderOf(loadedOf(shortBody)),
      );
      await flipToSms(tester);

      expect(find.text(shortBody), findsOneWidget);
    });

    testWidgets('masking the merchant never redacts the SMS body',
        (tester) async {
      await settings.setMaskMerchantNames(true);
      const bodyWithMerchant =
          'Rs.320.58 debited to VPA swiggy@ybl from A/c XX1234';

      await pumpSlab(
        tester,
        transaction: txn(),
        loader: loaderOf(loadedOf(bodyWithMerchant)),
      );

      expect(find.text('Sw••••gy'), findsOneWidget);
      expect(find.text('Swiggy'), findsNothing);

      await flipToSms(tester);
      expect(find.text(bodyWithMerchant), findsOneWidget);
    });
  });

  // ══ E. Never a blank field, never a raw error ════════════════════════════

  group('reverse — every miss lands on struck copy', () {
    const missStatuses = <OriginalSmsStatus>[
      OriginalSmsStatus.noSmsId,
      OriginalSmsStatus.notFound,
      OriginalSmsStatus.noPermission,
      OriginalSmsStatus.unsupportedPlatform,
      OriginalSmsStatus.emptyBody,
      OriginalSmsStatus.lookupFailed,
    ];

    for (final status in missStatuses) {
      testWidgets('${status.name} explains itself in plain words',
          (tester) async {
        await pumpSlab(
          tester,
          transaction: txn(),
          loader: loaderOf(OriginalSmsLookup.miss(status)),
        );
        await flipToSms(tester);

        final copy = originalSmsEmptyCopy(status);
        expect(find.text(copy.title), findsOneWidget);
        expect(find.text(copy.body), findsOneWidget);
        expect(find.text(debitBody), findsNothing);
      });
    }

    testWidgets('an inbox row with an empty body says so instead of showing '
        'nothing', (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(),
        loader: loaderOf(loadedOf('')),
      );
      await flipToSms(tester);

      expect(find.text('Alert has no text'), findsOneWidget);
      // Regression: the reverse used to render two empty strings.
      expect(find.text(''), findsNothing);
    });

    testWidgets('a whitespace-only body is treated as no text', (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(),
        loader: loaderOf(loadedOf('   \n  \t ')),
      );
      await flipToSms(tester);

      expect(find.text('Alert has no text'), findsOneWidget);
      expect(copyEnabled(tester), isFalse);
    });

    testWidgets('a read that throws lands on "Could not read the inbox"',
        (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(),
        loader: (_) async => throw PlatformException(code: 'SMS_READ_FAILED'),
      );
      await flipToSms(tester);

      expect(find.text('Could not read the inbox'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a read that throws never leaves the reading bar spinning',
        (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(),
        loader: (_) async => throw StateError('inbox exploded'),
      );
      await flipToSms(tester);

      expect(find.text('READING THE INBOX'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('while the inbox is being read the customer sees progress',
        (tester) async {
      final gate = Completer<OriginalSmsLookup>();
      await pumpSlab(
        tester,
        transaction: txn(),
        loader: (_) => gate.future,
      );

      await tester.tap(find.text('FLIP TO SMS'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.text('READING THE INBOX'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      gate.complete(debitLookup);
      await tester.pump();
      await tester.pump();
      expect(find.text(debitBody), findsOneWidget);
    });

    testWidgets('an entry that never came from an SMS says so up front',
        (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(smsId: null),
        loader: loaderOf(debitLookup),
      );
      await flipToSms(tester);

      expect(find.text('Minted by you'), findsOneWidget);
      expect(find.text(debitBody), findsNothing);
    });

    testWidgets('an empty smsId string behaves like no smsId at all',
        (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(smsId: ''),
        loader: loaderOf(debitLookup),
      );
      await flipToSms(tester);

      expect(find.text('Minted by you'), findsOneWidget);
    });

    testWidgets('an empty reverse still keeps the coin usable', (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(),
        loader: loaderOf(
          const OriginalSmsLookup.miss(OriginalSmsStatus.notFound),
        ),
      );
      await flipToSms(tester);
      await flipToCoin(tester);

      expect(find.text('Swiggy'), findsOneWidget);
      expect(find.text(formatInr(320.58)), findsOneWidget);
    });
  });

  // ══ F. Flip mechanics ═══════════════════════════════════════════════════

  group('flip mechanics', () {
    testWidgets('the button flips the coin to the SMS', (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(),
        loader: loaderOf(debitLookup),
      );
      await flipToSms(tester);

      expect(find.text(debitBody), findsOneWidget);
      expect(find.text('Swiggy'), findsNothing);
    });

    testWidgets('the button flips back to the coin', (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(),
        loader: loaderOf(debitLookup),
      );
      await flipToSms(tester);
      await flipToCoin(tester);

      expect(find.text('Swiggy'), findsOneWidget);
      expect(find.text(debitBody), findsNothing);
    });

    testWidgets('the flip button relabels itself with the destination',
        (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(),
        loader: loaderOf(debitLookup),
      );

      expect(find.text('FLIP TO SMS'), findsOneWidget);
      expect(find.text('FLIP TO COIN'), findsNothing);

      await flipToSms(tester);

      expect(find.text('FLIP TO COIN'), findsOneWidget);
      expect(find.text('FLIP TO SMS'), findsNothing);
    });

    testWidgets('tapping the coin itself flips it', (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(),
        loader: loaderOf(debitLookup),
      );

      await tester.tap(find.text(formatInr(320.58)));
      await tester.pumpAndSettle();

      expect(find.text(debitBody), findsOneWidget);
    });

    testWidgets('tapping the slab legend does not flip the coin away',
        (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(),
        loader: loaderOf(debitLookup),
      );
      await flipToSms(tester);

      await tester.tap(find.text('ORIGINAL SMS'));
      await tester.pumpAndSettle();

      expect(find.text(debitBody), findsOneWidget);
    });

    testWidgets('a swipe across the coin flips it', (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(),
        loader: loaderOf(debitLookup),
      );

      final stage = tester.getCenter(find.byType(PaisaCoinFace));
      await tester.timedDragFrom(
        stage,
        const Offset(-240, 0),
        const Duration(milliseconds: 200),
      );
      await tester.pumpAndSettle();

      expect(find.text(debitBody), findsOneWidget);
    });

    testWidgets('a swipe on the slab chrome flips back to the face',
        (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(),
        loader: loaderOf(debitLookup),
      );
      await flipToSms(tester);

      await tester.timedDragFrom(
        tester.getCenter(find.text('ORIGINAL SMS')),
        const Offset(240, 0),
        const Duration(milliseconds: 200),
      );
      await tester.pumpAndSettle();

      expect(find.text('Swiggy'), findsOneWidget);
      expect(find.text(debitBody), findsNothing);
    });

    testWidgets('dragging across the SMS text selects it instead of flipping '
        'the coin away', (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(),
        loader: loaderOf(debitLookup),
      );
      await flipToSms(tester);

      await tester.timedDragFrom(
        tester.getCenter(find.byType(SelectableText)),
        const Offset(200, 0),
        const Duration(milliseconds: 200),
      );
      await tester.pumpAndSettle();

      // The body stays put — a customer highlighting a reference number must
      // not lose the message mid-drag.
      expect(find.text(debitBody), findsOneWidget);
      expect(find.text('Swiggy'), findsNothing);
    });

    testWidgets('a lazy drag below the flick threshold keeps the face up',
        (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(),
        loader: loaderOf(debitLookup),
      );

      final stage = tester.getCenter(find.byType(PaisaCoinFace));
      await tester.timedDragFrom(
        stage,
        const Offset(-40, 0),
        const Duration(milliseconds: 700),
      );
      await tester.pumpAndSettle();

      expect(find.text('Swiggy'), findsOneWidget);
      expect(find.text(debitBody), findsNothing);
    });

    testWidgets('two fast taps on FLIP still settle on the SMS, not mid-air',
        (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(),
        loader: loaderOf(debitLookup),
      );

      await tester.tap(find.text('FLIP TO SMS'));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(find.text('FLIP TO SMS'));
      await tester.pumpAndSettle();

      expect(find.text(debitBody), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('flipping mid-animation does not throw', (tester) async {
      await pumpSlab(
        tester,
        transaction: txn(),
        loader: loaderOf(debitLookup),
      );

      await tester.tap(find.text('FLIP TO SMS'));
      await tester.pump(const Duration(milliseconds: 280));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();

      expect(find.text(debitBody), findsOneWidget);
    });

    testWidgets('the close button dismisses the sheet', (tester) async {
      await openSheet(
        tester,
        transaction: txn(),
        loader: loaderOf(debitLookup),
      );
      expect(find.text('MINT'), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(find.text('MINT'), findsNothing);
      expect(find.text('OPEN COIN'), findsOneWidget);
    });
  });

  // ══ G. What the sheet asks the inbox for ════════════════════════════════

  group('inbox read contract', () {
    testWidgets('the inbox is read once per open', (tester) async {
      var calls = 0;
      await pumpSlab(
        tester,
        transaction: txn(),
        loader: (_) async {
          calls++;
          return debitLookup;
        },
      );

      expect(calls, 1);
    });

    testWidgets('the read uses the smsId kept for a collapsed twin',
        (tester) async {
      final asked = <String>[];
      await pumpSlab(
        tester,
        transaction: txn(smsId: 'kept-twin-77'),
        loader: (id) async {
          asked.add(id);
          return debitLookup;
        },
      );
      await flipToSms(tester);

      expect(asked, ['kept-twin-77']);
      expect(find.text(debitBody), findsOneWidget);
    });

    testWidgets('no smsId means the inbox is never touched', (tester) async {
      var calls = 0;
      await pumpSlab(
        tester,
        transaction: txn(smsId: null),
        loader: (_) async {
          calls++;
          return debitLookup;
        },
      );
      await flipToSms(tester);

      expect(calls, 0);
    });

    testWidgets('an empty smsId means the inbox is never touched',
        (tester) async {
      var calls = 0;
      await pumpSlab(
        tester,
        transaction: txn(smsId: ''),
        loader: (_) async {
          calls++;
          return debitLookup;
        },
      );

      expect(calls, 0);
    });

    testWidgets('flipping back and forth does not re-read the inbox',
        (tester) async {
      var calls = 0;
      await pumpSlab(
        tester,
        transaction: txn(),
        loader: (_) async {
          calls++;
          return debitLookup;
        },
      );

      await flipToSms(tester);
      await flipToCoin(tester);
      await flipToSms(tester);

      expect(calls, 1);
      expect(find.text(debitBody), findsOneWidget);
    });

    testWidgets('re-opening the same transaction shows the SMS again',
        (tester) async {
      await openSheet(
        tester,
        transaction: txn(),
        loader: loaderOf(debitLookup),
      );
      await flipToSms(tester);
      expect(find.text(debitBody), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('MINT'), findsNothing);

      // Second visit: the session cache must not break the reverse.
      await tester.tap(find.text('OPEN COIN'));
      await tester.pumpAndSettle();
      await flipToSms(tester);

      expect(find.text(debitBody), findsOneWidget);
      expect(find.text('READING THE INBOX'), findsNothing);
    });
  });

  // ══ H. Copy ═════════════════════════════════════════════════════════════

  group('copy the original SMS', () {
    testWidgets('copies the body exactly, byte for byte', (tester) async {
      final copied = mockClipboard(tester);
      await pumpSlab(
        tester,
        transaction: txn(),
        loader: loaderOf(debitLookup),
      );

      await tester.tap(find.text('COPY SMS'));
      await tester.pumpAndSettle();

      expect(copied, [debitBody]);
    });

    testWidgets('confirms the copy so the customer knows it worked',
        (tester) async {
      mockClipboard(tester);
      await pumpSlab(
        tester,
        transaction: txn(),
        loader: loaderOf(debitLookup),
      );

      await tester.tap(find.text('COPY SMS'));
      await tester.pumpAndSettle();

      expect(find.text('Original SMS copied'), findsOneWidget);
    });

    testWidgets('copy is greyed out while the inbox is still being read',
        (tester) async {
      final gate = Completer<OriginalSmsLookup>();
      await pumpSlab(
        tester,
        transaction: txn(),
        loader: (_) => gate.future,
      );

      expect(copyEnabled(tester), isFalse);
      expect(
        tester.widget<Text>(find.text('COPY SMS')).style?.color,
        PaisaColors.muted,
      );

      gate.complete(debitLookup);
      await tester.pumpAndSettle();
      expect(copyEnabled(tester), isTrue);
    });

    testWidgets('copy is inert when the alert is gone from the inbox',
        (tester) async {
      final copied = mockClipboard(tester);
      await pumpSlab(
        tester,
        transaction: txn(),
        loader: loaderOf(
          const OriginalSmsLookup.miss(OriginalSmsStatus.notFound),
        ),
      );

      await tester.tap(find.text('COPY SMS'));
      await tester.pumpAndSettle();

      expect(copied, isEmpty);
      expect(copyEnabled(tester), isFalse);
    });

    testWidgets('copy works from the coin side without flipping first',
        (tester) async {
      final copied = mockClipboard(tester);
      await pumpSlab(
        tester,
        transaction: txn(),
        loader: loaderOf(debitLookup),
      );

      expect(find.text('FLIP TO SMS'), findsOneWidget); // still on the face
      await tester.tap(find.text('COPY SMS'));
      await tester.pumpAndSettle();

      expect(copied, [debitBody]);
    });

    testWidgets('Unicode and newlines are copied intact', (tester) async {
      final copied = mockClipboard(tester);
      await pumpSlab(
        tester,
        transaction: txn(),
        loader: loaderOf(loadedOf('$unicodeBody\n$multiParagraphBody')),
      );

      await tester.tap(find.text('COPY SMS'));
      await tester.pumpAndSettle();

      expect(copied.single, '$unicodeBody\n$multiParagraphBody');
    });
  });

  // ══ I. Getting there from the lists ═════════════════════════════════════

  group('customer journeys into the coin', () {
    Transaction listTxn({
      required String id,
      required double amount,
      required bool isCredit,
      required SpendCategory category,
      String merchant = 'Test',
      String bank = 'SBI',
      String mask = '••••0429',
      AccountKind kind = AccountKind.savings,
      Duration offset = Duration.zero,
    }) =>
        Transaction(
          id: id,
          smsId: id,
          merchant: merchant,
          bank: bank,
          maskedAccount: mask,
          category: category,
          amount: amount,
          isCredit: isCredit,
          timestamp: DateTime(2026, 8, 15, 12).add(offset),
          accountKind: kind,
        );

    Future<void> pumpDayStrip(WidgetTester tester, FinanceStore store) async {
      tester.view.physicalSize = const Size(400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildTestApp(
          settings: settings,
          store: store,
          child: DayStripScreen(initialDay: DateTime(2026, 8, 15)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a Day Strip row opens the coin for that exact amount',
        (tester) async {
      final store = FinanceStore()
        ..seedTransactions([
          listTxn(
            id: 'a',
            amount: 320.58,
            isCredit: false,
            category: SpendCategory.food,
            merchant: 'Swiggy',
          ),
        ]);
      await pumpDayStrip(tester, store);

      await tester.tap(find.text('Swiggy'));
      await tester.pumpAndSettle();

      expect(find.text('MINT'), findsOneWidget);
      expect(find.text('FLIP TO SMS'), findsOneWidget);
      expect(find.text('SBI · ••••0429'), findsOneWidget);
      expect(find.text('₹320.58'), findsWidgets);
    });

    testWidgets('a Day Strip CC bill payment opens as MOVE', (tester) async {
      final store = FinanceStore()
        ..seedTransactions([
          listTxn(
            id: 'ccbp',
            amount: 5000,
            isCredit: false,
            category: SpendCategory.transfer,
            merchant: 'Credit card bill payment',
          ),
        ]);
      await pumpDayStrip(tester, store);

      // One badge in the list, one chip in the sheet after opening.
      expect(find.text('MOVE'), findsOneWidget);
      await tester.tap(find.text('Credit card bill payment'));
      await tester.pumpAndSettle();

      expect(find.text('MOVE'), findsNWidgets(2));
    });

    testWidgets('a self-transfer leg opens as MOVE too', (tester) async {
      final store = FinanceStore()
        ..seedTransactions([
          listTxn(
            id: 'xfer_out',
            amount: 1500.75,
            isCredit: false,
            category: SpendCategory.transfer,
            merchant: 'NEFT to Axis',
          ),
          listTxn(
            id: 'xfer_in',
            amount: 1500.75,
            isCredit: true,
            category: SpendCategory.income,
            bank: 'Axis',
            mask: '••••9867',
            merchant: 'Self Transfer',
            offset: const Duration(minutes: 1),
          ),
        ]);
      await pumpDayStrip(tester, store);

      expect(find.text('MOVE'), findsNWidgets(2));
      await tester.tap(find.text('NEFT to Axis'));
      await tester.pumpAndSettle();

      expect(find.text('MOVE'), findsNWidgets(3));
    });

    testWidgets('off Android the journey ends in friendly copy, not a crash',
        (tester) async {
      final store = FinanceStore()
        ..seedTransactions([
          listTxn(
            id: 'a',
            amount: 42.42,
            isCredit: false,
            category: SpendCategory.food,
            merchant: 'Snack',
          ),
        ]);
      await pumpDayStrip(tester, store);

      await tester.tap(find.text('Snack'));
      await tester.pumpAndSettle();
      await flipToSms(tester);

      expect(find.text('Inbox unavailable'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a grouped list row opens the coin', (tester) async {
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildTestApp(
          settings: settings,
          child: GroupedTransactionList(
            transactions: [
              listTxn(
                id: 'a',
                amount: 88.88,
                isCredit: false,
                category: SpendCategory.food,
                merchant: 'Cafe',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cafe'));
      await tester.pumpAndSettle();

      expect(find.text('MINT'), findsOneWidget);
      expect(find.text('₹88.88'), findsWidgets);
    });

    testWidgets('a screen that owns its own tap handler still wins',
        (tester) async {
      Transaction? tapped;
      await tester.pumpWidget(
        buildTestApp(
          settings: settings,
          child: GroupedTransactionList(
            transactions: [
              listTxn(
                id: 'a',
                amount: 10,
                isCredit: false,
                category: SpendCategory.food,
                merchant: 'Cafe',
              ),
            ],
            onTransactionTap: (t) => tapped = t,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cafe'));
      await tester.pumpAndSettle();

      expect(tapped?.id, 'a');
      expect(find.text('MINT'), findsNothing);
    });

    testWidgets('a recents row infers MOVE for a CC payment received',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          settings: settings,
          child: TransactionCoinTap(
            transaction: listTxn(
              id: 'ccin',
              amount: 5000,
              isCredit: true,
              category: SpendCategory.transfer,
              merchant: 'Payment received',
              kind: AccountKind.creditCard,
            ),
            child: const Text('RECENT ROW'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('RECENT ROW'));
      await tester.pumpAndSettle();

      expect(find.text('MOVE'), findsOneWidget);
      expect(find.text('MINT'), findsOneWidget);
    });

    testWidgets('an ordinary recents row opens without a MOVE chip',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          settings: settings,
          child: TransactionCoinTap(
            transaction: listTxn(
              id: 'plain',
              amount: 12.34,
              isCredit: false,
              category: SpendCategory.food,
              merchant: 'Cafe',
            ),
            child: const Text('RECENT ROW'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('RECENT ROW'));
      await tester.pumpAndSettle();

      expect(find.text('MINT'), findsOneWidget);
      expect(find.text('MOVE'), findsNothing);
    });
  });

  // ══ J. Lookup + status mapping (pure units) ═════════════════════════════

  group('OriginalSmsLookup', () {
    OriginalSms sms(String body) => OriginalSms(
          id: 'sms-1',
          sender: 'HDFCBK',
          body: body,
          timestamp: when,
        );

    test('a real body counts as having a body', () {
      expect(OriginalSmsLookup.loaded(sms(debitBody)).hasBody, isTrue);
    });

    test('an empty body does not count as having a body', () {
      expect(OriginalSmsLookup.loaded(sms('')).hasBody, isFalse);
    });

    test('a whitespace-only body does not count as having a body', () {
      expect(OriginalSmsLookup.loaded(sms(' \n\t ')).hasBody, isFalse);
    });

    test('no miss ever claims to have a body', () {
      for (final status in OriginalSmsStatus.values) {
        if (status == OriginalSmsStatus.loaded) continue;
        expect(
          OriginalSmsLookup.miss(status).hasBody,
          isFalse,
          reason: '$status',
        );
      }
    });

    test('a loaded body displays as loaded', () {
      expect(
        OriginalSmsLookup.loaded(sms(debitBody)).displayStatus,
        OriginalSmsStatus.loaded,
      );
    });

    test('a loaded-but-blank row displays as emptyBody', () {
      expect(
        OriginalSmsLookup.loaded(sms('')).displayStatus,
        OriginalSmsStatus.emptyBody,
      );
      expect(
        OriginalSmsLookup.loaded(sms('   ')).displayStatus,
        OriginalSmsStatus.emptyBody,
      );
    });

    test('misses display as themselves', () {
      for (final status in OriginalSmsStatus.values) {
        if (status == OriginalSmsStatus.loaded) continue;
        expect(
          OriginalSmsLookup.miss(status).displayStatus,
          status,
          reason: '$status',
        );
      }
    });

    test('the body is kept verbatim, newlines and all', () {
      final lookup = OriginalSmsLookup.loaded(sms(multiParagraphBody));
      expect(lookup.sms!.body, multiParagraphBody);
      expect(lookup.sms!.timestamp, when);
      expect(lookup.sms!.sender, 'HDFCBK');
    });

    test('every non-loaded status has distinct, non-empty copy', () {
      final titles = <String>{};
      for (final status in OriginalSmsStatus.values) {
        final copy = originalSmsEmptyCopy(status);
        if (status == OriginalSmsStatus.loaded) {
          expect(copy.title, isEmpty);
          continue;
        }
        expect(copy.title, isNotEmpty, reason: '$status title');
        expect(copy.body, isNotEmpty, reason: '$status body');
        expect(titles.add(copy.title), isTrue, reason: 'duplicate $status');
      }
    });

    test('no empty-state copy leaks developer language', () {
      const leaks = [
        'exception',
        'null',
        'error code',
        'platformexception',
        'stack',
      ];
      for (final status in OriginalSmsStatus.values) {
        final copy = originalSmsEmptyCopy(status);
        final text = '${copy.title} ${copy.body}'.toLowerCase();
        for (final leak in leaks) {
          expect(text.contains(leak), isFalse, reason: '$status leaks $leak');
        }
      }
    });
  });

  // ══ K. Reader-service contract (native edges documented) ════════════════

  group('SmsReaderService.loadOriginalSms', () {
    final reader = SmsReaderService();

    test('a null smsId is a no-SMS miss, never a channel call', () async {
      final lookup = await reader.loadOriginalSms(null);
      expect(lookup.status, OriginalSmsStatus.noSmsId);
      expect(lookup.sms, isNull);
    });

    test('an empty smsId is a no-SMS miss', () async {
      final lookup = await reader.loadOriginalSms('');
      expect(lookup.status, OriginalSmsStatus.noSmsId);
    });

    test('off Android the inbox is reported as unavailable', () async {
      final lookup = await reader.loadOriginalSms('4242');
      expect(lookup.status, OriginalSmsStatus.unsupportedPlatform);
      expect(lookup.hasBody, isFalse);
    });

    test('getSmsById refuses an empty id without touching the channel',
        () async {
      expect(await reader.getSmsById(''), isNull);
    });

    test('odd ids resolve to a status instead of throwing', () async {
      for (final id in ['0', '-1', 'not-a-number', '99999999999999999999']) {
        final lookup = await reader.loadOriginalSms(id);
        expect(lookup.hasBody, isFalse, reason: id);
        expect(
          lookup.status,
          isNot(OriginalSmsStatus.loaded),
          reason: id,
        );
      }
    });
  });
}
