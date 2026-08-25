import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/models/transaction.dart';
import 'package:paisa_app/models/transaction_sort.dart';
import 'package:paisa_app/providers/finance_store.dart';
import 'package:paisa_app/screens/day_strip_screen.dart';
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

  test('CC spend counts as OUT; CC payment-received is MOVE not IN', () {
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'cc_spend',
          amount: 236.00,
          isCredit: false,
          category: SpendCategory.shopping,
          kind: AccountKind.creditCard,
          merchant: 'Amazon',
          mask: '••••1111',
        ),
        tx(
          id: 'cc_recv',
          amount: 5000.00,
          isCredit: true,
          category: SpendCategory.transfer,
          kind: AccountKind.creditCard,
          merchant: 'Payment received',
          mask: '••••1111',
          offset: const Duration(hours: 1),
        ),
        tx(
          id: 'salary',
          amount: 100.25,
          isCredit: true,
          category: SpendCategory.income,
          merchant: 'Payroll',
          offset: const Duration(hours: 2),
        ),
      ]);

    expect(store.transactionsForDay(day).length, 3);
    expect(store.daySpend(day), 236.00);
    expect(store.dayIncome(day), 100.25);
    expect(store.isDayInternalMove(store.transactionsForDay(day)
        .firstWhere((t) => t.id == 'cc_recv')), isTrue);
    expect(store.isDayInternalMove(store.transactionsForDay(day)
        .firstWhere((t) => t.id == 'cc_spend')), isFalse);
    expect(formatInr(store.daySpend(day)), '₹236.00');
    expect(formatInr(store.dayIncome(day)), '₹100.25');
  });

  test('CCBP via merchant wording alone is MOVE and excluded from OUT', () {
    // Enrichment may leave accountKind as savings; merchant still tags CCBP.
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'ccbp_savings_kind',
          amount: 1200.50,
          isCredit: false,
          category: SpendCategory.transfer,
          kind: AccountKind.savings,
          merchant: 'CCBP HDFC',
        ),
        tx(
          id: 'food',
          amount: 40.00,
          isCredit: false,
          category: SpendCategory.food,
          offset: const Duration(minutes: 5),
        ),
      ]);

    expect(store.transactionsForDay(day).length, 2);
    expect(store.daySpend(day), 40.00);
    expect(
      store.isDayInternalMove(
        store.transactionsForDay(day).firstWhere((t) => t.id == 'ccbp_savings_kind'),
      ),
      isTrue,
    );
  });

  test('self-transfer pair excluded from OUT/IN but listed with MOVE', () {
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'xfer_out',
          amount: 1500.75,
          isCredit: false,
          category: SpendCategory.transfer,
          bank: 'SBI',
          mask: '••••0429',
          merchant: 'NEFT to Axis',
        ),
        tx(
          id: 'xfer_in',
          amount: 1500.75,
          isCredit: true,
          category: SpendCategory.income,
          bank: 'Axis',
          mask: '••••9867',
          merchant: 'Self Transfer',
          offset: const Duration(minutes: 1),
        ),
        tx(
          id: 'food',
          amount: 12.50,
          isCredit: false,
          category: SpendCategory.food,
          offset: const Duration(hours: 3),
        ),
      ]);

    final list = store.transactionsForDay(day);
    expect(list.map((t) => t.id).toList(), ['xfer_out', 'xfer_in', 'food']);
    expect(store.daySpend(day), 12.50);
    expect(store.dayIncome(day), 0);
    expect(store.daySelfTransferLegIds(day), {'xfer_out', 'xfer_in'});
    expect(store.isDayInternalMove(list[0]), isTrue);
    expect(store.isDayInternalMove(list[1]), isTrue);
    expect(store.isDayInternalMove(list[2]), isFalse);
  });

  test('self-transfer outside 3-minute window still counts as OUT and IN', () {
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'xfer_out',
          amount: 800,
          isCredit: false,
          category: SpendCategory.transfer,
          bank: 'SBI',
          mask: '••••0429',
        ),
        tx(
          id: 'xfer_in',
          amount: 800,
          isCredit: true,
          category: SpendCategory.income,
          bank: 'Axis',
          mask: '••••9867',
          merchant: 'Self Transfer',
          offset: const Duration(minutes: 4),
        ),
      ]);

    expect(store.daySpend(day), 800);
    expect(store.dayIncome(day), 800);
    expect(store.daySelfTransferLegIds(day), isEmpty);
  });

  test('wallet credit with same amount does not cancel real bank debit', () {
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'upi_out',
          amount: 500,
          isCredit: false,
          category: SpendCategory.transfer,
          bank: 'SBI',
          mask: '••••0429',
          merchant: 'trf to Merchant',
        ),
        tx(
          id: 'wallet_in',
          amount: 500,
          isCredit: true,
          category: SpendCategory.income,
          bank: 'Paytm',
          mask: '••••1234',
          merchant: 'Cashback',
          offset: const Duration(minutes: 1),
        ),
      ]);

    expect(store.daySpend(day), 500);
    expect(store.dayIncome(day), 500);
    expect(store.daySelfTransferLegIds(day), isEmpty);
  });

  test('dayBounds are local midnight inclusive/exclusive', () {
    final (start, end) = FinanceStore.dayBounds(DateTime(2026, 8, 15, 18, 30));
    expect(start, DateTime(2026, 8, 15));
    expect(end, DateTime(2026, 8, 16));
    expect(start.isUtc, isFalse);
    expect(end.isUtc, isFalse);
  });

  test('23:59 vs next-day 00:01 land on different calendar days', () {
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'late',
          amount: 11.11,
          isCredit: false,
          category: SpendCategory.food,
          timestamp: DateTime(2026, 8, 15, 23, 59, 0),
        ),
        tx(
          id: 'early',
          amount: 22.22,
          isCredit: false,
          category: SpendCategory.food,
          timestamp: DateTime(2026, 8, 16, 0, 1, 0),
        ),
      ]);

    expect(
      store.transactionsForDay(DateTime(2026, 8, 15)).map((t) => t.id).toList(),
      ['late'],
    );
    expect(store.daySpend(DateTime(2026, 8, 15)), 11.11);
    expect(
      store.transactionsForDay(DateTime(2026, 8, 16)).map((t) => t.id).toList(),
      ['early'],
    );
    expect(store.daySpend(DateTime(2026, 8, 16)), 22.22);
  });

  test('paise preserved across multiple OUT/IN rows', () {
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'a',
          amount: 0.85,
          isCredit: false,
          category: SpendCategory.other,
        ),
        tx(
          id: 'b',
          amount: 23.60,
          isCredit: false,
          category: SpendCategory.food,
          offset: const Duration(minutes: 10),
        ),
        tx(
          id: 'c',
          amount: 1000.07,
          isCredit: true,
          category: SpendCategory.income,
          offset: const Duration(hours: 1),
        ),
      ]);

    expect(store.daySpend(day), closeTo(24.45, 1e-9));
    expect(store.dayIncome(day), 1000.07);
    expect(formatInr(store.daySpend(day)), '₹24.45');
    expect(formatInr(store.dayIncome(day)), '₹1,000.07');
    expect(formatInr(store.dayNet(day)), contains('975.62'));
  });

  test('range excludes CCBP and self-transfer across multi-day window', () {
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'd14_food',
          amount: 50.25,
          isCredit: false,
          category: SpendCategory.food,
          timestamp: DateTime(2026, 8, 14, 10),
        ),
        tx(
          id: 'd14_ccbp',
          amount: 900,
          isCredit: false,
          category: SpendCategory.transfer,
          kind: AccountKind.creditCard,
          merchant: 'Credit card bill payment',
          mask: '••••1111',
          timestamp: DateTime(2026, 8, 14, 18),
        ),
        tx(
          id: 'd15_xfer_out',
          amount: 2000,
          isCredit: false,
          category: SpendCategory.transfer,
          bank: 'SBI',
          mask: '••••0429',
          timestamp: DateTime(2026, 8, 15, 12),
        ),
        tx(
          id: 'd15_xfer_in',
          amount: 2000,
          isCredit: true,
          category: SpendCategory.income,
          bank: 'Axis',
          mask: '••••9867',
          merchant: 'Self Transfer',
          timestamp: DateTime(2026, 8, 15, 12, 1),
        ),
        tx(
          id: 'd16_in',
          amount: 300.50,
          isCredit: true,
          category: SpendCategory.income,
          timestamp: DateTime(2026, 8, 16, 9),
        ),
      ]);

    final start = DateTime(2026, 8, 14);
    final end = DateTime(2026, 8, 16);
    expect(store.transactionsForDateRange(start, end).length, 5);
    expect(store.rangeSpend(start, end), 50.25);
    expect(store.rangeIncome(start, end), 300.50);
    expect(
      store.isRangeInternalMove(
        store.transactionsForDateRange(start, end)
            .firstWhere((t) => t.id == 'd14_ccbp'),
        start: start,
        endInclusive: end,
      ),
      isTrue,
    );
    expect(
      store.isRangeInternalMove(
        store.transactionsForDateRange(start, end)
            .firstWhere((t) => t.id == 'd15_xfer_out'),
        start: start,
        endInclusive: end,
      ),
      isTrue,
    );
  });

  test('cross-midnight self-transfer: day-scoped vs range-scoped matching', () {
    // Legs within 3 minutes but on different local calendar days.
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'out_late',
          amount: 777,
          isCredit: false,
          category: SpendCategory.transfer,
          bank: 'SBI',
          mask: '••••0429',
          timestamp: DateTime(2026, 8, 14, 23, 59),
        ),
        tx(
          id: 'in_early',
          amount: 777,
          isCredit: true,
          category: SpendCategory.income,
          bank: 'Axis',
          mask: '••••9867',
          merchant: 'Self Transfer',
          timestamp: DateTime(2026, 8, 15, 0, 1),
        ),
      ]);

    // Single-day views cannot pair the legs → each day shows KPI movement.
    expect(store.daySpend(DateTime(2026, 8, 14)), 777);
    expect(store.dayIncome(DateTime(2026, 8, 14)), 0);
    expect(store.daySpend(DateTime(2026, 8, 15)), 0);
    expect(store.dayIncome(DateTime(2026, 8, 15)), 777);

    // Inclusive range sees both legs and nets them out.
    final start = DateTime(2026, 8, 14);
    final end = DateTime(2026, 8, 15);
    expect(store.transactionsForDateRange(start, end).length, 2);
    expect(store.rangeSpend(start, end), 0);
    expect(store.rangeIncome(start, end), 0);
    expect(store.rangeSelfTransferLegIds(start, end), {'out_late', 'in_early'});
  });

  test('range inclusive of end day 23:59; next midnight excluded', () {
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'end_edge',
          amount: 15.15,
          isCredit: false,
          category: SpendCategory.food,
          timestamp: DateTime(2026, 8, 16, 23, 59, 59),
        ),
        tx(
          id: 'after',
          amount: 99,
          isCredit: false,
          category: SpendCategory.food,
          timestamp: DateTime(2026, 8, 17, 0, 0, 0),
        ),
      ]);

    expect(
      store
          .transactionsForDateRange(DateTime(2026, 8, 15), DateTime(2026, 8, 16))
          .map((t) => t.id)
          .toList(),
      ['end_edge'],
    );
    expect(
      store.rangeSpend(DateTime(2026, 8, 15), DateTime(2026, 8, 16)),
      15.15,
    );
  });

  test('dayStripOutShare arc proportions', () {
    expect(dayStripOutShare(0, 0), 0);
    expect(dayStripOutShare(100, 0), 1);
    expect(dayStripOutShare(0, 50), 0);
    expect(dayStripOutShare(75, 25), 0.75);
    expect(dayStripOutShare(320.58, 500.00), 320.58 / (320.58 + 500.00));
  });

  test('formatDayStripHeader and range header cover same-month and cross-month', () {
    expect(formatDayStripHeader(DateTime(2026, 8, 15)), 'SAT 15 AUG');
    expect(
      formatDayStripRangeHeader(DateTime(2026, 8, 12), DateTime(2026, 8, 15)),
      '12–15 AUG',
    );
    expect(
      formatDayStripRangeHeader(DateTime(2026, 7, 28), DateTime(2026, 8, 2)),
      '28 JUL – 2 AUG',
    );
    expect(
      formatDayStripRangeHeader(DateTime(2025, 12, 30), DateTime(2026, 1, 2)),
      '30 DEC 2025 – 2 JAN 2026',
    );
    // Inverted args still produce ordered inclusive header.
    expect(
      formatDayStripRangeHeader(DateTime(2026, 8, 15), DateTime(2026, 8, 12)),
      '12–15 AUG',
    );
  });

  test('dayStripMerchantLabel masks when requested', () {
    expect(dayStripMerchantLabel('Swiggy', false), 'Swiggy');
    expect(dayStripMerchantLabel('Swiggy', true), 'Sw••••gy');
    expect(dayStripMerchantLabel('AB', true), 'AB');
    expect(dayStripMerchantLabel('Cafe', true), 'C••e');
  });

  test('income-only day: OUT zero, IN exact, list length 1', () {
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'in_only',
          amount: 42.42,
          isCredit: true,
          category: SpendCategory.income,
          merchant: 'Refund',
        ),
      ]);

    expect(store.transactionsForDay(day).length, 1);
    expect(store.daySpend(day), 0);
    expect(store.dayIncome(day), 42.42);
    expect(store.dayNet(day), 42.42);
    expect(formatInr(store.dayIncome(day)), '₹42.42');
  });

  test('spend-only day: IN zero, OUT exact, net negative', () {
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'out_only',
          amount: 99.99,
          isCredit: false,
          category: SpendCategory.bills,
        ),
      ]);

    expect(store.daySpend(day), 99.99);
    expect(store.dayIncome(day), 0);
    expect(store.dayNet(day), -99.99);
  });

  test('transactionsForDay sorts oldest to newest', () {
    final store = FinanceStore()
      ..seedTransactions([
        tx(
          id: 'third',
          amount: 3,
          isCredit: false,
          category: SpendCategory.food,
          offset: const Duration(hours: 5),
        ),
        tx(
          id: 'first',
          amount: 1,
          isCredit: false,
          category: SpendCategory.food,
          offset: const Duration(hours: 1),
        ),
        tx(
          id: 'second',
          amount: 2,
          isCredit: false,
          category: SpendCategory.food,
          offset: const Duration(hours: 3),
        ),
      ]);

    expect(
      store.transactionsForDay(day).map((t) => t.id).toList(),
      ['first', 'second', 'third'],
    );
  });
}
