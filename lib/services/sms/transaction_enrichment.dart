import 'account_discovery.dart';
import 'sms_keyword_lists.dart';
import 'sms_parser.dart';

/// Enriches parsed SMS transactions with account masks, kinds, and labels.
abstract final class TransactionEnrichment {
  static final _creditCardBody = RegExp(
    r'credit\s+card|card ending|card\s+x\d{4}|yes\s+bank\s+card|'
    r'axis bank card|bank card no\.|bobcard|indusind card|avl\s+lmt|ccbp',
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
    // Bare NACH/ACH is not enough (R2-2): SIPs and insurance use the same rail.
    if (looksLikeLoanPayment(lower)) return AccountKind.loan;
    if (looksLikeTransferToDiscoveredLoan(
      body: body,
      discoveries: discoveries,
    )) {
      return AccountKind.loan;
    }
    if (_looksLikeNachMandate(lower)) {
      // Kind only — do not rewrite funding bank/mask onto the loan product.
      if (resolveAssociatedLoanProduct(
            body: body,
            discoveries: discoveries,
          ) !=
          null) {
        return AccountKind.loan;
      }
    }

    // Debit-card / BLOCK DC / CCBBPSNO spends are savings, not credit card
    // (`ccbp` substring in CCBBPSNO used to flip kind via _creditCardBody).
    if (looksLikeDebitCardSpend(lower)) return AccountKind.savings;
    // ICICI CC refund landed in savings: body mentions the card as the source.
    if (RegExp(
      r'refund of .+to savings account .+successfully transferred',
      caseSensitive: false,
    ).hasMatch(lower)) {
      return AccountKind.savings;
    }

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

  /// True when the body transfers toward a last-4 that is a known loan product.
  static bool looksLikeTransferToDiscoveredLoan({
    required String body,
    required Iterable<DiscoveredAccount> discoveries,
  }) {
    final dest = destinationAccountLast4(body.toLowerCase());
    if (dest == null) return false;
    final mask = SmsParser.maskFromLast4(dest);
    return discoveries.any(
      (d) => d.kind == AccountKind.loan && d.mask == mask && d.mask.isNotEmpty,
    );
  }

  /// Shape + richness of HDFC-style debit-card / BBPS spend alerts.
  ///
  /// Lean = `ALERT: … spent via Debit Card` security ping. Drop it when a
  /// richer `Spent … BLOCK DC` sibling exists for the same event.
  static ({bool isTwin, bool isLean}) cardAlertTwinHints(String body) {
    final lower = body.toLowerCase();
    final isLean = RegExp(
          r'alert:\s*rs',
          caseSensitive: false,
        ).hasMatch(lower) &&
        lower.contains('spent via') &&
        lower.contains('debit card');
    return (isTwin: isLean || looksLikeDebitCardSpend(lower), isLean: isLean);
  }

  /// HDFC/SBI debit-card BBPS (BLOCK DC, "Debit Card", CCBBPSNO) must stay
  /// savings — not creditCard. Distinct from funding-side MBK CCBP bill pay.
  static bool looksLikeDebitCardSpend(String lower) {
    if (RegExp(r'\bblock\s+dc\b', caseSensitive: false).hasMatch(lower)) {
      return true;
    }
    if (RegExp(r'\bdebit\s+card\b', caseSensitive: false).hasMatch(lower)) {
      return true;
    }
    if ((lower.contains('ccbbps') ||
            lower.contains('bbpsbill') ||
            lower.contains('dcsi-bbps')) &&
        !lower.contains('credit card')) {
      return true;
    }
    return false;
  }

  static bool looksLikeCreditCardTransaction(String lower) {
    if (looksLikeLoanPayment(lower)) return false;
    if (looksLikeDebitCardSpend(lower)) return false;

    if (lower.contains('ccbp') || lower.contains('mbk ccbp')) return true;

    if (RegExp(
      r'spent on (?:your )?(?:\w+ ){0,4}(?:bank )?(?:\w+ ){0,3}credit card',
      caseSensitive: false,
    ).hasMatch(lower)) {
      return true;
    }
    // Live HSBC: "HSBC creditcard xxxxx3740 used at … for INR …"
    if (RegExp(
      r'credit\s*card\s+[x*\d]+\s+used at',
      caseSensitive: false,
    ).hasMatch(lower)) {
      return true;
    }
    if (RegExp(r'spent on yes bank card', caseSensitive: false).hasMatch(lower)) {
      return true;
    }
    // IndusInd: "spent on IndusInd Card XX… Avl Lmt" (Avl Lmt = card, not savings)
    if (lower.contains('spent on indusind card') ||
        (lower.contains('indusind card') && lower.contains('avl lmt'))) {
      return true;
    }
    // Live Axis: "Spent INR … Axis Bank Card no. XX8341" / "spent on Axis Bank Card"
    if (RegExp(
      r'(?:spent\s+(?:inr|rs\.?)|spent on).{0,40}axis bank card',
      caseSensitive: false,
    ).hasMatch(lower)) {
      return true;
    }
    if (RegExp(r'axis bank card no\.', caseSensitive: false).hasMatch(lower)) {
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
    // HSBC India: "HSBC creditcard xxxxx1234 used at MERCHANT for INR …"
    if (RegExp(
      r'hsbc\s+credit\s*card\s+[x*\d]+\s+used at',
      caseSensitive: false,
    ).hasMatch(lower)) {
      return true;
    }
    if (lower.contains('credited towards your') &&
        lower.contains('credit card')) {
      return true;
    }
    if (lower.contains('reversal') && lower.contains('credit card')) {
      return true;
    }
    if (lower.contains('e-mandate') && lower.contains('credit card')) {
      return true;
    }
    if (lower.contains('debited to') && lower.contains('credit card')) {
      return true;
    }
    if (RegExp(
      r'spent on kotak credit card',
      caseSensitive: false,
    ).hasMatch(lower)) {
      return true;
    }
    // HDFC "Spent Rs.X On HDFC Bank Card 1949 … BLOCK CC" is on-card spend.
    // "From HDFC Bank Card … BLOCK DC" is a debit-card / savings spend.
    if (RegExp(
      r'spent\s+rs\.?.{0,30}on\s+\w+\s+bank\s+card',
      caseSensitive: false,
    ).hasMatch(lower) &&
        !RegExp(r'\bblock\s+dc\b', caseSensitive: false).hasMatch(lower)) {
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

    // CCBP / MBK CCBP is a funding-account debit (pay the card), not activity
    // on the card. Never remap onto a discovered card — keep the funding
    // bank/mask (body last-4 is the funding A/c when present).
    if (lower.contains('ccbp') || lower.contains('credit card bill')) {
      final fundingMask = last4 != null
          ? SmsParser.maskFromLast4(last4)
          : parsedMask;
      return (
        bank: parsedBank,
        mask: fundingMask.isNotEmpty ? fundingMask : parsedMask,
      );
    }

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
      return (bank: 'Bank of Baroda', mask: parsedMask);
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
    // Explicit EMI/product wording only. Bare NACH/ACH is a collection rail
    // shared with SIPs and insurance — those stay savings (R2-2).
    return lower.contains('emi of') ||
        lower.contains('emi due') ||
        lower.contains('emi reminder');
  }

  static bool _looksLikeNachMandate(String lower) {
    return lower.contains('nach-') ||
        lower.contains('towards nach') ||
        lower.contains('tp ach');
  }

  /// True when [bankToken] appears in the NACH/ACH *beneficiary* clause,
  /// not merely as the funding bank ("debited from HDFC Bank A/c").
  static bool _nachBeneficiaryMentionsBank(String lower, String bankToken) {
    final b = bankToken.toLowerCase();
    if (b.isEmpty) return false;
    final escaped = RegExp.escape(b);
    // NACH-10-HDFC / NACH HDFC / NACH-10-TP ACH ICICI
    if (RegExp(
      'nach[\\s-]+(?:\\d+[\\s-]+)?(?:tp\\s*ach\\s+)?$escaped',
      caseSensitive: false,
    ).hasMatch(lower)) {
      return true;
    }
    if (b == 'icici' && lower.contains('tp ach icici')) return true;
    if (b == 'hdfc' &&
        RegExp(
          r'nach[\s-].{0,40}hdfc bank limited',
          caseSensitive: false,
        ).hasMatch(lower)) {
      return true;
    }
    if (b == 'idfc' &&
        RegExp(
          r'nach[\s-].{0,40}idfc first bank',
          caseSensitive: false,
        ).hasMatch(lower)) {
      return true;
    }
    return false;
  }

  /// Display bank/mask for a loan-kind SMS row.
  ///
  /// **Always keeps the funding (debited/credited) identity** — same idea as
  /// CCBP. A Kotak NACH paying an HDFC loan stays `Kotak|fundingMask` for You
  /// listing and balance. Product context comes from
  /// [resolveAssociatedLoanProduct] / merchant text, not from rewriting the
  /// ledger key onto the loan bank.
  static ({String bank, String mask}) resolveLoanDisplay({
    required String body,
    required String parsedBank,
    required String parsedMask,
    required Iterable<DiscoveredAccount> discoveries,
  }) {
    // [body]/[discoveries] kept for call-site API stability; product link is
    // [resolveAssociatedLoanProduct] — never rewrite funding identity here.
    return (bank: parsedBank, mask: parsedMask);
  }

  /// Which discovered loan product a funding EMI/NACH/UPI payment relates to,
  /// without changing the transaction's bank/mask.
  ///
  /// Confidence order:
  /// 1. Explicit loan last-4 in the SMS body
  /// 2. UPI / NEFT destination last-4 → **unique** loan with that mask
  /// 3. Mandate / beneficiary bank hint → **unique** loan at that bank
  /// 4. Ambiguous payee (MBK EMI, bare "EMI") → **unique** loan overall only
  ///
  /// Never guess from the funding bank when multiple loans exist.
  static DiscoveredAccount? resolveAssociatedLoanProduct({
    required String body,
    required Iterable<DiscoveredAccount> discoveries,
  }) {
    final lower = body.toLowerCase();

    String? loanLast4FromBody() {
      final patterns = [
        RegExp(
          r'(?:personal|home|car|housing)\s+loan\s+(?:xx|XX)?(\d{4})\b',
          caseSensitive: false,
        ),
        RegExp(
          r'loan\s+a/?c\s*(?:xx|XX|x{2,})?(\d{4,})\b',
          caseSensitive: false,
        ),
        RegExp(
          r'against\s+(?:your\s+)?loan\s+a/?c\s*(?:xx|XX)?(\d{4})\b',
          caseSensitive: false,
        ),
      ];
      for (final p in patterns) {
        final m = p.firstMatch(body);
        if (m == null) continue;
        final digits = m.group(1)!.replaceAll(RegExp(r'\D'), '');
        if (digits.length < 4) continue;
        return digits.substring(digits.length - 4);
      }
      return null;
    }

    DiscoveredAccount? loanFor(String bankHint) {
      final matches = discoveries
          .where(
            (d) =>
                d.kind == AccountKind.loan &&
                d.mask.isNotEmpty &&
                d.bank.toLowerCase().contains(bankHint),
          )
          .toList();
      if (matches.length != 1) return null;
      return matches.first;
    }

    DiscoveredAccount? uniqueLoan() {
      final loans = discoveries
          .where((d) => d.kind == AccountKind.loan && d.mask.isNotEmpty)
          .toList();
      if (loans.length == 1) return loans.first;
      return null;
    }

    final bodyLast4 = loanLast4FromBody();
    if (bodyLast4 != null) {
      final mask = SmsParser.maskFromLast4(bodyLast4);
      final byMask = discoveries
          .where((d) => d.kind == AccountKind.loan && d.mask == mask)
          .toList();
      if (byMask.isNotEmpty) return byMask.first;
    }

    final destLast4 = destinationAccountLast4(lower);
    if (destLast4 != null) {
      final mask = SmsParser.maskFromLast4(destLast4);
      final byMask = discoveries
          .where((d) => d.kind == AccountKind.loan && d.mask == mask)
          .toList();
      if (byMask.length == 1) return byMask.first;
    }

    if (_nachBeneficiaryMentionsBank(lower, 'hdfc')) {
      final loan = loanFor('hdfc');
      if (loan != null) return loan;
    }
    if (_nachBeneficiaryMentionsBank(lower, 'icici')) {
      final loan = loanFor('icici');
      if (loan != null) return loan;
    }
    if (_nachBeneficiaryMentionsBank(lower, 'idfc')) {
      final loan = loanFor('idfc');
      if (loan != null) return loan;
    }

    if (lower.contains('mbk emi') ||
        RegExp(r'\bemi\b').hasMatch(lower) ||
        lower.contains('loan instal')) {
      return uniqueLoan();
    }

    return null;
  }

  /// Last-4 of a transfer destination when present, e.g. `to a/c **0310`.
  static String? destinationAccountLast4(String lower) {
    final patterns = [
      RegExp(
        r'to\s+(?:a/?c|acct|account)\s*(?:\*{1,}|\•+|x{2,})(\d{4})\b',
        caseSensitive: false,
      ),
      RegExp(
        r'to\s+(?:\*{2,}|\•{2,}|x{2,})(\d{4})\b',
        caseSensitive: false,
      ),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(lower);
      if (m != null) return m.group(1);
    }
    return null;
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
