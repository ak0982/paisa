import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// SEC-1 — "your bank alerts never leave this device" has to survive the two
/// OS-level export paths the customer never sees and cannot inspect: Google
/// Auto Backup (Drive) and the Android 12+ device-to-device transfer used by
/// the new-phone setup wizard. Both are opt-**out**, both are configured purely
/// in the Android manifest plus two rules files, and no Dart code can detect a
/// regression at runtime — so the configuration itself is the unit under test.
///
/// [security_hardening_test.dart] locks the headline attributes; this suite
/// covers the full surface: every domain, both API-level rule files, the other
/// build variants' manifests, and the permissions the app asks for at all.
void main() {
  const manifestPath = 'android/app/src/main/AndroidManifest.xml';
  const debugManifestPath = 'android/app/src/debug/AndroidManifest.xml';
  const profileManifestPath = 'android/app/src/profile/AndroidManifest.xml';
  const backupRulesPath = 'android/app/src/main/res/xml/backup_rules.xml';
  const extractionRulesPath =
      'android/app/src/main/res/xml/data_extraction_rules.xml';

  /// The domains an Android backup agent can export. Paisa writes the SQLite
  /// ledger (`database`, under `root`) and the preferences (`sharedpref`); the
  /// rest are excluded too because a domain that is merely unused today would
  /// silently become an export path the day some feature starts writing there.
  const allDomains = {'root', 'file', 'database', 'sharedpref', 'external'};

  final manifest = File(manifestPath).readAsStringSync();
  final backupRules = File(backupRulesPath).readAsStringSync();
  final extractionRules = File(extractionRulesPath).readAsStringSync();

  group('SEC-1 release manifest closes both export paths', () {
    test('the app opts out of backup outright', () {
      expect(
        manifest.contains('android:allowBackup="false"'),
        isTrue,
        reason: 'the plaintext ledger would be swept into Google Auto Backup',
      );
      expect(
        manifest.contains('android:allowBackup="true"'),
        isFalse,
        reason: 'a second, later attribute would win',
      );
    });

    test('both rule files are declared and both exist on disk', () {
      expect(manifest.contains('android:fullBackupContent="@xml/backup_rules"'),
          isTrue);
      expect(
        manifest.contains(
          'android:dataExtractionRules="@xml/data_extraction_rules"',
        ),
        isTrue,
        reason: 'allowBackup="false" does not stop D2D transfer on Android 12+',
      );
      expect(File(backupRulesPath).existsSync(), isTrue);
      expect(File(extractionRulesPath).existsSync(), isTrue);
    });

    test('all three attributes sit on the <application> element', () {
      // A rules file declared on the wrong element is silently ignored by aapt.
      final application = _elementTag(manifest, 'application');
      expect(application, isNotNull, reason: '<application> not found');
      for (final attribute in [
        'android:allowBackup="false"',
        'android:fullBackupContent="@xml/backup_rules"',
        'android:dataExtractionRules="@xml/data_extraction_rules"',
      ]) {
        expect(
          application!.contains(attribute),
          isTrue,
          reason: '$attribute must be an <application> attribute',
        );
      }
    });

    test('the release build is not debuggable', () {
      expect(
        manifest.contains('android:debuggable="true"'),
        isFalse,
        reason: 'a debuggable release build hands the data dir to any ADB host',
      );
    });

    test('SMS read access is the only permission the app asks for', () {
      final permissions = _permissionsIn(manifest);
      expect(
        permissions,
        {'android.permission.READ_SMS'},
        reason: 'every extra permission widens what a compromise reaches',
      );
    });

    test('the shipped app has no network permission at all', () {
      // The privacy card promises messages are "never uploaded to any server".
      // Without INTERNET in the merged release manifest that is enforced by the
      // OS rather than by code review.
      expect(manifest.contains('android.permission.INTERNET'), isFalse);
      expect(manifest.contains('ACCESS_NETWORK_STATE'), isFalse);
    });

    test('no permission lets the app write to or receive SMS', () {
      for (final denied in [
        'RECEIVE_SMS',
        'SEND_SMS',
        'WRITE_SMS',
        'READ_CONTACTS',
        'WRITE_EXTERNAL_STORAGE',
      ]) {
        expect(
          manifest.contains(denied),
          isFalse,
          reason: '$denied is not needed to read bank alerts',
        );
      }
    });
  });

  group('SEC-1 tooling-only variants must not re-open backup', () {
    for (final path in [debugManifestPath, profileManifestPath]) {
      final variant = path.split('/')[4];

      test('$variant manifest only adds the Flutter tooling permission', () {
        final source = File(path).readAsStringSync();
        expect(_permissionsIn(source), {'android.permission.INTERNET'});
      });

      test('$variant manifest declares no <application> overrides', () {
        // A manifest-merger override here would flip allowBackup back on for
        // that variant, and nobody reads the merged manifest.
        final source = File(path).readAsStringSync();
        expect(source.contains('allowBackup'), isFalse);
        expect(source.contains('dataExtractionRules'), isFalse);
        expect(source.contains('fullBackupContent'), isFalse);
      });
    }
  });

  group('SEC-1 data_extraction_rules.xml (Android 12+)', () {
    test('the root element is the one the platform reads', () {
      expect(_rootElement(extractionRules), 'data-extraction-rules');
    });

    test('it declares exactly the cloud-backup and device-transfer sections',
        () {
      expect(
        _childElements(extractionRules, 'data-extraction-rules'),
        {'cloud-backup', 'device-transfer'},
        reason: 'an unexpected section is either a typo (ignored) or a new path',
      );
    });

    for (final section in ['cloud-backup', 'device-transfer']) {
      final body = _sectionBody(extractionRules, section);

      test('<$section> is present and terminated', () {
        expect(body, isNotNull, reason: '<$section> is missing or unterminated');
      });

      for (final domain in allDomains) {
        test('<$section> excludes the whole $domain domain', () {
          final excludes = _excludesIn(body!);
          expect(
            excludes[domain],
            '.',
            reason: '$section must exclude $domain with path="."',
          );
        });
      }

      test('<$section> excludes every domain and nothing else', () {
        expect(_excludesIn(body!).keys.toSet(), allDomains);
      });

      test('<$section> has no <include> re-opening the export', () {
        // A single include beats the excludes for the paths it names.
        expect(body!.contains('<include'), isFalse);
      });
    }

    test('cloud backup and device transfer are locked down identically', () {
      // The D2D path is the one allowBackup="false" does not cover, so it must
      // never drift behind the cloud rules.
      expect(
        _excludesIn(_sectionBody(extractionRules, 'device-transfer')!),
        _excludesIn(_sectionBody(extractionRules, 'cloud-backup')!),
      );
    });

    test('no include appears anywhere in the file', () {
      expect(extractionRules.contains('<include'), isFalse);
    });
  });

  group('SEC-1 backup_rules.xml (API <= 30)', () {
    test('the root element is the one the platform reads', () {
      expect(_rootElement(backupRules), 'full-backup-content');
    });

    for (final domain in allDomains) {
      test('the whole $domain domain is excluded', () {
        expect(_excludesIn(backupRules)[domain], '.');
      });
    }

    test('every domain is excluded and nothing else is listed', () {
      expect(_excludesIn(backupRules).keys.toSet(), allDomains);
    });

    test('there is no <include>', () {
      expect(backupRules.contains('<include'), isFalse);
    });

    test('old and new Android agree on what may be exported', () {
      // Same intent on both sides of API 31 — a device on either release must
      // not export more than the other.
      expect(
        _excludesIn(backupRules),
        _excludesIn(_sectionBody(extractionRules, 'cloud-backup')!),
      );
    });

    test('the ledger database is never named as an inclusion', () {
      // Naming the DB at all in a rules file is a smell: the only reason to
      // list a specific file is to include it. (Prose in the header comment
      // documenting *why* it is excluded is fine.)
      for (final rules in [backupRules, extractionRules]) {
        expect(_stripComments(rules).contains('paisa_transactions.db'), isFalse);
      }
    });
  });
}

