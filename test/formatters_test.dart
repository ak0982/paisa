import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/utils/formatters.dart';

void main() {
  group('formatInr', () {
    test('shows paise for fractional amounts (0.85 not 1)', () {
      final formatted = formatInr(0.85);
      expect(formatted, contains('0.85'));
      expect(formatted, isNot(contains('1.00')));
      expect(formatted, startsWith('₹'));
    });

    test('preserves paise for 23.60', () {
      final formatted = formatInr(23.60);
      expect(formatted, contains('23.60'));
    });

    test('shows .00 for whole amounts', () {
      expect(formatInr(500), contains('500.00'));
    });
  });

  group('formatAmount', () {
    test('preserves paise for debit 99.99', () {
      final formatted = formatAmount(99.99, isCredit: false);
      expect(formatted, contains('99.99'));
      expect(formatted, startsWith('−'));
    });

    test('credit prefix with paise', () {
      final formatted = formatAmount(12.5, isCredit: true);
      expect(formatted, startsWith('+'));
      expect(formatted, contains('12.50'));
    });
  });

  group('formatCompactInr', () {
    test('matches formatInr with decimals', () {
      expect(formatCompactInr(0.85), formatInr(0.85));
      expect(formatCompactInr(500), formatInr(500));
    });
  });

  group('formatSharePercent', () {
    test('omits non-positive shares', () {
      expect(formatSharePercent(0), '');
      expect(formatSharePercent(-0.1), '');
    });

    test('integer percent when >= 1%', () {
      expect(formatSharePercent(0.32), '32%');
      expect(formatSharePercent(1), '100%');
      expect(formatSharePercent(0.01), '1%');
    });

    test('one decimal between 0.1% and 1%', () {
      expect(formatSharePercent(0.004), '0.4%');
      expect(formatSharePercent(0.001), '0.1%');
      expect(formatSharePercent(0.0099), '1.0%');
    });

    test('two decimals between 0.01% and 0.1%', () {
      expect(formatSharePercent(0.0003), '0.03%');
      expect(formatSharePercent(0.0001), '0.01%');
    });

    test('shows <0.01% for tinier shares', () {
      expect(formatSharePercent(0.00005), '<0.01%');
      expect(formatSharePercent(0.000001), '<0.01%');
    });
  });
}
