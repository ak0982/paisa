import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/models/transaction_sort.dart';

import 'helpers/dummy_data.dart';

void main() {
  final txns = [
    dummyTxn(
      id: 'a',
      merchant: 'A',
      amount: 500,
      isCredit: false,
      timestamp: DateTime(2026, 7, 5, 10, 0),
    ),
    dummyTxn(
      id: 'b',
      merchant: 'B',
      amount: 100,
      isCredit: false,
      timestamp: DateTime(2026, 7, 7, 18, 0),
    ),
    dummyTxn(
      id: 'c',
      merchant: 'C',
      amount: 900,
      isCredit: false,
      timestamp: DateTime(2026, 7, 5, 8, 0),
    ),
    dummyTxn(
      id: 'd',
      merchant: 'D',
      amount: 100,
      isCredit: true,
      timestamp: DateTime(2026, 7, 1, 9, 0),
    ),
  ];

  group('sortTransactions', () {
    test('dateDesc orders newest first (default)', () {
      final result = sortTransactions(txns, TransactionSort.dateDesc);
      expect(result.map((t) => t.id).toList(), ['b', 'a', 'c', 'd']);
      expect(TransactionSort.defaultSort, TransactionSort.dateDesc);
    });

    test('dateAsc orders oldest first', () {
      final result = sortTransactions(txns, TransactionSort.dateAsc);
      expect(result.map((t) => t.id).toList(), ['d', 'c', 'a', 'b']);
    });

    test('amountDesc orders high to low, ties broken by newest', () {
      final result = sortTransactions(txns, TransactionSort.amountDesc);
      expect(result.map((t) => t.id).toList(), ['c', 'a', 'b', 'd']);
    });

    test('amountAsc orders low to high, ties broken by newest', () {
      final result = sortTransactions(txns, TransactionSort.amountAsc);
      // b and d both 100 -> newer (b, 7 Jul) before d (1 Jul).
      expect(result.map((t) => t.id).toList(), ['b', 'd', 'a', 'c']);
    });

    test('does not mutate the input list', () {
      final input = List.of(txns);
      sortTransactions(input, TransactionSort.amountDesc);
      expect(input.map((t) => t.id).toList(), ['a', 'b', 'c', 'd']);
    });
  });

  group('buildTransactionSections', () {
    test('date sort groups by day in descending order', () {
      final sections =
          buildTransactionSections(txns, TransactionSort.dateDesc);
      // Three distinct days: 7 Jul, 5 Jul, 1 Jul.
      expect(sections.length, 3);
      expect(sections.every((s) => s.header != null), isTrue);
      // First group is the newest day and holds only 'b'.
      expect(sections.first.items.map((t) => t.id).toList(), ['b']);
      // Middle group is 5 Jul with 'a' (10:00) before 'c' (08:00).
      expect(sections[1].items.map((t) => t.id).toList(), ['a', 'c']);
      expect(sections.last.items.map((t) => t.id).toList(), ['d']);
    });

    test('date ascending groups by day oldest first', () {
      final sections =
          buildTransactionSections(txns, TransactionSort.dateAsc);
      expect(sections.first.items.map((t) => t.id).toList(), ['d']);
      expect(sections[1].items.map((t) => t.id).toList(), ['c', 'a']);
      expect(sections.last.items.map((t) => t.id).toList(), ['b']);
    });

    test('amount sort produces a single flat header-less section', () {
      final sections =
          buildTransactionSections(txns, TransactionSort.amountDesc);
      expect(sections.length, 1);
      expect(sections.single.header, isNull);
      expect(
        sections.single.items.map((t) => t.id).toList(),
        ['c', 'a', 'b', 'd'],
      );
    });

    test('empty input yields no sections', () {
      expect(buildTransactionSections([], TransactionSort.dateDesc), isEmpty);
      expect(buildTransactionSections([], TransactionSort.amountAsc), isEmpty);
    });
  });

  group('TransactionSort metadata', () {
    test('classification flags are correct', () {
      expect(TransactionSort.dateDesc.isDate, isTrue);
      expect(TransactionSort.dateAsc.isDate, isTrue);
      expect(TransactionSort.amountDesc.isAmount, isTrue);
      expect(TransactionSort.amountAsc.isAmount, isTrue);
      expect(TransactionSort.dateAsc.isAscending, isTrue);
      expect(TransactionSort.amountAsc.isAscending, isTrue);
      expect(TransactionSort.dateDesc.isAscending, isFalse);
    });

    test('every option exposes label, shortLabel, and icon', () {
      for (final s in TransactionSort.values) {
        expect(s.label, isNotEmpty);
        expect(s.shortLabel, isNotEmpty);
        expect(s.icon, isNotNull);
      }
    });
  });
}
