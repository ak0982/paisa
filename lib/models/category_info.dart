import 'package:flutter/material.dart';

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
  final Color tintBg;
  final Color iconColor;

  static const all = <CategoryInfo>[
    CategoryInfo(
      category: SpendCategory.food,
      label: 'Food',
      emoji: '🍔',
      tintBg: Color(0xFFFFEDE7),
      iconColor: Color(0xFFD9663F),
    ),
    CategoryInfo(
      category: SpendCategory.travel,
      label: 'Travel',
      emoji: '🚗',
      tintBg: Color(0xFFE7F0FF),
      iconColor: Color(0xFF3B6FD4),
    ),
    CategoryInfo(
      category: SpendCategory.shopping,
      label: 'Shopping',
      emoji: '🛍️',
      tintBg: Color(0xFFF3E8FF),
      iconColor: Color(0xFF8B44D6),
    ),
    CategoryInfo(
      category: SpendCategory.bills,
      label: 'Bills',
      emoji: '⚡',
      tintBg: Color(0xFFFDF3DD),
      iconColor: Color(0xFFB4791A),
    ),
    CategoryInfo(
      category: SpendCategory.entertainment,
      label: 'Entertainment',
      emoji: '🎬',
      tintBg: Color(0xFFE8E9FD),
      iconColor: Color(0xFF4F52D6),
    ),
    CategoryInfo(
      category: SpendCategory.emi,
      label: 'EMI',
      emoji: '🏦',
      tintBg: Color(0xFFE3F5EC),
      iconColor: Color(0xFF0B7A4B),
    ),
    CategoryInfo(
      category: SpendCategory.health,
      label: 'Health',
      emoji: '💊',
      tintBg: Color(0xFFFCE7F1),
      iconColor: Color(0xFFC43C7E),
    ),
    CategoryInfo(
      category: SpendCategory.transfer,
      label: 'Transfer',
      emoji: '🔄',
      tintBg: Color(0xFFDEF5F1),
      iconColor: Color(0xFF0E9488),
    ),
    CategoryInfo(
      category: SpendCategory.income,
      label: 'Income',
      emoji: '💰',
      tintBg: Color(0xFFE3F0E7),
      iconColor: Color(0xFF0B7A4B),
    ),
    CategoryInfo(
      category: SpendCategory.atm,
      label: 'ATM',
      emoji: '🏧',
      tintBg: Color(0xFFEEF1F4),
      iconColor: Color(0xFF5B6B7B),
    ),
    CategoryInfo(
      category: SpendCategory.other,
      label: 'Other',
      emoji: '📦',
      tintBg: Color(0xFFF1F4F7),
      iconColor: Color(0xFF64748B),
    ),
  ];

  static CategoryInfo forCategory(SpendCategory c) =>
      all.firstWhere((e) => e.category == c);
}
