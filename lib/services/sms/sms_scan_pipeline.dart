import 'parsed_sms_transaction.dart';
import 'sms_parser.dart';

/// Result of running a single SMS through the staged scan pipeline.
enum SmsPipelineOutcome {
  /// Sender does not look like a bank / UPI provider.
  notFinancialSender,

  /// Body too short or clearly not financial.
  notFinancialBody,

  /// OTP-only message without transaction details.
  otpOnly,

  /// Loan / card / marketing offer.
  promo,

  /// Bank-like but no debit/credit/UPI signal.
  noTransactionSignal,

  /// Passed all filters but regex did not extract a transaction.
  parseFailed,

  /// Successfully parsed transaction.
  parsed,
}

class SmsPipelineResult {
  const SmsPipelineResult({
    required this.outcome,
    this.transaction,
  });

  final SmsPipelineOutcome outcome;
  final ParsedSmsTransaction? transaction;

  bool get isParsed => outcome == SmsPipelineOutcome.parsed;
}

/// Fast multi-stage SMS filter — cheap checks first, full regex last.
///
/// Stage 1: financial sender? (string contains, no regex)
/// Stage 2: financial body hint? (lightweight keywords)
/// Stage 3: promo / offer? (skip marketing)
/// Stage 4: transaction signal? (debited, credited, UPI, etc.)
/// Stage 5: full [SmsParser.parseTransaction] regex extraction
abstract final class SmsScanPipeline {
  static const _senderHints = [
    'HDFC',
    'SBI',
    'SBIN',
    'ICICI',
    'AXIS',
    'KOTAK',
    'PAYTM',
    'PHONEPE',
    'GPAY',
    'GOOGLEPAY',
    'GOOGLE',
    'BHIM',
    'YESBNK',
    'YESBANK',
    'INDUS',
    'PNB',
    'CANARA',
    'BARODA',
    'FEDERAL',
    'IDFC',
    'UPI',
    'NEFT',
    'IMPS',
    'LENDEN',
    'SBICRD',
    'SBICGV',
    'HDFCBK',
    'ICICIO',
    'ICICIT',
    'IDFCFB',
    'KOTAKB',
    'HSBCIN',
    'HSBC',
  ];

  static const _bodyBankHints = [
    'hdfc',
    'sbi',
    'icici',
    'axis bank',
    'axis',
    'kotak',
    'paytm',
    'phonepe',
    'google pay',
    'gpay',
    'yes bank',
    'indusind',
    'pnb',
    'canara',
    'bank of baroda',
    'idfc',
    'hsbc',
  ];

  static const _bodyTxnHints = [
    'debited',
    'credited',
    'spent',
    'paid',
    'received',
    'withdrawn',
    'deposited',
    'depositing',
    'loan ac',
    'loan a/c',
    'payment of',
    'payment received',
    'credit card',
    'card ending',
    'emi',
    'upi',
    'neft',
    'imps',
    'rtgs',
    'a/c',
    'acct',
    'account',
    'bal ',
    'balance',
    'rs.',
    'rs ',
    'inr ',
    '₹',
  ];

  /// Stage 1 — O(1) sender check, skips most personal SMS instantly.
  static bool isFinancialSender(String sender) {
    if (sender.isEmpty) return false;
    final upper = sender.toUpperCase();
    for (final hint in _senderHints) {
      if (upper.contains(hint)) return true;
    }
    return false;
  }

  /// Stage 2 — lightweight body hints when sender is generic (e.g. VM-XXXX).
  static bool hasFinancialBodyHint(String body) {
    if (body.length < 20) return false;
    final lower = body.toLowerCase();
    for (final hint in _bodyBankHints) {
      if (lower.contains(hint)) return true;
    }
    for (final hint in _bodyTxnHints) {
      if (lower.contains(hint)) return true;
    }
    return false;
  }

  /// Stage 1 + 2 combined — requires min body length and txn/bank signal.
  static bool passesFinancialGate(String sender, String body) {
    final trimmed = body.trim();
    if (trimmed.length < 20) return false;

    // Personal numbers never send legitimate bank/UPI alerts. Reject them at
    // the financial gate — do not let a completed-txn phrase ("debited") reopen
    // the door (that was ISSUE-3 hole #2 for bare 10-digit senders).
    if (SmsParser.isPersonalPhoneSender(sender)) return false;

    if (hasFinancialBodyHint(trimmed)) return true;
    return isFinancialSender(sender) && SmsParser.hasTransactionSignal(trimmed);
  }

  /// Run all stages and return outcome + optional parsed transaction.
  static SmsPipelineResult process(SmsMessageInput message) {
    final sender = message.sender;
    final body = message.body.trim();

    // Bank OTP SMS: reject before financial gate (gate requires txn signals).
    if (body.length >= 20 &&
        isFinancialSender(sender) &&
        (SmsParser.isOtpOnly(body) || _looksLikeOtp(body))) {
      return const SmsPipelineResult(outcome: SmsPipelineOutcome.otpOnly);
    }

    if (!passesFinancialGate(sender, body)) {
      if (!isFinancialSender(sender)) {
        return const SmsPipelineResult(outcome: SmsPipelineOutcome.notFinancialSender);
      }
      return const SmsPipelineResult(outcome: SmsPipelineOutcome.notFinancialBody);
    }

    if (SmsParser.isOtpOnly(body) || _looksLikeOtp(body)) {
      return const SmsPipelineResult(outcome: SmsPipelineOutcome.otpOnly);
    }

    if (SmsParser.isPromoOrOfferSms(body, sender: sender)) {
      return const SmsPipelineResult(outcome: SmsPipelineOutcome.promo);
    }

    if (!SmsParser.isRealTransactionSms(sender, body)) {
      return const SmsPipelineResult(outcome: SmsPipelineOutcome.noTransactionSignal);
    }

    final parsed = SmsParser.parseTransaction(message);
    if (parsed == null) {
      return const SmsPipelineResult(outcome: SmsPipelineOutcome.parseFailed);
    }

    return SmsPipelineResult(
      outcome: SmsPipelineOutcome.parsed,
      transaction: parsed,
    );
  }

  static bool _looksLikeOtp(String body) {
    if (SmsParser.hasTransactionSignal(body)) return false;
    final lower = body.toLowerCase();
    return lower.contains('otp') ||
        lower.contains('one time password') ||
        lower.contains('verification code') ||
        lower.contains('do not share');
  }
}
