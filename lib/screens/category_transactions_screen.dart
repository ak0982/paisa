import 'package:flutter/material.dart';

import '../models/category_info.dart';
import 'filtered_transactions_screen.dart';

/// Lists debit transactions for one category.
///
/// Without [range], uses the Insights window (`store.insightsTransactions`).
/// With [range], filters to that inclusive report date range instead.
///
/// Thin wrapper around [FilteredTransactionsScreen.category] so Insights and
/// Reports category drill-downs keep a stable API.
class CategoryTransactionsScreen extends StatelessWidget {
  const CategoryTransactionsScreen({
    super.key,
    required this.category,
    this.range,
    this.periodLabel,
  });

  final SpendCategory category;

  /// Optional inclusive date range (Reports). When null, uses Insights period.
  final DateTimeRange? range;

  /// Subtitle under the category name. Defaults to Insights period label.
  final String? periodLabel;

  @override
  Widget build(BuildContext context) {
    return FilteredTransactionsScreen.category(
      category: category,
      range: range,
      periodLabel: periodLabel,
    );
  }
}
