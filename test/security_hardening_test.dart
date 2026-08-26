import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:paisa_app/providers/app_settings.dart';
import 'package:paisa_app/providers/finance_store.dart';
import 'package:paisa_app/screens/settings/privacy_settings_screen.dart';
import 'package:paisa_app/services/screen_security.dart';

import 'helpers/test_harness.dart';

/// Round-3 security review (Fable/Claude) — regression cover for the findings
/// that were reproduced and fixed. Each group names the finding it locks down.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SEC-1 financial data must not leave the device via OS backup', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    test('release manifest opts out of backup and declares both rule files',
        () {
      expect(
        manifest.contains('android:allowBackup="false"'),
        isTrue,
        reason: 'without this the plaintext DB is swept into Google Auto Backup',
      );
      expect(
        manifest.contains('android:fullBackupContent="@xml/backup_rules"'),
        isTrue,
        reason: 'API <= 30 counterpart',
      );
      expect(
        manifest.contains(
          'android:dataExtractionRules="@xml/data_extraction_rules"',
        ),
        isTrue,
        reason: 'allowBackup=false does NOT stop D2D transfer on Android 12+',
      );
    });

    test('data extraction rules exclude every domain from cloud AND transfer',
        () {
      final rules =
          File('android/app/src/main/res/xml/data_extraction_rules.xml')
              .readAsStringSync();

      for (final section in ['cloud-backup', 'device-transfer']) {
        final start = rules.indexOf('<$section');
        final end = rules.indexOf('</$section>');
        expect(start, greaterThan(-1), reason: 'missing <$section>');
        expect(end, greaterThan(start), reason: 'unterminated <$section>');

        final body = rules.substring(start, end);
        for (final domain in ['root', 'database', 'sharedpref', 'file']) {
          expect(
            body.contains('<exclude domain="$domain" path="." />'),
            isTrue,
            reason: '$section must exclude the $domain domain',
          );
        }
        expect(
          body.contains('<include'),
          isFalse,
          reason: 'an include in $section would re-open the export path',
        );
      }
    });

    test('pre-31 backup rules exclude every domain', () {
      final rules = File('android/app/src/main/res/xml/backup_rules.xml')
          .readAsStringSync();
      for (final domain in ['root', 'database', 'sharedpref', 'file']) {
        expect(
          rules.contains('<exclude domain="$domain" path="." />'),
          isTrue,
          reason: 'backup_rules.xml must exclude the $domain domain',
        );
      }
      expect(rules.contains('<include'), isFalse);
    });
  });

  group('SEC-2 screens (incl. raw bank SMS) are hidden from capture', () {
    final activity = File(
      'android/app/src/main/kotlin/com/paisa/paisa_app/MainActivity.kt',
    ).readAsStringSync();

    test('MainActivity sets FLAG_SECURE in onCreate, before the first frame',
        () {
      final onCreate = activity.indexOf('override fun onCreate');
      expect(onCreate, greaterThan(-1), reason: 'onCreate override removed');

      final body = activity.substring(onCreate);
      final addFlags =
          body.indexOf('window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)');
      final superCall = body.indexOf('super.onCreate');
      expect(addFlags, greaterThan(-1), reason: 'FLAG_SECURE is not set');
      expect(
        addFlags,
        lessThan(superCall),
        reason: 'the flag must be set before the Flutter view is attached',
      );
    });

    test('security channel can both set and clear the flag', () {
      expect(activity.contains('com.paisa.paisa_app/security'), isTrue);
      expect(activity.contains('"setSecureScreen"'), isTrue);
      expect(
        activity.contains(
          'window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)',
        ),
        isTrue,
        reason: 'the opt-out path needs clearFlags',
      );
    });

    test('blockScreenshots defaults to ON and persists', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = await AppSettings.load();
      expect(settings.blockScreenshots, isTrue);

      await settings.setBlockScreenshots(false);
      expect(settings.blockScreenshots, isFalse);
      expect((await AppSettings.load()).blockScreenshots, isFalse);
    });

    test('ScreenSecurity forwards the requested state to the platform',
        () async {
      const channel = MethodChannel('com.paisa.paisa_app/security');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      const security = ScreenSecurity(isSupportedPlatform: true);
      expect(await security.apply(blockScreenshots: false), isTrue);
      expect(await security.apply(blockScreenshots: true), isTrue);

      expect(calls.map((c) => c.method), everyElement('setSecureScreen'));
      expect(calls.first.arguments, {'enabled': false});
      expect(calls.last.arguments, {'enabled': true});
    });

    test('ScreenSecurity is a silent no-op off Android', () async {
      const channel = MethodChannel('com.paisa.paisa_app/security');
      var called = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        called = true;
        return true;
      });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      const security = ScreenSecurity(isSupportedPlatform: false);
      expect(await security.apply(blockScreenshots: true), isFalse);
      expect(called, isFalse);
    });

    test('a failing channel never throws out of ScreenSecurity', () async {
      const channel = MethodChannel('com.paisa.paisa_app/security');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'BOOM');
      });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      const security = ScreenSecurity(isSupportedPlatform: true);
      expect(await security.apply(blockScreenshots: false), isFalse);
    });

    testWidgets('Privacy settings expose the toggle, on by default',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = await AppSettings.load();

      await tester.pumpWidget(
        buildTestApp(
          child: const PrivacySettingsScreen(),
          settings: settings,
          store: FinanceStore(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Block screenshots'), findsOneWidget);
      final toggle = tester.widget<Switch>(
        find.descendant(
          of: find.ancestor(
            of: find.text('Block screenshots'),
            matching: find.byType(Row),
          ),
          matching: find.byType(Switch),
        ),
      );
      expect(toggle.value, isTrue);

      await tester.tap(find.byType(Switch).at(1));
      await tester.pumpAndSettle();
      expect(settings.blockScreenshots, isFalse);
    });
  });

  group('SEC-4 release builds must not log to logcat', () {
    test('every print / debugPrint in lib/ is behind kDebugMode', () {
      // debugPrint and debugPrintStack are NOT compiled out of release builds;
      // they reach logcat, which ADB and READ_LOGS holders can read.
      final logging = RegExp(r'\b(debugPrintStack|debugPrint|print)\s*\(');
      final offenders = <String>[];

      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          final trimmed = line.trimLeft();
          if (trimmed.startsWith('//')) continue;
          if (!logging.hasMatch(line)) continue;

          final window = lines
              .sublist(i - 3 < 0 ? 0 : i - 3, i + 1)
              .join('\n');
          if (window.contains('kDebugMode')) continue;
          offenders.add('${entity.path}:${i + 1}: ${trimmed.trim()}');
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'ungated logging leaks into release logcat:\n'
            '${offenders.join('\n')}',
      );
    });
  });
}
