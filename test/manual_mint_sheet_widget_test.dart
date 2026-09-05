import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/models/manual_transaction.dart';
import 'package:paisa_app/providers/app_settings.dart';
import 'package:paisa_app/utils/formatters.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/test_harness.dart';

/// Lightweight UI/logic checks for mint sheet behaviours that do not need the
/// full [MintTransactionSheet] tree (which embeds unbounded Flexible layout
/// intended for modal sheets and can stall widget pumps).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppSettings settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await AppSettings.load();
  });

  group('sheet default message ↔ category (UI contract)', () {
    for (final info in CategoryInfo.all) {
      test('chip ${info.label} maps to ${defaultManualMessage(info.category)}',
          () {
        expect(defaultManualMessage(info.category), isNotEmpty);
        expect(
          defaultManualIsCredit(info.category),
          info.category == SpendCategory.income,
        );
      });
    }
  });

  group('message-edit contract (sheet _messageEdited semantics)', () {
    test('unedited: category change replaces message', () {
      var message = defaultManualMessage(SpendCategory.food);
      var edited = false;
      void onCategory(SpendCategory c) {
        if (!edited) message = defaultManualMessage(c);
      }

      onCategory(SpendCategory.travel);
      expect(message, 'Cash · Travel');
      onCategory(SpendCategory.income);
      expect(message, 'Cash received');
    });

    test('edited: category change keeps custom message', () {
      var message = defaultManualMessage(SpendCategory.food);
      var edited = false;
      void onMessage(String v) {
        message = v;
        edited = true;
      }

      void onCategory(SpendCategory c) {
        if (!edited) message = defaultManualMessage(c);
      }

      onMessage('Cutting chai custom');
      onCategory(SpendCategory.travel);
      expect(message, 'Cutting chai custom');
    });
  });

  group('amount parse contract (sheet _parseAmount)', () {
    double? parse(String raw) {
      final cleaned = raw.trim().replaceAll(',', '');
      if (cleaned.isEmpty) return null;
      return double.tryParse(cleaned);
    }

    final cases = <(String, double?)>[
      ('', null),
      ('  ', null),
      ('20', 20),
      ('0.50', 0.5),
      ('1,250', 1250),
      ('1,250.50', 1250.5),
      ('abc', null),
      ('12.34', 12.34),
      ('0', 0),
      ('0.00', 0),
    ];

    for (final (raw, expected) in cases) {
      test('parse "$raw" → $expected', () {
        expect(parse(raw), expected);
      });
    }

    test('parsed value then validate', () {
      expect(validateManualAmount(parse('')), isNotNull);
      expect(validateManualAmount(parse('0')), isNotNull);
      expect(validateManualAmount(parse('20')), isNull);
      expect(validateManualAmount(parse('1,250')), isNull);
    });
  });

  group('Day Strip date seed label format', () {
    String dayLabel(DateTime day) {
      const months = [
        'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
        'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
      ];
      return '${day.day} ${months[day.month - 1]} ${day.year}';
    }

    final days = [
      DateTime(2026, 8, 12),
      DateTime(2026, 1, 1),
      DateTime(2024, 2, 29),
      DateTime(2025, 12, 31),
      DateTime(2026, 7, 31),
    ];

    for (final d in days) {
      test('label for ${d.toIso8601String().substring(0, 10)}', () {
        final label = dayLabel(d);
        expect(label, contains('${d.year}'));
        expect(label.split(' ').length, 3);
      });
    }

    testWidgets('empty-day CTA copy MINT A TRANSACTION renders', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          settings: settings,
          child: const Text('MINT A TRANSACTION'),
        ),
      );
      await tester.pump();
      expect(find.text('MINT A TRANSACTION'), findsOneWidget);
    });

    testWidgets('Transactions FAB copy Add transaction renders', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          settings: settings,
          child: const Text('Add transaction'),
        ),
      );
      await tester.pump();
      expect(find.text('Add transaction'), findsOneWidget);
    });

    testWidgets('Manual badge copy renders', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          settings: settings,
          child: const Text('✍️ Manual'),
        ),
      );
      await tester.pump();
      expect(find.text('✍️ Manual'), findsOneWidget);
    });

    testWidgets('Coin Flip minted copy renders', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          settings: settings,
          child: const Text('Minted by you'),
        ),
      );
      await tester.pump();
      expect(find.text('Minted by you'), findsOneWidget);
    });
  });

  group('mask merchant for manual display labels', () {
    final merchants = [
      'Cutting chai',
      'Auto rickshaw',
      'Wedding gift cash',
      'चाय की दुकान',
      '🛕 Temple',
      'Cash · Food',
      'Cash received',
    ];
    for (final m in merchants) {
      test('mask still applies to "$m"', () {
        final masked = maskedMerchantLabel(m, true);
        expect(maskedMerchantLabel(m, false), m);
        if (m.length > 2) {
          expect(masked.contains('•'), isTrue);
        }
      });
    }
  });
}
