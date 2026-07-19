import 'package:flutter_test/flutter_test.dart';

import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/providers/finance_store.dart';

import 'helpers/dummy_data.dart';

void main() {
  group('Insights full-history window', () {
    test('insightsSince equals the earliest transaction date', () {
      final store = FinanceStore()
        ..seedTransactions(dummyTransactionHistory());
      // Earliest txn in the dummy set is 2026-04-01.
      expect(store.earliestTransactionDate, DateTime(2026, 4, 1, 12));
      expect(store.insightsSince, store.earliestTransactionDate);
    });

    test('insightsTransactions covers the entire history, not a 12mo window',
        () {
      final store = FinanceStore()
        ..seedTransactions(dummyTransactionHistory());
      // Every seeded transaction is included regardless of age.
      expect(store.insightsTransactions.length, store.transactions.length);
    });

    test('old transactions beyond 12 months are still included', () {
      final store = FinanceStore()
        ..seedTransactions([
          dummyTxn(
            id: 'old',
            merchant: 'Old Shop',
            amount: 999,
            isCredit: false,
            category: SpendCategory.shopping,
            // ~3 years before "now" — the previous rolling window dropped this.
            timestamp: DateTime.now().subtract(const Duration(days: 365 * 3)),
          ),
          dummyTxn(
            id: 'recent',
            merchant: 'New Shop',
            amount: 100,
            isCredit: false,
            category: SpendCategory.shopping,
            timestamp: DateTime.now().subtract(const Duration(days: 2)),
          ),
        ]);
      expect(store.insightsTransactions.length, 2);
      expect(store.insightsSpent, 1099);
    });

    test('insightsPeriodLabel is dynamic ("Since <month> <year>")', () {
      final store = FinanceStore()
        ..seedTransactions(dummyTransactionHistory());
      expect(store.insightsPeriodLabel, 'Since Apr 2026');
    });

    test('insightsPeriodLabel is "All time" when there is no data', () {
      final store = FinanceStore();
      expect(store.insightsPeriodLabel, 'All time');
    });

    test('insights getters do not crash on an empty store', () {
      final store = FinanceStore();
      expect(store.insightsSpent, 0);
      expect(store.insightsDailyAverage, 0);
      expect(store.insightsHighestDaySpend, 0);
      expect(store.insightsTransactions, isEmpty);
      expect(store.insightsFoodDelta(), isNull);
    });
  });
}
