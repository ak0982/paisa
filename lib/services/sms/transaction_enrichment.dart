import 'account_discovery.dart';
import 'sms_keyword_lists.dart';
import 'sms_parser.dart';

/// Enriches parsed SMS transactions with account masks, kinds, and labels.
abstract final class TransactionEnrichment {
  static final _creditCardBody = RegExp(
    r'credit\s+card|card ending|card\s+x\d{4}|yes\s+bank\s+card|bobcard|ccbp',
    caseSensitive: false,
  );

  static final _loanBody = RegExp(
    r'\b(emi|loan a/c|loan ac|personal loan|home loan|housing loan|car loan)\b',
    caseSensitive: false,
  );

  static String resolveMaskedAccount({
    required String parsedMask,
    required String sender,
    required String body,
  }) {
    if (!_isUnknownMask(parsedMask)) return parsedMask;

    final discovered = AccountDiscovery.discover(sender: sender, body: body);
    if (discovered != null) return discovered.mask;

    final last4 = SmsParser.extractAccountLast4(body);
    if (last4 != null) return SmsParser.maskFromLast4(last4);

    return '';
  }

  static AccountKind resolveAccountKind({
    required String bank,
    required String mask,
    required String body,
    required Iterable<DiscoveredAccount> discoveries,
  }) {
    final lower = body.toLowerCase();

    // Loan payments often debit a savings account via NACH — detect from SMS body
    // before falling back to the debited account's discovered type.
    if (looksLikeLoanPayment(lower)) return AccountKind.loan;

    if (looksLikeCreditCardTransaction(lower)) return AccountKind.creditCard;

    if (_creditCardBody.hasMatch(lower)) return AccountKind.creditCard;
    if (_loanBody.hasMatch(lower)) return AccountKind.loan;

    if (mask.isNotEmpty) {
      final byBankMask = discoveries.where(
        (d) => d.mask == mask && d.bank == bank,
      );
      if (byBankMask.length == 1) return byBankMask.first.kind;

      final byMask = discoveries.where((d) => d.mask == mask).toList();
      if (byMask.length == 1) return byMask.first.kind;

      final cc = byMask.where((d) => d.kind == AccountKind.creditCard);
      if (cc.isNotEmpty) return AccountKind.creditCard;
    }

    return AccountKind.savings;
  }

  static bool looksLikeLoanPayment(String lower) {
    if (categoryLooksLikeEmi(lower)) return true;
    if (lower.contains('ecs/nach dishonored')) return true;
    if (lower.contains('against your loan ac')) return true;
    if (lower.contains('depositing an amount') && lower.contains('loan ac')) {
      return true;
    }
    if (lower.contains('loan instalment') ||
        lower.contains('loan installment')) {
      return true;
    }
    return false;
  }

  static bool looksLikeCreditCardTransaction(String lower) {
    if (looksLikeLoanPayment(lower)) return false;

    if (lower.contains('ccbp') || lower.contains('mbk ccbp')) return true;

    if (RegExp(
      r'spent on (?:your )?(?:\w+ ){0,4}(?:bank )?(?:\w+ ){0,3}credit card',
      caseSensitive: false,
    ).hasMatch(lower)) {
      return true;
    }
    if (RegExp(r'spent on yes bank card', caseSensitive: false).hasMatch(lower)) {
      return true;
    }
    // Low-risk scheme-aware hint: "spent on … Visa/RuPay card …"
    final scheme = SmsKeywordLists.detectCardScheme(lower);
    if (scheme != null &&
        RegExp(
          r'spent on .{0,40}\b(?:credit\s+)?card\b',
          caseSensitive: false,
        ).hasMatch(lower)) {
      return true;
    }
    if (lower.contains('delicious purchase') && lower.contains('credit card')) {
      return true;
    }

    if (lower.contains('received payment') &&
        lower.contains('bbps') &&
        lower.contains('credit card')) {
      return true;
    }
    if (RegExp(
      r'payment of .*received towards your',
      caseSensitive: false,
    ).hasMatch(lower)) {
      if (lower.contains('credit card') ||
          lower.contains('yes bank card') ||
          lower.contains('bobcard')) {
        return true;
      }
    }
    if (lower.contains('is spent on your bobcard')) return true;
    if (lower.contains('debited for') && lower.contains('credit card')) {
      return true;
    }
    if (lower.contains('spent using') && lower.contains('icici bank card')) {
      return true;
    }
    if (lower.contains('credited towards your') &&
        lower.contains('credit card')) {
      return true;
    }
    if (lower.contains('reversal') && lower.contains('credit card')) {
      return true;
    }

    return false;
  }

