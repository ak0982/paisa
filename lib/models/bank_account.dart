import 'package:flutter/material.dart';

import '../services/sms/account_discovery.dart';

class BankAccount {
  const BankAccount({
    required this.name,
    required this.mask,
    required this.badge,
    required this.color,
    this.isActive = true,
    this.receivedTotal = 0,
    this.spentTotal = 0,
    this.kind = AccountKind.savings,
    this.activityCount = 0,
  });

  final String name;
  final String mask;
  final String badge;
  final Color color;
  final bool isActive;
  /// Total credits received into this savings account (all time in local data).
  final double receivedTotal;
  /// Total debits/spend on this account or card.
  final double spentTotal;
  final AccountKind kind;
  final int activityCount;

  bool get isCreditCard => kind == AccountKind.creditCard;
  bool get isLoan => kind == AccountKind.loan;
  bool get isSavings => kind == AccountKind.savings;
}
