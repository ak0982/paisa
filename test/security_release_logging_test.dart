import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:paisa_app/providers/finance_store.dart';

/// SEC-4 — `debugPrint` and `debugPrintStack` are **not** compiled out of a
/// release build. They write to logcat, which any app holding READ_LOGS and
/// anyone with an ADB cable can read. The scan path handles bank SMS and the
/// exceptions it catches quote the offending message, so an ungated log there
/// publishes the customer's financial alerts to the device log.
///
/// A grep for `debugPrint` is easy to write and easy to fool (a call three
/// lines below an unrelated `kDebugMode` mention looks guarded). So the guard
/// detector is a real brace-scoped scanner, and the first group proves the
/// scanner itself has teeth before it is pointed at `lib/`.
void main() {
  group('the logging detector actually detects', () {
    late Directory sandbox;

    setUp(() => sandbox = Directory.systemTemp.createTempSync('paisa_sec4'));
    tearDown(() => sandbox.deleteSync(recursive: true));

    List<String> scan(String source) {
      File('${sandbox.path}/sample.dart').writeAsStringSync(source);
      return findUngatedLogging(sandbox).map((o) => o.code).toList();
    }

    test('a bare debugPrint is reported', () {
      expect(
        scan('void f() {\n  debugPrint("boom");\n}\n'),
        ['debugPrint("boom");'],
      );
    });

    test('a call inside an if (kDebugMode) block is accepted', () {
      expect(
        scan('void f() {\n'
            '  if (kDebugMode) {\n'
            '    debugPrint("boom");\n'
            '  }\n'
            '}\n'),
        isEmpty,
      );
    });

    test('a single-line guard is accepted', () {
      expect(
        scan('void f() {\n  if (kDebugMode) debugPrint("boom");\n}\n'),
        isEmpty,
      );
    });

    test('nesting inside the guard is still accepted', () {
      expect(
        scan('void f() {\n'
            '  if (kDebugMode) {\n'
            '    for (final x in xs) {\n'
            '      debugPrint(x);\n'
            '    }\n'
            '  }\n'
            '}\n'),
        isEmpty,
      );
    });

    test('a call after the guard block closed is reported', () {
      // This is the case a "kDebugMode within 3 lines" grep waves through.
      expect(
        scan('void f() {\n'
            '  if (kDebugMode) {\n'
            '    final x = 1;\n'
            '  }\n'
            '  debugPrint("boom");\n'
            '}\n'),
        ['debugPrint("boom");'],
      );
    });

    test('a call in a sibling method of a guarded one is reported', () {
      expect(
        scan('class A {\n'
            '  void a() {\n'
            '    if (kDebugMode) {\n'
            '      debugPrint("ok");\n'
            '    }\n'
            '  }\n'
            '  void b() {\n'
            '    print("boom");\n'
            '  }\n'
            '}\n'),
        ['print("boom");'],
      );
    });

    test('commented-out and documented calls are ignored', () {
      expect(
        scan('/// Logged with debugPrint in debug builds only.\n'
            'void f() {\n'
            '  // debugPrint("old");\n'
            '}\n'),
        isEmpty,
      );
    });

    test('a call named inside a string literal is ignored', () {
      expect(
        scan('void f() {\n  final s = "call debugPrint(x) here";\n}\n'),
        isEmpty,
      );
    });

    test('debugPrintStack counts as logging', () {
      expect(
        scan('void f() {\n  debugPrintStack(stackTrace: s);\n}\n'),
        ['debugPrintStack(stackTrace: s);'],
      );
    });

    test('non-dart files are not scanned', () {
      File('${sandbox.path}/notes.txt').writeAsStringSync('debugPrint("x");');
      expect(findUngatedLogging(sandbox), isEmpty);
    });
  });

  group('SEC-4 release builds keep quiet', () {
    test('no ungated print / debugPrint / debugPrintStack anywhere in lib/',
        () {
      final offenders = findUngatedLogging(Directory('lib'));
      expect(
        offenders,
        isEmpty,
        reason: 'these reach release logcat:\n'
            '${offenders.map((o) => '  $o').join('\n')}',
      );
    });

    test('the SMS scan failure path still logs, but only in debug', () {
      // The named SEC-4 finding: this handler catches PlatformExceptions whose
      // message can quote the SMS row it choked on. The diagnostics are worth
      // keeping for debug builds, so assert both halves — they exist, and they
      // are guarded.
      final lines = File('lib/providers/finance_store.dart').readAsLinesSync();
      expect(
        lines.where((l) => _loggingCall.hasMatch(_stripNonCode(l))),
        isNotEmpty,
        reason: 'the scan diagnostics disappeared entirely',
      );
      expect(_scanFile('finance_store.dart', lines), isEmpty);
    });

    test('nothing in lib/ logs through dart:developer', () {
      // developer.log survives release too, and is not covered by avoid_print.
      final offenders = <String>[];
      for (final file in _dartFiles(Directory('lib'))) {
        if (file.readAsStringSync().contains("import 'dart:developer'")) {
          offenders.add(file.path);
        }
      }
      expect(offenders, isEmpty);
    });

    test('nothing in lib/ writes to stdout or stderr', () {
      final offenders = <String>[];
      for (final file in _dartFiles(Directory('lib'))) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final code = _stripNonCode(lines[i]);
          if (RegExp(r'\b(stdout|stderr)\s*\.\s*(write|writeln|add)')
              .hasMatch(code)) {
            offenders.add('${file.path}:${i + 1}');
          }
        }
      }
      expect(offenders, isEmpty);
    });
  });

  group('SEC-4 what the customer sees instead of the exception', () {
    // ISSUE-8's user-facing half: the scan error banner must be readable copy,
    // never platform internals — and the internals are exactly what a leaked
    // log would have carried.
    const smsLeak =
        'Rs.4,999.00 debited from a/c XX5300 to AMAZON UPI Ref 9365227';

    final leaky = <String, Object>{
      'PlatformException with an SMS in the message': PlatformException(
        code: 'SMS_SCAN_FAILED',
        message: smsLeak,
        details: {'row': 8121, 'body': smsLeak},
      ),
      'PlatformException with a file path': PlatformException(
        code: 'DB_LOCKED',
        message: '/data/user/0/com.paisa.paisa_app/paisa_transactions.db',
      ),
      'MissingPluginException': MissingPluginException(
        'No implementation found for method scanInboxBatch',
      ),
      'a raw state error': StateError('cursor closed at offset 8121'),
      'a format error over a body': const FormatException(
        'bad amount',
        smsLeak,
      ),
    };

    for (final entry in leaky.entries) {
      test('${entry.key} becomes plain user copy', () {
        final message = FinanceStore.friendlyScanError(entry.value);

        expect(
          message,
          anyOf(
            contains("We couldn't read your SMS inbox"),
            contains('Something went wrong while scanning your messages'),
          ),
        );
        expect(message.contains(smsLeak), isFalse);
        expect(message.contains('paisa_transactions.db'), isFalse);
        expect(message.contains('Exception'), isFalse);
        expect(message.contains('scanInboxBatch'), isFalse);
        expect(message.contains('8121'), isFalse);
      });
    }

    test('a permission-shaped platform failure points at SMS access', () {
      expect(
        FinanceStore.friendlyScanError(
          PlatformException(code: 'PERMISSION_DENIED'),
        ),
        contains('SMS access'),
      );
    });

    test('the copy is a short sentence, not a dump', () {
      for (final error in leaky.values) {
        final message = FinanceStore.friendlyScanError(error);
        expect(message.length, lessThan(160));
        expect(message.contains('\n'), isFalse);
      }
    });
  });
}

