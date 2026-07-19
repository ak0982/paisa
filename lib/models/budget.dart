import 'package:flutter/material.dart';
import 'category_info.dart';
import '../theme/paisa_colors.dart';

enum BudgetStatus { safe, warning, over }

class Budget {
  const Budget({
    required this.category,
    required this.spent,
    required this.limit,
  });

  final SpendCategory category;
  final double spent;
  final double limit;

  double get ratio => limit > 0 ? spent / limit : 0;

  BudgetStatus get status {
    if (ratio >= 1) return BudgetStatus.over;
    if (ratio >= 0.75) return BudgetStatus.warning;
    return BudgetStatus.safe;
  }

  Color get barColor {
    switch (status) {
      case BudgetStatus.safe:
        return PaisaColors.credit;
      case BudgetStatus.warning:
        return PaisaColors.warning;
      case BudgetStatus.over:
        return PaisaColors.overBudget;
    }
  }

  String get statusLabel {
    switch (status) {
      case BudgetStatus.safe:
        return 'On track';
      case BudgetStatus.warning:
        return 'Almost there';
      case BudgetStatus.over:
        return 'Over budget';
    }
  }

  Color get statusColor {
    switch (status) {
      case BudgetStatus.safe:
        return PaisaColors.credit;
      case BudgetStatus.warning:
        return PaisaColors.warning;
      case BudgetStatus.over:
        return PaisaColors.overBudget;
    }
  }

  CategoryInfo get info => CategoryInfo.forCategory(category);
}
