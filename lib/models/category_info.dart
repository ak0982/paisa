import 'package:flutter/material.dart';

import '../theme/paisa_colors.dart';

enum SpendCategory {
  food,
  travel,
  shopping,
  bills,
  entertainment,
  emi,
  health,
  transfer,
  income,
  atm,
  other,
}

class CategoryInfo {
  const CategoryInfo({
    required this.category,
    required this.label,
    required this.emoji,
    required this.tintBg,
    required this.iconColor,
  });

  final SpendCategory category;
  final String label;
  final String emoji;
  /// Solid saturated fill used as chip / icon tile background (Neo-Vault).
  final Color tintBg;
  final Color iconColor;

  static const all = <CategoryInfo>[
    CategoryInfo(
      category: SpendCategory.food,
      label: 'Food',
      emoji: '🍔',
      tintBg: PaisaColors.catFood,
      iconColor: PaisaColors.catFood,
    ),
    CategoryInfo(
      category: SpendCategory.travel,
      label: 'Travel',
      emoji: '🚗',
      tintBg: PaisaColors.catTravel,
      iconColor: PaisaColors.catTravel,
    ),
    CategoryInfo(
      category: SpendCategory.shopping,
      label: 'Shopping',
      emoji: '🛍️',
      tintBg: PaisaColors.catShopping,
      iconColor: PaisaColors.catShopping,
    ),
    CategoryInfo(
      category: SpendCategory.bills,
      label: 'Bills',
      emoji: '⚡',
      tintBg: PaisaColors.catBills,
      iconColor: PaisaColors.catBills,
    ),
    CategoryInfo(
      category: SpendCategory.entertainment,
      label: 'Entertainment',
      emoji: '🎬',
      tintBg: PaisaColors.catEntertainment,
      iconColor: PaisaColors.catEntertainment,
    ),
    CategoryInfo(
      category: SpendCategory.emi,
      label: 'EMI',
      emoji: '🏦',
      tintBg: PaisaColors.catEmi,
      iconColor: PaisaColors.catEmi,
    ),
    CategoryInfo(
      category: SpendCategory.health,
      label: 'Health',
      emoji: '💊',
      tintBg: PaisaColors.catHealth,
      iconColor: PaisaColors.catHealth,
    ),
    CategoryInfo(
      category: SpendCategory.transfer,
      label: 'Transfer',
      emoji: '🔄',
      tintBg: PaisaColors.catTransfer,
      iconColor: PaisaColors.catTransfer,
    ),
    CategoryInfo(
      category: SpendCategory.income,
      label: 'Income',
      emoji: '💰',
      tintBg: PaisaColors.catIncome,
      iconColor: PaisaColors.catIncome,
    ),
    CategoryInfo(
      category: SpendCategory.atm,
      label: 'ATM',
      emoji: '🏧',
      tintBg: PaisaColors.catAtm,
      iconColor: PaisaColors.catAtm,
    ),
    CategoryInfo(
      category: SpendCategory.other,
      label: 'Other',
      emoji: '📦',
      tintBg: PaisaColors.catOther,
      iconColor: PaisaColors.catOther,
    ),
  ];

  static CategoryInfo forCategory(SpendCategory c) =>
      all.firstWhere((e) => e.category == c);
}
