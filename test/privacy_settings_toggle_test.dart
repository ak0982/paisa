import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:paisa_app/data/transaction_database.dart';
import 'package:paisa_app/providers/app_settings.dart';
import 'package:paisa_app/providers/finance_store.dart';
import 'package:paisa_app/screens/settings/privacy_settings_screen.dart';
import 'package:paisa_app/services/screen_security.dart';
import 'package:paisa_app/services/sms/sms_reader_service.dart';
import 'package:paisa_app/theme/paisa_colors.dart';
import 'package:paisa_app/theme/paisa_theme.dart';
import 'package:paisa_app/widgets/settings_detail_scaffold.dart';

import 'helpers/test_harness.dart';

/// Privacy settings, from the customer's side of the screen.
///
/// The R3 UI fix was about a switch nobody could read: on M3 the default theme
/// paints the selected thumb and track in the same primary lime, so "on" and
/// "off" looked identical — on the one screen where getting the state wrong
/// means believing screenshots are blocked when they are not. Hence both an
/// explicit ON/OFF word and a themed thumb/track that stay distinguishable.
///
/// The screen also owns the SEC-2 opt-out, so these tests check the toggle
/// actually reaches the platform, not just that the preference flipped.
class _GrantedSmsReader extends SmsReaderService {
  @override
  Future<bool> hasSmsPermission() async => true;
}