/// Strips XML comments so a commented-out rule never counts as configuration.
String _stripComments(String xml) =>
    xml.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');

/// The full opening tag of [name], attributes included.
String? _elementTag(String xml, String name) =>
    RegExp('<$name\\b[^>]*>').firstMatch(_stripComments(xml))?.group(0);

String? _rootElement(String xml) => RegExp(r'<([\w-]+)')
    .firstMatch(_stripComments(xml).replaceAll(RegExp(r'<\?[\s\S]*?\?>'), ''))
    ?.group(1);

/// Direct child element names of [parent] (each name once).
Set<String> _childElements(String xml, String parent) {
  final body = _sectionBody(xml, parent);
  if (body == null) return const {};

  final children = <String>{};
  var depth = 0;
  for (final match in RegExp(r'<(/?)([\w-]+)([^>]*)>').allMatches(body)) {
    if (match.group(1) == '/') {
      depth--;
      continue;
    }
    if (depth == 0) children.add(match.group(2)!);
    if (!match.group(3)!.trimRight().endsWith('/')) depth++;
  }
  return children;
}

/// Everything between `<name ...>` and `</name>`, or null when unterminated.
String? _sectionBody(String xml, String name) {
  final source = _stripComments(xml);
  final open = RegExp('<$name\\b[^>]*>').firstMatch(source);
  if (open == null) return null;
  final close = source.indexOf('</$name>', open.end);
  if (close < 0) return null;
  return source.substring(open.end, close);
}

/// `domain -> path` for every `<exclude>` in [xml].
Map<String, String> _excludesIn(String xml) {
  final excludes = <String, String>{};
  for (final match
      in RegExp(r'<exclude\b([^>]*)>').allMatches(_stripComments(xml))) {
    final attributes = match.group(1)!;
    final domain =
        RegExp(r'domain\s*=\s*"([^"]*)"').firstMatch(attributes)?.group(1);
    final path =
        RegExp(r'path\s*=\s*"([^"]*)"').firstMatch(attributes)?.group(1);
    if (domain != null) excludes[domain] = path ?? '';
  }
  return excludes;
}

Set<String> _permissionsIn(String xml) => RegExp(
      r'<uses-permission\b[^>]*android:name\s*=\s*"([^"]*)"',
    )
        .allMatches(_stripComments(xml))
        .map((m) => m.group(1)!)
        .toSet();
