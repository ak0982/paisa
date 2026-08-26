import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:paisa_app/providers/app_settings.dart';
import 'package:paisa_app/services/screen_security.dart';

/// SEC-2 — the screens show balances, the whole ledger and (since the Coin Flip
/// reverse) the verbatim bank alert, so screenshots, screen recorders and the
/// recent-apps thumbnail have to be blocked. Three pieces have to hold together:
///
///   * `MainActivity.onCreate` sets `FLAG_SECURE` *before* the first frame, so
///     there is no unprotected window even for one frame;
///   * the preference defaults to protected and survives a restart;
///   * `ScreenSecurity` carries the customer's choice to the window and never
///     throws — losing the toggle must not take the app down with it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'com.paisa.paisa_app/security';
  const channel = MethodChannel(channelName);
  final activity = File(
    'android/app/src/main/kotlin/com/paisa/paisa_app/MainActivity.kt',
  ).readAsStringSync();

  /// Records every call on the security channel and answers with [reply], or
  /// throws [error] when given one.
  List<MethodCall> mockChannel({Object? reply = true, Object? error}) {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (error != null) throw error;
      return reply;
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    return calls;
  }

  group('SEC-2 the window is protected before the first frame', () {
    test('FLAG_SECURE is added ahead of super.onCreate', () {
      final onCreate = activity.indexOf('override fun onCreate');
      expect(onCreate, greaterThan(-1), reason: 'onCreate override removed');

      final body = activity.substring(onCreate);
      final addFlags = body.indexOf(
        'window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)',
      );
      expect(addFlags, greaterThan(-1), reason: 'FLAG_SECURE is never set');
      expect(
        addFlags,
        lessThan(body.indexOf('super.onCreate')),
        reason: 'set after attach = one capturable frame at launch',
      );
    });

    test('the flag is set in onCreate, not in a later lifecycle callback', () {
      // onResume/onStart would leave the recents thumbnail of a cold start
      // unprotected.
      final onCreate = activity.indexOf('override fun onCreate');
      final firstAdd = activity.indexOf(
        'window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)',
      );
      expect(firstAdd, greaterThan(onCreate));
      expect(activity.contains('override fun onResume'), isFalse);
    });

    test('the platform side of the toggle can both set and clear the flag', () {
      expect(activity.contains(channelName), isTrue);
      expect(activity.contains('"setSecureScreen"'), isTrue);
      expect(
        activity.contains(
          'window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)',
        ),
        isTrue,
        reason: 'the opt-out path needs clearFlags',
      );
    });

    test('a call that arrives without an argument fails secure', () {
      // A malformed/absent `enabled` must not be read as "stop protecting".
      expect(
        activity.contains('call.argument<Boolean>("enabled") ?: true'),
        isTrue,
        reason: 'the default for a missing argument must be protected',
      );
    });

    test('the security channel is separate from the SMS channel', () {
      expect(activity.contains('com.paisa.paisa_app/sms'), isTrue);
      expect(
        activity.contains('private val securityChannelName = "$channelName"'),
        isTrue,
      );
    });

    test('unknown methods are rejected rather than silently succeeding', () {
      expect(activity.contains('else -> result.notImplemented()'), isTrue);
    });
  });

  group('SEC-2 the preference is secure by default and persists', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('a fresh install starts protected', () async {
      expect((await AppSettings.load()).blockScreenshots, isTrue);
    });

    test('an upgrade that has never seen the key starts protected', () async {
      // Existing installs have prefs but no screenshot key — they must not be
      // read as "the customer turned it off".
      SharedPreferences.setMockInitialValues({
        'privacy_mask_merchants': true,
        'profile_user_name': 'Aarav Sharma',
      });
      expect((await AppSettings.load()).blockScreenshots, isTrue);
    });

    for (final stored in [true, false]) {
      test('a stored $stored is honoured on load', () async {
        SharedPreferences.setMockInitialValues({
          'privacy_block_screenshots': stored,
        });
        expect((await AppSettings.load()).blockScreenshots, stored);
      });
    }

    test('turning protection off persists across a restart', () async {
      final settings = await AppSettings.load();
      await settings.setBlockScreenshots(false);
      expect(settings.blockScreenshots, isFalse);
      expect((await AppSettings.load()).blockScreenshots, isFalse);
    });

    test('turning it back on persists too', () async {
      final settings = await AppSettings.load();
      await settings.setBlockScreenshots(false);
      await settings.setBlockScreenshots(true);
      expect((await AppSettings.load()).blockScreenshots, isTrue);
    });

    test('each change notifies listeners so the switch repaints', () async {
      final settings = await AppSettings.load();
      var notifications = 0;
      settings.addListener(() => notifications++);

      await settings.setBlockScreenshots(false);
      await settings.setBlockScreenshots(true);

      expect(notifications, 2);
    });

    test('it is stored under its own key, independent of merchant masking',
        () async {
      final settings = await AppSettings.load();
      await settings.setBlockScreenshots(false);
      expect(settings.maskMerchantNames, isFalse);

      await settings.setMaskMerchantNames(true);
      expect(settings.blockScreenshots, isFalse);

      await settings.setBlockScreenshots(true);
      expect(settings.maskMerchantNames, isTrue);
    });
  });

  group('SEC-2 ScreenSecurity carries the choice to the window', () {
    tearDown(() => ScreenSecurity.debugSupportedPlatformOverride = null);

    for (final enabled in [true, false]) {
      test('applying $enabled invokes setSecureScreen with enabled: $enabled',
          () async {
        final calls = mockChannel();
        const security = ScreenSecurity(isSupportedPlatform: true);

        expect(await security.apply(blockScreenshots: enabled), isTrue);
        expect(calls, hasLength(1));
        expect(calls.single.method, 'setSecureScreen');
        expect(calls.single.arguments, {'enabled': enabled});
      });
    }

    test('repeated toggles reach the platform in order, uncoalesced', () async {
      final calls = mockChannel();
      const security = ScreenSecurity(isSupportedPlatform: true);

      for (final value in [false, true, false, false]) {
        await security.apply(blockScreenshots: value);
      }

      expect(
        calls.map((c) => (c.arguments as Map)['enabled']).toList(),
        [false, true, false, false],
        reason: 'a cached "already off" would strand the real window flag',
      );
    });

    test('a platform reply of null still counts as applied', () async {
      // The Kotlin handler answers with the new state, but a void reply from an
      // older build is not a failure.
      mockChannel(reply: null);
      const security = ScreenSecurity(isSupportedPlatform: true);
      expect(await security.apply(blockScreenshots: true), isTrue);
    });

    test('it is a silent no-op off Android', () async {
      final calls = mockChannel();
      const security = ScreenSecurity(isSupportedPlatform: false);

      expect(await security.apply(blockScreenshots: true), isFalse);
      expect(calls, isEmpty, reason: 'FLAG_SECURE is an Android window flag');
    });

    test('it follows the host platform when not told otherwise', () async {
      // These tests run on the desktop VM, so the unconfigured service must not
      // try to talk to a channel that has no Android window behind it. This is
      // also why the widget tests need the override below.
      final calls = mockChannel();
      expect(
        await const ScreenSecurity().apply(blockScreenshots: true),
        Platform.isAndroid,
      );
      expect(calls.isEmpty, !Platform.isAndroid);
    });

    test('the debug override makes the service testable off Android', () async {
      ScreenSecurity.debugSupportedPlatformOverride = true;
      final calls = mockChannel();

      expect(await const ScreenSecurity().apply(blockScreenshots: false), isTrue);
      expect(calls.single.arguments, {'enabled': false});
    });

    test('an explicit platform flag beats the override', () async {
      ScreenSecurity.debugSupportedPlatformOverride = true;
      final calls = mockChannel();

      expect(
        await const ScreenSecurity(isSupportedPlatform: false)
            .apply(blockScreenshots: false),
        isFalse,
      );
      expect(calls, isEmpty);
    });

    test('a failing platform call reports failure instead of throwing',
        () async {
      mockChannel(error: PlatformException(code: 'BOOM'));
      const security = ScreenSecurity(isSupportedPlatform: true);
      expect(await security.apply(blockScreenshots: false), isFalse);
    });

    test('a missing native handler is survivable', () async {
      // Real case: the toggle is flipped before the engine attached the channel.
      mockChannel(error: MissingPluginException('no handler'));
      const security = ScreenSecurity(isSupportedPlatform: true);
      expect(await security.apply(blockScreenshots: true), isFalse);
    });

    test('an unexpected reply type is survivable too', () async {
      // main() fires this call without awaiting it, so anything escaping here
      // becomes an unhandled async error at launch rather than a lost toggle.
      mockChannel(reply: 'not-a-bool');
      const security = ScreenSecurity(isSupportedPlatform: true);
      expect(await security.apply(blockScreenshots: true), isFalse);
    });

    test('a failed call does not stop the next one from being tried', () async {
      mockChannel(error: PlatformException(code: 'BOOM'));
      const security = ScreenSecurity(isSupportedPlatform: true);
      expect(await security.apply(blockScreenshots: false), isFalse);

      final calls = mockChannel();
      expect(await security.apply(blockScreenshots: false), isTrue);
      expect(calls, hasLength(1));
    });
  });

  group('SEC-2 launch wiring', () {
    final startup = File('lib/main.dart').readAsStringSync();

    test('startup applies the persisted preference, not a hardcoded state', () {
      expect(
        startup.contains('blockScreenshots: appSettings.blockScreenshots'),
        isTrue,
        reason: 'otherwise the opt-out never takes effect after a restart',
      );
    });

    test('the launch call runs after the first frame and is not awaited', () {
      final callback = startup.indexOf('addPostFrameCallback');
      final apply = startup.indexOf('const ScreenSecurity().apply');
      expect(callback, greaterThan(-1));
      expect(apply, greaterThan(callback), reason: 'must not block the splash');
      expect(
        startup.contains('await const ScreenSecurity().apply'),
        isFalse,
        reason: 'ISSUE-7: hydration must not wait on a window flag',
      );
    });
  });
}