void main() {
  const channel = MethodChannel('com.paisa.paisa_app/security');

  late AppSettings settings;
  late List<MethodCall> securityCalls;
  late Directory tmp;
  var dbSeq = 0;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await AppSettings.load();
    tmp = Directory.systemTemp.createTempSync('paisa_privacy_test');

    // The screen builds its own `const ScreenSecurity()`, which is a no-op on
    // the test VM unless we claim to be Android.
    ScreenSecurity.debugSupportedPlatformOverride = true;
    securityCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      securityCalls.add(call);
      return (call.arguments as Map)['enabled'];
    });
  });

  tearDown(() {
    ScreenSecurity.debugSupportedPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<void> openPrivacy(
    WidgetTester tester, {
    FinanceStore? store,
  }) async {
    await tester.pumpWidget(
      buildTestApp(
        child: const PrivacySettingsScreen(),
        settings: settings,
        store: store ?? FinanceStore(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder rowFor(String title) => find.ancestor(
        of: find.text(title),
        matching: find.byType(SettingsToggleRow),
      );

  Finder switchFor(String title) => find.descendant(
        of: rowFor(title),
        matching: find.byType(Switch),
      );

  /// The ON / OFF word rendered beside the switch in [title]'s row.
  String stateLabelFor(WidgetTester tester, String title) {
    final label = find.descendant(
      of: rowFor(title),
      matching: find.byWidgetPredicate(
        (w) => w is Text && (w.data == 'ON' || w.data == 'OFF'),
      ),
    );
    expect(label, findsOneWidget, reason: 'no ON/OFF word for "$title"');
    return tester.widget<Text>(label).data!;
  }

  group('the Privacy screen states both toggles in words', () {
    testWidgets('screenshot blocking is on, and says so, out of the box',
        (tester) async {
      await openPrivacy(tester);

      expect(find.text('Block screenshots'), findsOneWidget);
      expect(
        find.text(
          'Hide My Paisa from screenshots, screen recording and the recent-apps '
          'preview.',
        ),
        findsOneWidget,
      );
      expect(tester.widget<Switch>(switchFor('Block screenshots')).value, isTrue);
      expect(stateLabelFor(tester, 'Block screenshots'), 'ON');
    });

    testWidgets('merchant masking is off, and says so, out of the box',
        (tester) async {
      await openPrivacy(tester);

      expect(
        tester.widget<Switch>(switchFor('Mask merchant names')).value,
        isFalse,
      );
      expect(stateLabelFor(tester, 'Mask merchant names'), 'OFF');
    });

    testWidgets('the word follows the switch when it is turned off',
        (tester) async {
      await openPrivacy(tester);

      await tester.tap(switchFor('Block screenshots'));
      await tester.pumpAndSettle();

      expect(stateLabelFor(tester, 'Block screenshots'), 'OFF');
      expect(
        tester.widget<Switch>(switchFor('Block screenshots')).value,
        isFalse,
      );
    });

    testWidgets('a previously saved opt-out is shown as OFF on open',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'privacy_block_screenshots': false,
      });
      settings = await AppSettings.load();

      await openPrivacy(tester);

      expect(stateLabelFor(tester, 'Block screenshots'), 'OFF');
    });

    testWidgets('each row has exactly one word and one switch', (tester) async {
      await openPrivacy(tester);

      for (final title in ['Mask merchant names', 'Block screenshots']) {
        expect(switchFor(title), findsOneWidget);
        expect(
          find.descendant(of: rowFor(title), matching: find.text('ON')).evaluate().length +
              find.descendant(of: rowFor(title), matching: find.text('OFF')).evaluate().length,
          1,
          reason: 'ambiguous state text in the "$title" row',
        );
      }
    });

    testWidgets('the word is coloured to match the state', (tester) async {
      await openPrivacy(tester);

      Color labelColour(String title) => tester
          .widget<Text>(
            find.descendant(
              of: rowFor(title),
              matching: find.byWidgetPredicate(
                (w) => w is Text && (w.data == 'ON' || w.data == 'OFF'),
              ),
            ),
          )
          .style!
          .color!;

      expect(labelColour('Block screenshots'), PaisaColors.primary);
      expect(labelColour('Mask merchant names'), PaisaColors.muted);
    });
  });

  group('the switch itself stays readable', () {
    test('the theme never paints the thumb and the track the same colour', () {
      final switchTheme = PaisaTheme.dark().switchTheme;

      for (final states in [
        <MaterialState>{MaterialState.selected},
        <MaterialState>{},
      ]) {
        final thumb = switchTheme.thumbColor!.resolve(states);
        final track = switchTheme.trackColor!.resolve(states);
        expect(
          thumb,
          isNot(track),
          reason: 'the handle disappears into the track for $states',
        );
        expect(
          _contrastRatio(thumb!, track!),
          greaterThan(3.0),
          reason: 'thumb/track contrast is too low to read for $states',
        );
      }
    });

    test('the two states do not look like each other', () {
      final switchTheme = PaisaTheme.dark().switchTheme;
      final on = switchTheme.trackColor!.resolve({MaterialState.selected})!;
      final off = switchTheme.trackColor!.resolve(<MaterialState>{})!;

      expect(on, isNot(off));
      expect(
        _contrastRatio(on, off),
        greaterThan(3.0),
        reason: 'on and off tracks must be tellable apart at a glance',
      );
    });

    test('the off track keeps a visible outline on the dark card', () {
      final switchTheme = PaisaTheme.dark().switchTheme;
      final outline =
          switchTheme.trackOutlineColor!.resolve(<MaterialState>{})!;

      expect(outline.alpha, 255, reason: 'a see-through edge is no edge');
      expect(
        outline,
        isNot(switchTheme.trackColor!.resolve(<MaterialState>{})),
        reason: 'the pill would have no discernible border',
      );
      expect(
        _contrastRatio(outline, PaisaColors.card),
        greaterThan(1.5),
        reason: 'the off pill must be findable against the settings card',
      );
    });

    test('the on track drops the outline so the lime pill reads as filled', () {
      final outline = PaisaTheme.dark()
          .switchTheme
          .trackOutlineColor!
          .resolve({MaterialState.selected});
      expect(outline, Colors.transparent);
    });

    test('pressing feedback exists for both states', () {
      final overlay = PaisaTheme.dark().switchTheme.overlayColor!;
      expect(overlay.resolve({MaterialState.selected})!.alpha, greaterThan(0));
      expect(overlay.resolve(<MaterialState>{})!.alpha, greaterThan(0));
    });

    testWidgets('the row leaves the colours to the theme', (tester) async {
      await openPrivacy(tester);

      final toggle = tester.widget<Switch>(switchFor('Block screenshots'));
      expect(
        toggle.activeColor,
        isNull,
        reason: 'activeColor makes M3 paint thumb and track the same lime',
      );
      expect(toggle.thumbColor, isNull);
      expect(toggle.trackColor, isNull);
    });

    testWidgets('it is a Material switch, so the theme applies at all',
        (tester) async {
      await openPrivacy(tester);
      expect(find.byType(Switch), findsNWidgets(2));
      expect(find.byType(CupertinoSwitch), findsNothing);
    });

    test('the shared toggle row does not reintroduce the unreadable switch',
        () {
      // Switch.adaptive renders a Cupertino switch on iOS, which ignores
      // SwitchThemeData entirely — the exact regression that hid the handle.
      final code = File('lib/widgets/settings_detail_scaffold.dart')
          .readAsLinesSync()
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      expect(code.contains('Switch.adaptive'), isFalse);
      expect(code.contains('activeColor'), isFalse);
    });

    testWidgets('screen readers get the state, not just the colour',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await openPrivacy(tester);

      final blocked = tester.getSemantics(switchFor('Block screenshots'));
      expect(blocked.hasFlag(SemanticsFlag.hasToggledState), isTrue);
      expect(blocked.hasFlag(SemanticsFlag.isToggled), isTrue);
      expect(blocked.hasFlag(SemanticsFlag.isEnabled), isTrue);

      expect(
        tester
            .getSemantics(switchFor('Mask merchant names'))
            .hasFlag(SemanticsFlag.isToggled),
        isFalse,
      );

      semantics.dispose();
    });
  });

  group('the screenshot toggle reaches the window, not just the preference', () {
    testWidgets('turning it off saves the choice and clears the flag',
        (tester) async {
      await openPrivacy(tester);

      await tester.tap(switchFor('Block screenshots'));
      await tester.pumpAndSettle();

      expect(settings.blockScreenshots, isFalse);
      expect(securityCalls, hasLength(1));
      expect(securityCalls.single.method, 'setSecureScreen');
      expect(securityCalls.single.arguments, {'enabled': false});
    });

    testWidgets('turning it back on re-arms the flag', (tester) async {
      await openPrivacy(tester);

      await tester.tap(switchFor('Block screenshots'));
      await tester.pumpAndSettle();
      await tester.tap(switchFor('Block screenshots'));
      await tester.pumpAndSettle();

      expect(settings.blockScreenshots, isTrue);
      expect(
        securityCalls.map((c) => (c.arguments as Map)['enabled']).toList(),
        [false, true],
      );
      expect(stateLabelFor(tester, 'Block screenshots'), 'ON');
    });

    testWidgets('the opt-out survives leaving and reopening the screen',
        (tester) async {
      await openPrivacy(tester);
      await tester.tap(switchFor('Block screenshots'));
      await tester.pumpAndSettle();

      settings = await AppSettings.load();
      await openPrivacy(tester);

      expect(stateLabelFor(tester, 'Block screenshots'), 'OFF');
    });

    testWidgets('masking merchants never touches the window flag',
        (tester) async {
      await openPrivacy(tester);

      await tester.tap(switchFor('Mask merchant names'));
      await tester.pumpAndSettle();

      expect(settings.maskMerchantNames, isTrue);
      expect(settings.blockScreenshots, isTrue);
      expect(securityCalls, isEmpty);
      expect(stateLabelFor(tester, 'Block screenshots'), 'ON');
    });

    testWidgets('a platform that refuses still records the choice',
        (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        securityCalls.add(call);
        throw PlatformException(code: 'BOOM');
      });

      await openPrivacy(tester);
      await tester.tap(switchFor('Block screenshots'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'the screen must not throw');
      expect(settings.blockScreenshots, isFalse);
      expect(stateLabelFor(tester, 'Block screenshots'), 'OFF');
      expect(securityCalls, hasLength(1));
    });

    testWidgets('flipping it repeatedly leaves preference and flag agreeing',
        (tester) async {
      await openPrivacy(tester);

      for (var i = 0; i < 5; i++) {
        await tester.tap(switchFor('Block screenshots'));
        await tester.pumpAndSettle();
      }

      expect(settings.blockScreenshots, isFalse);
      expect(stateLabelFor(tester, 'Block screenshots'), 'OFF');
      expect(
        (securityCalls.last.arguments as Map)['enabled'],
        settings.blockScreenshots,
      );
      expect(securityCalls, hasLength(5));
    });
  });

  group('the rest of the privacy promise is on screen', () {
    testWidgets('the guarantee card spells out the on-device promise',
        (tester) async {
      await openPrivacy(tester);

      expect(find.text('Your privacy is guaranteed'), findsOneWidget);
      expect(
        find.text(
          'Messages are processed on your device — never uploaded to any '
          'server.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Your data is never sold or shared with anyone.'),
        findsOneWidget,
      );
      expect(find.text('Privacy policy'), findsOneWidget);
    });

    testWidgets('a revoked SMS permission is called out, not hidden',
        (tester) async {
      await openPrivacy(tester);

      expect(find.text('SMS permission'), findsOneWidget);
      expect(find.text('Off'), findsOneWidget);
      expect(
        find.text('Not granted — transactions cannot be auto-detected.'),
        findsOneWidget,
      );
    });

    testWidgets('a granted SMS permission shows as active', (tester) async {
      final store = FinanceStore(
        smsReader: _GrantedSmsReader(),
        database: TransactionDatabase.forTesting('${tmp.path}/p${dbSeq++}.db'),
      );
      // The FFI database answers on a real isolate, which the widget tester's
      // fake clock would never let finish.
      await tester.runAsync(store.init);

      await openPrivacy(tester, store: store);

      expect(find.text('Active'), findsOneWidget);
      expect(
        find.text('Granted — My Paisa can read bank alert SMS on this device.'),
        findsOneWidget,
      );
    });

    testWidgets('clearing local data asks first and can be backed out of',
        (tester) async {
      await openPrivacy(tester);

      await tester.scrollUntilVisible(
        find.text('Clear local data'),
        120,
        scrollable: find.byType(Scrollable),
      );
      await tester.tap(find.text('Clear local data'));
      await tester.pumpAndSettle();

      expect(find.text('Clear local data?'), findsOneWidget);
      expect(
        find.textContaining('Your SMS messages will not be deleted.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Clear local data?'), findsNothing);
    });

    testWidgets('the toggles keep their state while the dialog is up',
        (tester) async {
      await openPrivacy(tester);
      await tester.tap(switchFor('Block screenshots'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Clear local data'),
        120,
        scrollable: find.byType(Scrollable),
      );
      await tester.tap(find.text('Clear local data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Block screenshots'),
        -120,
        scrollable: find.byType(Scrollable),
      );
      expect(stateLabelFor(tester, 'Block screenshots'), 'OFF');
    });
  });
}

/// WCAG contrast ratio, used to assert two theme colours are tellable apart
/// rather than merely `!=` (0xC8FF4D vs 0xC8FF4E would pass a plain compare).
double _contrastRatio(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  final lighter = math.max(first, second);
  final darker = math.min(first, second);
  return (lighter + 0.05) / (darker + 0.05);
}
