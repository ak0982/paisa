import 'category_info.dart';
import 'manual_transaction.dart';
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
    this.isDebitCardAlertTwin = false,
    this.isLeanDebitCardAlert = false,
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

  /// User-minted cash move (`source == manual`), not parsed from SMS.
  bool get isManual => source == kManualSource;

  /// Survives SMS wipe / full rescan (manual mint or paste).
  bool get preservedAcrossSmsRescan => isPreservedAcrossSmsRescan(source);

  /// Ingest-only (not persisted). Debit-card / CCBP / BBPS spend alert that
  /// may share an event with a same-account sibling SMS.
  final bool isDebitCardAlertTwin;

  /// Ingest-only (not persisted). Lean `ALERT: … spent via Debit Card` ping.
  /// The richer `Spent … Bal … BLOCK DC` row is preferred when collapsing.
  final bool isLeanDebitCardAlert;

  CategoryInfo get categoryInfo => CategoryInfo.forCategory(category);

  bool get hasValidMask =>
      maskedAccount.isNotEmpty && !maskedAccount.contains('????');

  String get accountTypeLabel => switch (accountKind) {
        AccountKind.savings => 'Savings',
        AccountKind.creditCard => 'Credit Card',
        AccountKind.loan => 'Loan',
      };

  /// Every stored cash movement is still SHOWN in Home / Transactions lists
  /// (with a [flowLabel] badge). This drives list membership only — the spend /
  /// income KPIs use [countsTowardSpend] / [countsTowardIncome] instead, so
  /// internal movement (CC bill payments, CC payment-received, self-transfers)
  /// is visible but does not distort the headline numbers. See ISSUE-4.
  bool get countsTowardCashflowSummary => true;

  /// A credit-card bill payment: a debit made to pay down your own card
  /// (CCBP / BBPS / "credit card bill"). It is internal movement — money leaving
  /// a funding account to reduce a card liability — not spend ON the card.
  ///
  /// Enrichment normally tags these as [AccountKind.creditCard], but if that
  /// miss-fires and the row stays savings, the merchant wording alone is still
  /// enough — otherwise KPIs double-count card spend + the funding debit.
  bool get isCreditCardBillPayment {
    if (isCredit) return false;
    final m = merchant.toLowerCase();
    return m.contains('ccbp') || m.contains('credit card bill');
  }

  /// A "payment received" credit on a credit card. This reduces the card's
  /// outstanding balance; it is NOT income.
  bool get isCreditCardPaymentReceived =>
      accountKind == AccountKind.creditCard && isCredit;

  /// Counts toward spend KPIs: a real debit that is not a credit-card bill
  /// payment. NOTE: self-transfers (money moved between your own accounts) are
  /// netted out separately in `FinanceStore`, because deciding that requires
  /// cross-transaction context (a matching opposite leg) that a single
  /// transaction cannot know. Do NOT exclude `category == transfer` here —
  /// ordinary UPI merchant purchases are frequently worded "trf to <merchant>"
  /// and categorised as transfer, so excluding them would drop genuine spend.
  bool get countsTowardSpend => !isCredit && !isCreditCardBillPayment;

  /// Counts toward income KPIs: a real credit that is not a credit-card
  /// payment-received leg. Self-transfer credit legs are netted out in
  /// `FinanceStore` via matching.
  bool get countsTowardIncome => isCredit && !isCreditCardPaymentReceived;

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
