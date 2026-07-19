import 'category_info.dart';
import '../services/sms/account_discovery.dart';

class Transaction {
  const Transaction({
    required this.id,
    required this.merchant,
    required this.bank,
    required this.maskedAccount,
    required this.category,
    required this.amount,
    required this.isCredit,
    required this.timestamp,
    this.source = 'SMS',
    this.smsId,
    this.accountKind = AccountKind.savings,
  });

  final String id;
  final String? smsId;
  final String merchant;
  final String bank;
  final String maskedAccount;
  final SpendCategory category;
  final double amount;
  final bool isCredit;
  final DateTime timestamp;
  final String source;
  final AccountKind accountKind;

  CategoryInfo get categoryInfo => CategoryInfo.forCategory(category);

  bool get hasValidMask =>
      maskedAccount.isNotEmpty && !maskedAccount.contains('????');

  String get accountTypeLabel => switch (accountKind) {
        AccountKind.savings => 'Savings',
        AccountKind.creditCard => 'Credit Card',
        AccountKind.loan => 'Loan',
      };

  /// Every stored cash movement counts toward Home spend/income lists.
  bool get countsTowardCashflowSummary => true;

  /// Money-in for Home: every parsed credit (bank, wallet, CC payment-in, etc.).
  bool get countsTowardIncome => isCredit;

  bool get isCreditCardBillPayment {
    if (accountKind != AccountKind.creditCard || isCredit) return false;
    final m = merchant.toLowerCase();
    return m.contains('ccbp') || m.contains('credit card bill');
  }

  String get flowLabel {
    if (accountKind == AccountKind.creditCard) {
      if (isCreditCardBillPayment) return 'CC bill paid';
      return isCredit ? 'CC payment in' : 'CC spend';
    }
    if (accountKind == AccountKind.loan) {
      return isCredit ? 'Loan credit' : 'Loan EMI paid';
    }
    return isCredit ? 'Money in' : 'Money out';
  }

  String get accountLine {
    final parts = <String>[bank, accountTypeLabel];
    if (hasValidMask) parts.add(maskedAccount);
    return parts.join(' · ');
  }

  String get metaLine => '$accountLine · ${categoryInfo.label}';
}
