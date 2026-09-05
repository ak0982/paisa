import 'package:flutter/material.dart';
import 'category_info.dart';
import '../theme/paisa_colors.dart';

/// Calendar window for envelope plans — monthly and yearly limits are independent.
enum BudgetPeriod { monthly, yearly }

enum BudgetStatus { safe, warning, over }

class Budget {
  const Budget({
    required this.category,
    required this.spent,
    required this.limit,
    this.isUserSet = false,
  });

  final SpendCategory category;
  final double spent;
  final double limit;

  /// True when [limit] came from a persisted user-set (or once-seeded) value
  /// rather than a live auto-suggestion. Seeded limits are stored so they stay
  /// fixed for the month and can be exceeded — see ISSUE-5.
  final bool isUserSet;

  /// Never set a plan and nothing spent — show a "Set plan" CTA.
  /// Explicit ₹0 ([hasStoredPlan]) is **not** unset.
  bool get isUnset => !hasStoredPlan && limit <= 0 && spent <= 0;

  /// User (or seed) has a stored plan row, including an explicit ₹0 plan.
  bool get hasStoredPlan => isUserSet;

  double get ratio {
    if (limit <= 0) return spent > 0 ? 1.0 : 0.0;
    return spent / limit;
  }

  /// Rupees still available under the plan (0 when over or no positive plan).
  double get remaining =>
      limit > 0 ? (limit - spent).clamp(0.0, double.infinity) : 0.0;

  /// Amount past the plan. When plan is ₹0 and there is spend, equals [spent].
  double get overAmount {
    if (limit <= 0) return spent > 0 ? spent : 0.0;
    return spent > limit ? spent - limit : 0.0;
  }

  /// Whole-number percent of plan used (0 when no positive plan and no spend).
  int get usedPercent {
    if (limit <= 0) return spent > 0 ? 100 : 0;
    return (ratio * 100).round();
  }

  BudgetStatus get status {
    if (limit <= 0) {
      return spent > 0 ? BudgetStatus.over : BudgetStatus.safe;
    }
    if (ratio >= 1) return BudgetStatus.over;
    if (ratio >= 0.75) return BudgetStatus.warning;
    return BudgetStatus.safe;
  }

  /// Aggregate hero OVER / LEFT using the same rules as [status].
  static bool isOverAggregate({required double planned, required double spent}) {
    if (planned <= 0) return spent > 0;
    return spent >= planned;
  }

  Color get barColor {
    switch (status) {
      case BudgetStatus.safe:
        return PaisaColors.safe;
      case BudgetStatus.warning:
        return PaisaColors.warning;
      case BudgetStatus.over:
        return PaisaColors.overBudget;
    }
  }

  String get statusLabel {
    if (isUnset) return 'Set plan';
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
    if (isUnset) return PaisaColors.mutedCaption;
    switch (status) {
      case BudgetStatus.safe:
        return PaisaColors.safe;
      case BudgetStatus.warning:
        return PaisaColors.warning;
      case BudgetStatus.over:
        return PaisaColors.overBudget;
    }
  }

  CategoryInfo get info => CategoryInfo.forCategory(category);
}