/// A logging call that would reach logcat in a release build.
class LogOffender {
  const LogOffender(this.file, this.line, this.code);

  final String file;
  final int line;
  final String code;

  @override
  String toString() => '$file:$line: $code';
}

final _loggingCall = RegExp(r'\b(debugPrintStack|debugPrint|print)\s*\(');

Iterable<File> _dartFiles(Directory root) => root
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

/// Every logging call in [root] that is not inside a `kDebugMode` guard.
List<LogOffender> findUngatedLogging(Directory root) {
  final offenders = <LogOffender>[];
  for (final file in _dartFiles(root)) {
    offenders.addAll(_scanFile(file.path, file.readAsLinesSync()));
  }
  return offenders;
}

/// Brace-scoped scan: a call counts as guarded only while the innermost
/// `kDebugMode` block that opened is still open.
List<LogOffender> _scanFile(String path, List<String> lines) {
  final offenders = <LogOffender>[];
  var depth = 0;
  int? gateDepth;
  var pendingGate = false;

  for (var i = 0; i < lines.length; i++) {
    final code = _stripNonCode(lines[i]);
    final gatedHere = code.contains('kDebugMode');
    if (gatedHere) pendingGate = true;

    if (_loggingCall.hasMatch(code) && gateDepth == null && !gatedHere) {
      offenders.add(LogOffender(path, i + 1, lines[i].trim()));
    }

    for (final char in code.split('')) {
      if (char == '{') {
        depth++;
        gateDepth ??= pendingGate ? depth : null;
        if (pendingGate) pendingGate = false;
      } else if (char == '}') {
        if (gateDepth != null && depth <= gateDepth) gateDepth = null;
        depth--;
      }
    }

    // `if (kDebugMode) debugPrint(x);` opens no block, so the pending guard
    // ends with the statement. A guard split over lines has neither yet.
    if (pendingGate && code.contains(';')) pendingGate = false;
  }

  return offenders;
}

/// Drops string literals and comments so neither can hide — or fake — a call.
String _stripNonCode(String line) {
  var code = line
      .replaceAll(RegExp(r'"(?:[^"\\]|\\.)*"'), '""')
      .replaceAll(RegExp(r"'(?:[^'\\]|\\.)*'"), "''")
      .replaceAll(RegExp(r'/\*.*?\*/'), '');
  final comment = code.indexOf('//');
  return comment >= 0 ? code.substring(0, comment) : code;
}