  /// Route CC bill payments (CCBP) and card-specific SMS to the right card.
  static ({String bank, String mask}) resolveCreditCardDisplay({
    required String body,
    required String parsedBank,
    required String parsedMask,
    required Iterable<DiscoveredAccount> discoveries,
  }) {
    final lower = body.toLowerCase();
    final last4 = SmsParser.extractAccountLast4(body);
    if (last4 != null) {
      final mask = SmsParser.maskFromLast4(last4);
      final byMask = discoveries.where((d) => d.mask == mask).toList();
      if (byMask.length == 1) {
        return (bank: byMask.first.bank, mask: mask);
      }
      final cc = byMask.where((d) => d.kind == AccountKind.creditCard);
      if (cc.isNotEmpty) return (bank: cc.first.bank, mask: mask);
      return (bank: parsedBank, mask: mask);
    }

    if (lower.contains('bobcard')) {
      final bob = discoveries.where(
        (d) => d.kind == AccountKind.creditCard && d.bank.toLowerCase().contains('bob'),
      );
      if (bob.isNotEmpty) return (bank: bob.first.bank, mask: bob.first.mask);
      return (bank: 'BOB', mask: parsedMask);
    }

    if (lower.contains('ccbp')) {
      final cards = discoveries
          .where((d) => d.kind == AccountKind.creditCard)
          .toList();
      if (cards.length == 1) {
        return (bank: cards.first.bank, mask: cards.first.mask);
      }
    }

    final cc = discoveries.where(
      (d) =>
          d.kind == AccountKind.creditCard &&
          d.bank.toLowerCase() == parsedBank.toLowerCase(),
    );
    if (cc.length == 1) return (bank: cc.first.bank, mask: cc.first.mask);

    return (bank: parsedBank, mask: parsedMask);
  }

  static String? creditCardLabelFromBody(String body, {required bool isCredit}) {
    final lower = body.toLowerCase();
    if (lower.contains('ccbp') || lower.contains('mbk ccbp')) {
      return 'Credit card bill payment';
    }
    if (isCredit) {
      if (lower.contains('bbps')) return 'Credit card payment (BBPS)';
      if (lower.contains('bobcard')) return 'BOB credit card payment';
      if (lower.contains('credited towards')) return 'Credit card payment';
      return 'Credit card payment';
    }
    if (lower.contains('delicious purchase')) {
      final at = RegExp(
        r"at\s+([A-Za-z0-9 .&'_-]+?)(?:\s+on|\s+\d{2})",
        caseSensitive: false,
      ).firstMatch(body);
      if (at != null) return _titleCase(at.group(1)!.trim());
    }
    return null;
  }

  static bool categoryLooksLikeEmi(String lower) {
    return lower.contains('nach-') ||
        lower.contains('towards nach') ||
        lower.contains('emi of') ||
        lower.contains('tp ach');
  }

  /// When EMI is paid via NACH from a savings account, show the loan account.
  static ({String bank, String mask}) resolveLoanDisplay({
    required String body,
    required String parsedBank,
    required String parsedMask,
    required Iterable<DiscoveredAccount> discoveries,
  }) {
    final lower = body.toLowerCase();

    DiscoveredAccount? loanFor(String bankHint) {
      final matches = discoveries
          .where(
            (d) =>
                d.kind == AccountKind.loan &&
                d.bank.toLowerCase().contains(bankHint),
          )
          .toList();
      return matches.isEmpty ? null : matches.first;
    }

    if (lower.contains('nach-10-hdfc') ||
        lower.contains('hdfc bank limited')) {
      final loan = loanFor('hdfc');
      return (bank: loan?.bank ?? 'HDFC', mask: loan?.mask ?? '');
    }
    if (lower.contains('tp ach icici') ||
        lower.contains('nach-10-tp ach icici')) {
      final loan = loanFor('icici');
      return (bank: loan?.bank ?? 'ICICI', mask: loan?.mask ?? '');
    }
    if (lower.contains('idfc first bank')) {
      final loan = loanFor('idfc');
      return (bank: loan?.bank ?? 'IDFC', mask: loan?.mask ?? '');
    }
    if (lower.contains('loan ac')) {
      final last4 = SmsParser.extractAccountLast4(body);
      return (
        bank: parsedBank,
        mask: SmsParser.maskFromLast4(last4),
      );
    }

    return (bank: parsedBank, mask: parsedMask);
  }

