import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/models/transaction.dart';
import 'package:paisa_app/providers/app_settings.dart';
import 'package:paisa_app/providers/finance_store.dart';
import 'package:paisa_app/screens/day_strip_screen.dart';
import 'package:paisa_app/services/sms/account_discovery.dart';
import 'package:paisa_app/services/sms/original_sms_lookup.dart';
import 'package:paisa_app/utils/formatters.dart';
import 'package:paisa_app/widgets/sms_coin_slab.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/test_harness.dart';

/// Coin Flip / Mint Slab transaction detail: the face carries the summary, the
/// reverse carries the full original bank SMS fetched on demand by `smsId`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppSettings settings;
  final when = DateTime(2026, 8, 15, 12, 4);

  const smsBody =
      'Dear Customer, Rs.320.58 debited from HDFC Bank A/c XX1234 on '
      '15-08-26 to VPA swiggy@ybl. Not you? Call 18002586161. '
      'Avl Bal: Rs.11,204.12';

  Transaction txn({
    String? smsId = 'sms-1',
    bool isCredit = false,
    double amount = 320.58,
    String merchant = 'Swiggy',
    AccountKind kind = AccountKind.savings,
  }) =>
      Transaction(
        id: 'txn-1',
        smsId: smsId,
        merchant: merchant,
        bank: 'HDFC',
        maskedAccount: '••••1234',
        category: SpendCategory.food,
        amount: amount,
        isCredit: isCredit,
        timestamp: when,
        accountKind: kind,
      );

  OriginalSmsLoader loaderOf(OriginalSmsLookup result) =>
      (_) async => result;

  final loadedLookup = OriginalSmsLookup.loaded(
    OriginalSms(
      id: 'sms-1',
      sender: 'HDFCBK',
      body: smsBody,
      timestamp: when,
    ),
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await AppSettings.load();
  });

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

  testWidgets('face mints amount, merchant and account before any flip',
      (tester) async {
    await pumpSlab(
      tester,
      transaction: txn(),
      loader: loaderOf(loadedLookup),
    );

    expect(find.text(formatInr(320.58)), findsOneWidget);
    expect(find.text('Swiggy'), findsOneWidget);
    expect(find.text('HDFC · ••••1234'), findsOneWidget);
    expect(find.text('OUT'), findsOneWidget);
    expect(find.text('PAISA'), findsOneWidget);
    expect(find.text('15 Aug 2026 · 12:04'), findsOneWidget);
    // The SMS lives on the reverse only.
    expect(find.text('ORIGINAL SMS'), findsNothing);
    expect(find.text(smsBody), findsNothing);
    expect(find.text('FLIP TO SMS'), findsOneWidget);
  });

  testWidgets('credit face labels IN', (tester) async {
    await pumpSlab(
      tester,
      transaction: txn(isCredit: true, merchant: 'Salary'),
      loader: loaderOf(loadedLookup),
    );

    expect(find.text('IN'), findsOneWidget);
    expect(find.text('Salary'), findsOneWidget);
  });

  testWidgets('flip reveals the full original SMS and its sender',
      (tester) async {
    await pumpSlab(
      tester,
      transaction: txn(),
      loader: loaderOf(loadedLookup),
    );

    await tester.tap(find.text('FLIP TO SMS'));
    await tester.pumpAndSettle();

    expect(find.text('ORIGINAL SMS'), findsOneWidget);
    expect(find.text('HDFCBK'), findsOneWidget);
    expect(find.text(smsBody), findsOneWidget);
    expect(find.text('RECEIVED 15 AUG 2026 · 12:04'), findsOneWidget);
    // Face content is turned away.
    expect(find.text('Swiggy'), findsNothing);
    expect(find.text('FLIP TO COIN'), findsOneWidget);
  });

  testWidgets('tapping the coin itself flips it', (tester) async {
    await pumpSlab(
      tester,
      transaction: txn(),
      loader: loaderOf(loadedLookup),
    );

    await tester.tap(find.text(formatInr(320.58)));
    await tester.pumpAndSettle();

    expect(find.text(smsBody), findsOneWidget);
  });

  testWidgets('flipping back returns to the coin face', (tester) async {
    await pumpSlab(
      tester,
      transaction: txn(),
      loader: loaderOf(loadedLookup),
    );

    await tester.tap(find.text('FLIP TO SMS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FLIP TO COIN'));
    await tester.pumpAndSettle();

    expect(find.text('Swiggy'), findsOneWidget);
    expect(find.text(smsBody), findsNothing);
  });

  testWidgets('reverse shows a reading state until the inbox answers',
      (tester) async {
    final gate = Completer<OriginalSmsLookup>();

    await pumpSlab(
      tester,
      transaction: txn(),
      loader: (_) => gate.future,
    );

    await tester.tap(find.text('FLIP TO SMS'));
    // The reading state runs an indeterminate bar, so settle by hand.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('READING THE INBOX'), findsOneWidget);
    expect(find.text(smsBody), findsNothing);

    gate.complete(loadedLookup);
    await tester.pump();
    await tester.pump();

    expect(find.text('READING THE INBOX'), findsNothing);
    expect(find.text(smsBody), findsOneWidget);
  });

  testWidgets('transaction without an smsId explains the blank reverse',
      (tester) async {
    await pumpSlab(
      tester,
      transaction: txn(smsId: null),
      loader: loaderOf(loadedLookup),
    );

    await tester.tap(find.text('FLIP TO SMS'));
    await tester.pumpAndSettle();

    expect(find.text('Not struck from an SMS'), findsOneWidget);
    expect(find.text(smsBody), findsNothing);
  });

  testWidgets('deleted SMS reads as gone from the inbox, not an error',
      (tester) async {
    await pumpSlab(
      tester,
      transaction: txn(),
      loader: loaderOf(
        const OriginalSmsLookup.miss(OriginalSmsStatus.notFound),
      ),
    );

    await tester.tap(find.text('FLIP TO SMS'));
    await tester.pumpAndSettle();

    expect(find.text('Alert no longer in the inbox'), findsOneWidget);
  });

  testWidgets('revoked SMS permission points at the permission', (tester) async {
    await pumpSlab(
      tester,
      transaction: txn(),
      loader: loaderOf(
        const OriginalSmsLookup.miss(OriginalSmsStatus.noPermission),
      ),
    );

    await tester.tap(find.text('FLIP TO SMS'));
    await tester.pumpAndSettle();

    expect(find.text('SMS access is off'), findsOneWidget);
  });

  testWidgets('internal movement is stamped MOVE', (tester) async {
    await pumpSlab(
      tester,
      transaction: txn(
        merchant: 'Credit card bill payment',
        kind: AccountKind.creditCard,
      ),
      isMove: true,
      loader: loaderOf(loadedLookup),
    );

    expect(find.text('MOVE'), findsOneWidget);
    expect(find.text('CC bill paid · Food'), findsOneWidget);
  });

  testWidgets('Copy SMS puts the full body on the clipboard', (tester) async {
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

    await pumpSlab(
      tester,
      transaction: txn(),
      loader: loaderOf(loadedLookup),
    );

    await tester.tap(find.text('COPY SMS'));
    await tester.pumpAndSettle();

    expect(copied, smsBody);
    expect(find.text('Original SMS copied'), findsOneWidget);
  });

  testWidgets('Copy stays inert when there is no SMS to copy', (tester) async {
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

    await pumpSlab(
      tester,
      transaction: txn(smsId: null),
      loader: loaderOf(loadedLookup),
    );

    await tester.tap(find.text('COPY SMS'));
    await tester.pumpAndSettle();

    expect(copied, isNull);
  });

  testWidgets('merchant masking hides the face label but never the SMS body',
      (tester) async {
    await settings.setMaskMerchantNames(true);

    await pumpSlab(
      tester,
      transaction: txn(),
      loader: loaderOf(loadedLookup),
    );

    expect(find.text('Sw••••gy'), findsOneWidget);
    expect(find.text('Swiggy'), findsNothing);

    await tester.tap(find.text('FLIP TO SMS'));
    await tester.pumpAndSettle();

    expect(find.text(smsBody), findsOneWidget);
  });

  testWidgets('tapping a Paisa Coin row opens the flip detail', (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = FinanceStore()..seedTransactions([txn()]);

    await tester.pumpWidget(
      buildTestApp(
        settings: settings,
        store: store,
        child: DayStripScreen(initialDay: DateTime(2026, 8, 15)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Swiggy'));
    await tester.pumpAndSettle();

    // Screen wordmark (PAISA COIN) plus the sheet's own (PAISA MINT).
    expect(find.text('PAISA'), findsNWidgets(2));
    expect(find.text('MINT'), findsOneWidget);
    expect(find.text('FLIP TO SMS'), findsOneWidget);
    expect(find.text('HDFC · ••••1234'), findsOneWidget);
  });

  test('empty-state copy exists for every non-loaded status', () {
    for (final status in OriginalSmsStatus.values) {
      final copy = originalSmsEmptyCopy(status);
      if (status == OriginalSmsStatus.loaded) continue;
      expect(copy.title, isNotEmpty, reason: '$status title');
      expect(copy.body, isNotEmpty, reason: '$status body');
    }
  });
}
