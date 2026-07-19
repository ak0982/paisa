import 'category_info.dart';

/// Aggregated spending / income analytics for a date range.
class RangeReport {
  const RangeReport({
    required this.start,
    required this.end,
    required this.spent,
    required this.income,
    required this.transactionCount,
    required this.categorySpending,
    required this.topMerchants,
    required this.incomeSources,
    required this.dailyAverage,
    required this.highestDaySpend,
    required this.topCategory,
  });

  final DateTime start;
  final DateTime end;
  final double spent;
  final double income;
  final int transactionCount;

  /// Spend per category, sorted high → low by the store.
  final Map<SpendCategory, double> categorySpending;

  /// (merchant, "N transactions", total) sorted high → low.
  final List<(String name, String sub, double amount)> topMerchants;

  /// (source, total) sorted high → low.
  final List<(String source, double amount)> incomeSources;

  final double dailyAverage;
  final double highestDaySpend;
  final SpendCategory? topCategory;

  double get saved => (income - spent).clamp(0, double.infinity);

  double get savingsRate {
    if (income <= 0) return 0;
    return (saved / income).clamp(0.0, 1.0);
  }

  double get net => income - spent;

  bool get isEmpty => transactionCount == 0;

  int get dayCount {
    final diff = end.difference(start).inDays + 1;
    return diff < 1 ? 1 : diff;
  }
}