  static String improveMerchant({
    required String merchant,
    required String body,
    required bool isCredit,
    required AccountKind accountKind,
  }) {
    if (accountKind == AccountKind.loan) {
      final loanLabel = loanLabelFromBody(body);
      if (loanLabel != null) return loanLabel;
    }

    if (accountKind == AccountKind.creditCard) {
      final ccLabel = creditCardLabelFromBody(body, isCredit: isCredit);
      if (ccLabel != null) return ccLabel;
    }

    final trimmed = merchant.trim();
    if (trimmed.isNotEmpty &&
        trimmed.toLowerCase() != 'transaction' &&
        trimmed.toLowerCase() != 'credit received' &&
        !_isNachMerchant(trimmed)) {
      if (SmsKeywordLists.isKnownUpiVpa(trimmed)) {
        return trimmed.toLowerCase();
      }
      final stripped = SmsKeywordLists.stripBalanceSuffix(trimmed);
      if (stripped.isNotEmpty) return stripped;
      return trimmed;
    }

    if (accountKind == AccountKind.creditCard) {
      final ccLabel = creditCardLabelFromBody(body, isCredit: isCredit);
      if (ccLabel != null) return ccLabel;
      if (isCredit) return 'Credit card payment';
      final at = RegExp(
        r"at\s+([A-Za-z0-9 .&'_-]+?)(?:\s+on|\s+\d{2}-|\.)",
        caseSensitive: false,
      ).firstMatch(body);
      if (at != null) return _titleCase(at.group(1)!.trim());
      return 'Credit card spend';
    }

    if (accountKind == AccountKind.loan) {
      return loanLabelFromBody(body) ?? 'Loan EMI';
    }

    if (isCredit) {
      final salary = RegExp(
        r"(?:credited by|deposited in|salary|neft cr|imps cr)\s+([A-Za-z0-9 .&'_-]{3,40})",
        caseSensitive: false,
      ).firstMatch(body);
      if (salary != null) return _titleCase(salary.group(1)!.trim());

      final fromVpa = RegExp(
        r'from VPA\s+([A-Za-z0-9._+\-]+@[A-Za-z0-9._+\-]+)',
        caseSensitive: false,
      ).firstMatch(body);
      if (fromVpa != null) {
        final raw = fromVpa.group(1)!;
        if (SmsKeywordLists.isKnownUpiVpa(raw)) return raw.toLowerCase();
        return raw;
      }

      final allowlisted = SmsKeywordLists.extractUpiVpa(body);
      if (allowlisted != null) return allowlisted;

      return 'Money received';
    }

    final towards = RegExp(
      r"towards\s+([A-Za-z0-9 .&'_-]{3,40})",
      caseSensitive: false,
    ).firstMatch(body);
    if (towards != null) return _titleCase(towards.group(1)!.trim());

    final allowlistedDebit = SmsKeywordLists.extractUpiVpa(body);
    if (allowlistedDebit != null) return allowlistedDebit;

    final to = RegExp(
      r'(?:to|at|trf to)\s+([A-Za-z0-9@._+\-]{3,40})',
      caseSensitive: false,
    ).firstMatch(body);
    if (to != null) {
      final candidate = to.group(1)!.trim();
      if (SmsKeywordLists.isKnownUpiVpa(candidate)) {
        return candidate.toLowerCase();
      }
      return _titleCase(candidate);
    }

    return 'Payment';
  }

  static String? loanLabelFromBody(String body) {
    final lower = body.toLowerCase();
    // Prefer explicit product wording over personal NACH merchant strings
    // (ISSUE-13). Unknown NACH becomes a generic label — never "HDFC Home Loan
    // EMI" just because the mandate mentions HDFC.
    if (lower.contains('ecs/nach dishonored')) {
      return 'NACH return charges';
    }
    if (lower.contains('home loan') || lower.contains('housing loan')) {
      return 'Home loan EMI';
    }
    if (lower.contains('personal loan')) return 'Personal loan EMI';
    if (lower.contains('car loan')) return 'Car loan EMI';
    if (lower.contains('against your loan ac') ||
        (lower.contains('depositing') && lower.contains('loan ac'))) {
      return 'Loan payment';
    }
    if (RegExp(r'\bnach\b|\becs\b', caseSensitive: false).hasMatch(lower)) {
      return 'NACH debit';
    }
    if (lower.contains('loan ac') || lower.contains('loan a/c')) {
      return 'Loan EMI';
    }
    return null;
  }

  static bool _isNachMerchant(String merchant) {
    final m = merchant.toLowerCase();
    return m.startsWith('nach-') || m.contains('nach-10-');
  }

  static bool _isUnknownMask(String mask) {
    return mask.isEmpty || mask.contains('????');
  }

  static bool lowerContains(String body, String needle) {
    return body.toLowerCase().contains(needle);
  }

  static String _titleCase(String input) {
    if (input.length <= 3) return input.toUpperCase();
    return input.split(' ').map((w) {
      if (w.isEmpty) return w;
      return '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}';
    }).join(' ');
  }
}
