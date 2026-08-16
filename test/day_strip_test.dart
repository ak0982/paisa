import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/models/transaction.dart';
import 'package:paisa_app/models/transaction_sort.dart';
import 'package:paisa_app/providers/finance_store.dart';
import 'package:paisa_app/services/sms/account_discovery.dart';
import 'package:paisa_app/utils/formatters.dart';

/// Day Strip aggregation: OUT/IN match Home KPI rules; list includes internals.
void main() {
  final day = DateTime(2026, 8, 15, 12);

  Transaction tx({
    required String id,
    required double amount,
    required bool isCredit,
    required SpendCategory category,
    AccountKind kind = AccountKind.savings,
    String merchant = 'Test',
    String bank = 'SBI',
    String mask = '••••0429',
    DateTime? timestamp,
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
        timestamp: (timestamp ?? day).add(offset),
        accountKind: kind,
      );

  test('OUT/IN exclude internals; list includes them; net = IN − OUT', () {
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'food',
          amount: 320.58,
          isCredit: false,
          category: SpendCategory.food,
          merchant: 'Swiggy',
          offset: const Duration(hours: -3),
        ),
        tx(
          id: 'salary',
          amount: 500.00,
          isCredit: true,
          category: SpendCategory.income,
          merchant: 'Salary',
          offset: const Duration(hours: -1),
        ),
        tx(
          id: 'ccbp',
          amount: 1200.00,
          isCredit: false,
          category: SpendCategory.transfer,
          kind: AccountKind.creditCard,
          merchant: 'Credit card bill payment',
          mask: '••••1111',
        ),
        tx(
          id: 'cc_in',
          amount: 1200.00,
          isCredit: true,
          category: SpendCategory.transfer,
          kind: AccountKind.creditCard,
          merchant: 'Credit card payment',
          mask: '••••1111',
          offset: const Duration(minutes: 1),
        ),
        tx(
          id: 'xfer_out',
          amount: 2000.00,
          isCredit: false,
          category: SpendCategory.transfer,
          merchant: 'Axis Transfer',
          offset: const Duration(hours: 2),
        ),
        tx(
          id: 'xfer_in',
          amount: 2000.00,
          isCredit: true,
          category: SpendCategory.income,
          merchant: 'Self Transfer',
          bank: 'Axis',
          mask: '••••9867',
          offset: const Duration(hours: 2, seconds: 40),
        ),
      ]);

    expect(store.transactionsForDay(day).length, 6);
    expect(store.daySpend(day), 320.58);
    expect(store.dayIncome(day), 500.00);
    expect(store.dayNet(day), 500.00 - 320.58);

    expect(store.isDayInternalMove(store.transactionsForDay(day)
        .firstWhere((t) => t.id == 'ccbp')), isTrue);
    expect(store.isDayInternalMove(store.transactionsForDay(day)
        .firstWhere((t) => t.id == 'cc_in')), isTrue);
    expect(store.isDayInternalMove(store.transactionsForDay(day)
        .firstWhere((t) => t.id == 'xfer_out')), isTrue);
    expect(store.isDayInternalMove(store.transactionsForDay(day)
        .firstWhere((t) => t.id == 'food')), isFalse);

    // Exact paise — no rounding away from 2 dp.
    expect(formatInr(store.daySpend(day)), '₹320.58');
    expect(formatInr(store.dayNet(day).abs()), contains('179.42'));
  });

  test('empty day returns zeros and empty list', () {
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'other_day',
          amount: 99,
          isCredit: false,
          category: SpendCategory.food,
          timestamp: DateTime(2026, 8, 14, 12),
        ),
      ]);

    expect(store.transactionsForDay(day), isEmpty);
    expect(store.daySpend(day), 0);
    expect(store.dayIncome(day), 0);
    expect(store.dayNet(day), 0);
  });

  test('local calendar day boundaries — midnight neighbors excluded', () {
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'before',
          amount: 10,
          isCredit: false,
          category: SpendCategory.food,
          timestamp: DateTime(2026, 8, 14, 23, 59, 59),
        ),
        tx(
          id: 'start',
          amount: 20.01,
          isCredit: false,
          category: SpendCategory.food,
          timestamp: DateTime(2026, 8, 15, 0, 0, 0),
        ),
        tx(
          id: 'end',
          amount: 30.02,
          isCredit: false,
          category: SpendCategory.food,
          timestamp: DateTime(2026, 8, 15, 23, 59, 59),
        ),
        tx(
          id: 'after',
          amount: 40,
          isCredit: false,
          category: SpendCategory.food,
          timestamp: DateTime(2026, 8, 16, 0, 0, 0),
        ),
      ]);

    final list = store.transactionsForDay(day);
    expect(list.map((t) => t.id).toList(), ['start', 'end']);
    expect(store.daySpend(day), 50.03);
  });

  test('merchant "trf to" debit without opposite leg still counts as OUT', () {
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'buy',
          amount: 3250.75,
          isCredit: false,
          category: SpendCategory.transfer,
          merchant: 'Innofin Solution',
        ),
      ]);

    expect(store.daySpend(day), 3250.75);
    expect(store.isDayInternalMove(store.transactionsForDay(day).single), isFalse);
  });

  test('recentDaySpendSeries returns last N days ending at anchor', () {
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'd13',
          amount: 100,
          isCredit: false,
          category: SpendCategory.food,
          timestamp: DateTime(2026, 8, 13, 12),
        ),
        tx(
          id: 'd14',
          amount: 200,
          isCredit: false,
          category: SpendCategory.food,
          timestamp: DateTime(2026, 8, 14, 12),
        ),
        tx(
          id: 'd15',
          amount: 300,
          isCredit: false,
          category: SpendCategory.food,
          timestamp: DateTime(2026, 8, 15, 12),
        ),
      ]);

    expect(
      store.recentDaySpendSeries(anchor: day, count: 5),
      [0.0, 0.0, 100.0, 200.0, 300.0],
    );
  });

  test('range aggregates inclusive end; single-day equals day APIs', () {
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'd14',
          amount: 100.25,
          isCredit: false,
          category: SpendCategory.food,
          timestamp: DateTime(2026, 8, 14, 10),
        ),
        tx(
          id: 'd15_out',
          amount: 50.50,
          isCredit: false,
          category: SpendCategory.food,
          timestamp: DateTime(2026, 8, 15, 12),
        ),
        tx(
          id: 'd15_in',
          amount: 200.00,
          isCredit: true,
          category: SpendCategory.income,
          timestamp: DateTime(2026, 8, 15, 14),
        ),
        tx(
          id: 'd16',
          amount: 75.00,
          isCredit: false,
          category: SpendCategory.food,
          timestamp: DateTime(2026, 8, 16, 9),
        ),
        // Neighbor outside range (exclusive after endInclusive).
        tx(
          id: 'd17',
          amount: 999,
          isCredit: false,
          category: SpendCategory.food,
          timestamp: DateTime(2026, 8, 17, 0, 0, 0),
        ),
      ]);

    final start = DateTime(2026, 8, 14);
    final end = DateTime(2026, 8, 16);

    expect(
      store.transactionsForDateRange(start, end).map((t) => t.id).toList(),
      ['d14', 'd15_out', 'd15_in', 'd16'],
    );
    expect(store.rangeSpend(start, end), 100.25 + 50.50 + 75.00);
    expect(store.rangeIncome(start, end), 200.00);
    expect(
      store.rangeNet(start, end),
      200.00 - (100.25 + 50.50 + 75.00),
    );

    // Single-day range matches day APIs.
    expect(
      store.transactionsForDateRange(day, day).length,
      store.transactionsForDay(day).length,
    );
    expect(store.rangeSpend(day, day), store.daySpend(day));
    expect(store.rangeIncome(day, day), store.dayIncome(day));
  });

  test('empty range returns zeros and empty list', () {
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'other',
          amount: 40,
          isCredit: false,
          category: SpendCategory.food,
          timestamp: DateTime(2026, 8, 10, 12),
        ),
      ]);

    final start = DateTime(2026, 8, 14);
    final end = DateTime(2026, 8, 16);
    expect(store.transactionsForDateRange(start, end), isEmpty);
    expect(store.rangeSpend(start, end), 0);
    expect(store.rangeIncome(start, end), 0);
    expect(store.rangeNet(start, end), 0);
  });

  test('range swaps inverted start/end and keeps inclusive bounds', () {
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'a',
          amount: 10,
          isCredit: false,
          category: SpendCategory.food,
          timestamp: DateTime(2026, 8, 14, 12),
        ),
        tx(
          id: 'b',
          amount: 20,
          isCredit: false,
          category: SpendCategory.food,
          timestamp: DateTime(2026, 8, 15, 23, 59, 59),
        ),
        tx(
          id: 'c',
          amount: 30,
          isCredit: false,
          category: SpendCategory.food,
          timestamp: DateTime(2026, 8, 16, 0, 0, 0),
        ),
      ]);

    // end before start — still inclusive of both calendar days.
    expect(
      store
          .transactionsForDateRange(
            DateTime(2026, 8, 15),
            DateTime(2026, 8, 14),
          )
          .map((t) => t.id)
          .toList(),
      ['a', 'b'],
    );
    expect(
      store.rangeSpend(DateTime(2026, 8, 15), DateTime(2026, 8, 14)),
      30,
    );
  });

  test('monthDaySpendMap + daySpendIntensity for calendar highlights', () {
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'low',
          amount: 100,
          isCredit: false,
          category: SpendCategory.food,
          timestamp: DateTime(2026, 8, 10, 12),
        ),
        tx(
          id: 'high',
          amount: 400,
          isCredit: false,
          category: SpendCategory.food,
          timestamp: DateTime(2026, 8, 15, 12),
        ),
        tx(
          id: 'income_only',
          amount: 5000,
          isCredit: true,
          category: SpendCategory.income,
          timestamp: DateTime(2026, 8, 20, 12),
        ),
      ]);

    final map = store.monthDaySpendMap(DateTime(2026, 8, 1));
    expect(map[10], 100);
    expect(map[15], 400);
    expect(map.containsKey(20), isFalse); // income-only day omitted
    expect(store.daySpendIntensity(DateTime(2026, 8, 15), monthMap: map), 1.0);
    expect(store.daySpendIntensity(DateTime(2026, 8, 10), monthMap: map), 0.25);
    expect(store.daySpendIntensity(DateTime(2026, 8, 20), monthMap: map), 0);
    // Empty month must not throw.
    expect(store.monthDaySpendMap(DateTime(2025, 1, 1)), isEmpty);
    expect(store.daySpendIntensity(DateTime(2025, 1, 5)), 0);
  });

  test('sortTransactions orders day-strip lists as expected', () {
    final list = [
      tx(
        id: 'mid',
        amount: 200,
        isCredit: false,
        category: SpendCategory.food,
        offset: const Duration(hours: 2),
      ),
      tx(
        id: 'low',
        amount: 50,
        isCredit: false,
        category: SpendCategory.food,
        offset: const Duration(hours: 5),
      ),
      tx(
        id: 'high',
        amount: 500,
        isCredit: false,
        category: SpendCategory.food,
        offset: const Duration(hours: 1),
      ),
    ];

    expect(
      sortTransactions(list, TransactionSort.dateAsc).map((t) => t.id).toList(),
      ['high', 'mid', 'low'],
    );
    expect(
      sortTransactions(list, TransactionSort.dateDesc).map((t) => t.id).toList(),
      ['low', 'mid', 'high'],
    );
    expect(
      sortTransactions(list, TransactionSort.amountAsc)
          .map((t) => t.id)
          .toList(),
      ['low', 'mid', 'high'],
    );
    expect(
      sortTransactions(list, TransactionSort.amountDesc)
          .map((t) => t.id)
          .toList(),
      ['high', 'mid', 'low'],
    );
  });
}
