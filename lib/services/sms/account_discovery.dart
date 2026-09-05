/// Discovered financial account from SMS body patterns.
enum AccountKind {
  savings,
  creditCard,
  loan,
}

class DiscoveredAccount {
  const DiscoveredAccount({
    required this.bank,
    required this.mask,
    required this.kind,
    this.ownerName,
    this.accountLabel,
    this.smsHits = 1,
    this.spentTotal = 0,
    this.receivedTotal = 0,
  });

  final String bank;
  final String mask;
  final AccountKind kind;
  /// Name found in SMS (e.g. "Amar Kumar") when present.
  final String? ownerName;
  /// e.g. "Personal Loan", "Home Loan", "Credit Card".
  final String? accountLabel;
  final int smsHits;
  final double spentTotal;
  final double receivedTotal;

  String get key => '${kind.name}|$bank|$mask';

  DiscoveredAccount merge(DiscoveredAccount other) {
    return DiscoveredAccount(
      bank: bank,
      mask: mask,
      kind: kind,
      ownerName: ownerName ?? other.ownerName,
      accountLabel: accountLabel ?? other.accountLabel,
      smsHits: smsHits + other.smsHits,
      spentTotal: spentTotal + other.spentTotal,
      receivedTotal: receivedTotal + other.receivedTotal,
    );
  }
}

/// Extracts savings and credit-card accounts from Indian bank SMS text.
class AccountDiscovery {
  AccountDiscovery._();

  static final _ownerDear = RegExp(
    r'Dear\s+([A-Za-z][A-Za-z .]{1,40}?)[,\s]',
    caseSensitive: false,
  );

  static final _ownerNeft = RegExp(
    r'(?:Limited|Ltd|Company|Corp)-([A-Za-z][A-Za-z ]{2,40})-[A-Z0-9]',
    caseSensitive: false,
  );

  static final _creditCardPatterns = <_CardPattern>[
    _CardPattern(
      RegExp(
        r'(?:SBI|ICICI|Axis|HDFC|Kotak|IDFC(?:\s+FIRST)?|Yes(?:\s+Bank)?|IndusInd|HSBC)\s+(?:Bank\s+)?Credit\s+Card\s+(?:no\.?\s*)?(?:ending\s+)?(?:XX|xx|\*{1,4})?(\d{4})\b',
        caseSensitive: false,
      ),
      bankFromMatch: _bankFromCreditCardPrefix,
    ),
    _CardPattern(
      RegExp(
        r'(?:SBI|ICICI|Axis|HDFC|Kotak|IDFC(?:\s+FIRST)?|Yes(?:\s+Bank)?|IndusInd|HSBC)\s+(?:Bank\s+)?Credit\s+Card\s+ending\s+(\d{4})\b',
        caseSensitive: false,
      ),
      bankFromMatch: _bankFromCreditCardPrefix,
    ),
    // IndusInd: "spent on IndusInd Card XX4821 … Avl Lmt" (card, not savings)
    _CardPattern(
      RegExp(
        r'IndusInd\s+Card\s+(?:XX|xx)?(\d{4})\b',
        caseSensitive: false,
      ),
      bankFromMatch: (_, __, ___) => 'IndusInd',
    ),
    // BOBCARD: "is spent on your BOBCARD ending 1234"
    _CardPattern(
      RegExp(
        r'BOBCARD\s+ending\s+(\d{4})\b',
        caseSensitive: false,
      ),
      bankFromMatch: (_, __, ___) => 'Bank of Baroda',
    ),
    // AU Bank Credit Card: "spent at … on AU Bank Credit Card x1234"
    _CardPattern(
      RegExp(
        r'AU Bank Credit Card\s+x+(\d{4})\b',
        caseSensitive: false,
      ),
      bankFromMatch: (_, __, ___) => 'AU Bank',
    ),
    // Live Axis spend: "Axis Bank Card no. XX8341" (no "Credit" in SMS)
    _CardPattern(
      RegExp(
        r'Axis\s+Bank\s+Card\s+no\.?\s*(?:XX|xx|X)?(\d{4})\b',
        caseSensitive: false,
      ),
      bankFromMatch: (_, __, ___) => 'Axis',
    ),
    // "spent on Axis Bank Card XX8341 at …" / "On HDFC Bank Card 1949"
    // Debit-card "From … Bank Card … BLOCK DC" is handled as savings first.
    _CardPattern(
      RegExp(
        r'(?:SBI|ICICI|Axis|HDFC|Kotak)\s+Bank\s+Card\s+(?:XX|xx|X)?(\d{4})\b',
        caseSensitive: false,
      ),
      bankFromMatch: _bankFromCreditCardPrefix,
    ),
    // HSBC "creditcard xxxxx1234 used at …"
    _CardPattern(
      RegExp(
        r'HSBC\s+credit\s*card\s+[xX*]*(\d{4})\b',
        caseSensitive: false,
      ),
      bankFromMatch: (_, __, ___) => 'HSBC',
    ),
    // Slice CC: "spent on your credit card xx7185 at … - slice"
    _CardPattern(
      RegExp(
        r'spent on your credit card\s*(?:xx|XX|X{2,}|\*+)?(\d{3,4})\b',
        caseSensitive: false,
      ),
      bankFromMatch: _bankFromSliceCard,
    ),
    _CardPattern(
      RegExp(
        r'Credit Card\s+(?:no\.?\s*)?(?:[Xx]{1,4})?(\d{4})\b',
        caseSensitive: false,
      ),
      bankFromMatch: _bankFromSenderOrBody,
    ),
    _CardPattern(
      RegExp(
        r'card ending with\s+(?:XX|xx|\*{1,4})?(\d{4})\b',
        caseSensitive: false,
      ),
      bankFromMatch: _bankFromSenderOrBody,
    ),
    _CardPattern(
      RegExp(
        r'(?:FIRST|Power Plus|Flipkart|Airtel|Visa|RuPay|Mastercard|Master|Amex)\s+(?:\w+\s+)*(?:Bank\s+)?Credit Card\s+(?:XX|xx|X)?(\d{4})\b',
        caseSensitive: false,
      ),
      bankFromMatch: _bankFromSenderOrBody,
    ),
    _CardPattern(
      RegExp(
        r'Credit\s+Card\s+ending\s+(?:XX|xx|\*{1,4})?(\d{4})\b',
        caseSensitive: false,
      ),
      bankFromMatch: _bankFromSenderOrBody,
    ),
    _CardPattern(
      RegExp(
        r'credited\s+to\s+your\s+(?:\w+\s+)*(?:Bank\s+)?Credit Card\s+(?:XX|xx|X)?(\d{4})\b',
        caseSensitive: false,
      ),
      bankFromMatch: _bankFromSenderOrBody,
    ),
    _CardPattern(
      RegExp(
        r'credited\s+to\s+your\s+card\s+ending\s+(\d{4})\b',
        caseSensitive: false,
      ),
      bankFromMatch: _bankFromSenderOrBody,
    ),
    _CardPattern(
      RegExp(
        r'(?:payment|paid)\s+of\s+(?:INR|Rs\.?).*Credit\s+Card\s+(?:no\.?\s*)?(?:XX|xx|X)?(\d{4})\b',
        caseSensitive: false,
      ),
      bankFromMatch: _bankFromSenderOrBody,
    ),
    _CardPattern(
      RegExp(
        r'card\s+ending\s+(?:XX|xx|\*{1,4})?(\d{4})\b',
        caseSensitive: false,
      ),
      bankFromMatch: _bankFromSenderOrBody,
    ),
    _CardPattern(
      RegExp(
        r'(?:YES BANK|Yes Bank)\s+Card\s+(?:XX|xx|X)?(\d{4})\b',
        caseSensitive: false,
      ),
      bankFromMatch: (_, __, ___) => 'Yes Bank',
    ),
    _CardPattern(
      RegExp(
        r'Payment of Credit Card\s+X?(\d{4})\b',
        caseSensitive: false,
      ),
      bankFromMatch: _bankFromSenderOrBody,
    ),
    _CardPattern(
      RegExp(
        r'Credit Card\s+X(\d{4})\b',
        caseSensitive: false,
      ),
      bankFromMatch: _bankFromSenderOrBody,
    ),
  ];

  static final _savingsPatterns = <_CardPattern>[
    // Slice SFB: "sent from a/c xx0856" / "received in a/c XXX856" / "slice A/c xx0856"
    // Trailing digits may be 3 or 4; pad short tails (856 → 0856) via last4FromLongMask.
    _CardPattern(
      RegExp(
        r'(?:sent from|received in|from)\s+(?:slice\s+)?a/c\s*(?:xx|XX|X{2,}|\*+)?(\d{3,4})\b',
        caseSensitive: false,
      ),
      bankFromMatch: _bankFromSliceSavings,
      kind: AccountKind.savings,
      last4FromLongMask: true,
    ),
    _CardPattern(
      RegExp(
        r'received in slice\s+A/c\s*(?:xx|XX|X{2,}|\*+)?(\d{3,4})\b',
        caseSensitive: false,
      ),
      bankFromMatch: (_, __, ___) => 'Slice',
      kind: AccountKind.savings,
      last4FromLongMask: true,
    ),
    // HSBC India: "A/c 074-260***-006" / "paid from your A/c …" / "is credited with"
    _CardPattern(
      RegExp(
        r'(?:your\s+)?(?:A/?c|account)\s+([\d][\d\-*\s]{3,24}\d)\b',
        caseSensitive: false,
      ),
      bankFromMatch: _bankFromHsbcAcMask,
      kind: AccountKind.savings,
      last4FromLongMask: true,
    ),
    // HDFC/SBI debit card BBPS: "Spent Rs.X From HDFC Bank Card x3569 … BLOCK DC" / Bal Rs
    // Must win over the CC "Bank Card" pattern so debit-card last-4 stay savings.
    _CardPattern(
      RegExp(
        r'From\s+(?:HDFC|SBI|ICICI|Axis|Kotak)\s+Bank\s+Card\s+[xX*]*(\d{4})\b.*(?:\bBLOCK\s+DC\b|\bBal\s+Rs)',
        caseSensitive: false,
      ),
      bankFromMatch: _bankFromSavingsMatch,
      kind: AccountKind.savings,
    ),
    _CardPattern(
      RegExp(
        r'(?:spent on|spent via).{0,60}(?:HDFC|SBI|ICICI|Axis|Kotak)\s+Bank\s+Card\s+[xX*]*(\d{4})\b.*\bBLOCK\s+DC\b',
        caseSensitive: false,
      ),
      bankFromMatch: _bankFromSavingsMatch,
      kind: AccountKind.savings,
    ),
    _CardPattern(
      RegExp(
        r'(?:HDFC|SBI|ICICI|Axis|Kotak)\s+BANK\s+Debit Card\s+[xX*]*(\d{4})\b',
        caseSensitive: false,
      ),
      bankFromMatch: _bankFromSavingsMatch,
      kind: AccountKind.savings,
    ),
    _CardPattern(
      RegExp(
        r'Savings Account\s+[Xx*•]+(\d{4})\b',
        caseSensitive: false,
      ),
      bankFromMatch: _bankFromSenderOrBody,
      kind: AccountKind.savings,
    ),
    _CardPattern(
      RegExp(
        r'(?:deposited|debited|credited)\s+(?:in|to|from)\s+(?:HDFC|SBI|ICICI|Axis|Kotak|IDFC(?:\s+FIRST)?|Yes(?:\s+Bank)?|IndusInd|HSBC)\s+Bank\s+(?:A/?c|Acct)\s*(?:XX|xx|\*{1,4})?(\d{4})\b',
        caseSensitive: false,
      ),
      bankFromMatch: _bankFromSavingsMatch,
      kind: AccountKind.savings,
    ),
    _CardPattern(
      RegExp(
        r'(?:HDFC|SBI|ICICI|Axis|Kotak|IDFC(?:\s+FIRST)?|HSBC)\s+Bank\s+(?:A/?c|Acct)\s*(?:XX|xx|\*{1,4})?(\d{4})\b',
        caseSensitive: false,
      ),
      bankFromMatch: _bankFromSavingsMatch,
      kind: AccountKind.savings,
    ),
    _CardPattern(
      RegExp(
        r'(?:your\s+)?account\s+X+(\d{4})\s+has been credited',
        caseSensitive: false,
      ),
      bankFromMatch: _bankFromSenderOrBody,
      kind: AccountKind.savings,
    ),
    _CardPattern(
      RegExp(
        r'linked\s+Account\s+(?:XX|xx)?(\d{4})\b',
        caseSensitive: false,
      ),
      bankFromMatch: _bankFromSenderOrBody,
      kind: AccountKind.savings,
    ),
    _CardPattern(
      RegExp(
        r'(?:Savings|CURRENT)\s+(?:A/?c|Acct|Account)\s*[Xx*•]*(\d{4})\b',
        caseSensitive: false,
      ),
      bankFromMatch: _bankFromSenderOrBody,
      kind: AccountKind.savings,
    ),
    // "in/on/to your [Bank] [Savings] A/c|Account XX1234" — the account is the
    // user's OWN (never a counterparty, which is worded "to A/c 1234" with no
    // "your"). Covers balance-only / interest / informational savings SMS that
    // never parse as a transaction (e.g. Federal Bank via Fi/Jupiter, PNB,
    // IDFC), so a savings account known only from such SMS still surfaces.
    // The negative lookbehind keeps loan/card accounts out of savings.
    _CardPattern(
      RegExp(
        r'(?:in|on|to)\s+your\s+(?:\w+\s+){0,4}?(?<!loan )(?<!card )(?<!credit )'
        r'(?:A/?c|Acct|Account)\s*(?:No\.?\s*)?[Xx*•]+\d*?(\d{4})\b',
        caseSensitive: false,
      ),
      // Sender-first: the account belongs to the sending bank, not a NACH
      // beneficiary (e.g. "HDFC BANK LIMITED") mentioned in the body.
      bankFromMatch: _bankFromAccountDebitSms,
      kind: AccountKind.savings,
    ),
    // "A/c XX1234 credited/debited with Rs …" — the account is the subject of
    // the money movement (PNB "Ac XXXXXXXX00134720 Credited with Rs …",
    // "A/c XXXX4720 debited with Rs …"). Not a counterparty ("to A/c 1234 (UPI
    // Ref…)") because those are never followed by "credited/debited with".
    _CardPattern(
      RegExp(
        r'\b(?:A/?c|Ac|Acct|Account)\s*(?:No\.?\s*)?[Xx*•]+\d*?(\d{4})\s+'
        r'(?:credited|debited)\s+with\b',
        caseSensitive: false,
      ),
      bankFromMatch: _bankFromAccountDebitSms,
      kind: AccountKind.savings,
    ),
    _CardPattern(
      RegExp(
        r'(?:your\s+)?Account\s+[Xx*•]+(\d{4,})\b',
        caseSensitive: false,
      ),
      bankFromMatch: _bankFromAccountDebitSms,
      kind: AccountKind.savings,
      last4FromLongMask: true,
    ),
    _CardPattern(
      RegExp(
        r'Your A/C\s+[Xx*•]+(\d{4,})\s+has a credit',
        caseSensitive: false,
      ),
      bankFromMatch: _bankFromSenderOrBody,
      kind: AccountKind.savings,
      last4FromLongMask: true,
    ),
    _CardPattern(
      RegExp(
        r'Kotak Bank\s+(?:A/?c|AC)\s+X?(\d{4,})\b',
        caseSensitive: false,
      ),
      bankFromMatch: (_, __, ___) => 'Kotak',
      kind: AccountKind.savings,
      last4FromLongMask: true,
    ),
    // Canara: "Acct XXX5510 Dr.|Cr. INR …"
    _CardPattern(
      RegExp(
        r'Acct\s+X+(\d{4,})\s+(?:Dr|Cr)\.?\s+(?:INR|Rs\.?|₹)',
        caseSensitive: false,
      ),
      bankFromMatch: _bankFromCanaraAcct,
      kind: AccountKind.savings,
      last4FromLongMask: true,
    ),
    // Union Bank: "A/c *7788 Debited|Credited for Rs:"
    _CardPattern(
      RegExp(
        r'A/?c\s*\*?(\d{4})\s+(?:Debited|Credited)\s+for\s+Rs:?',
        caseSensitive: false,
      ),
      bankFromMatch: _bankFromUnionOrSender,
      kind: AccountKind.savings,
    ),
    // Bank of India: "debited A/cXX5468 and credited to"
    _CardPattern(
      RegExp(
        r'debited\s+A/?c\s*(?:XX|xx)?(\d{4})\s+and credited to',
        caseSensitive: false,
      ),
      bankFromMatch: _bankFromBoiOrSender,
      kind: AccountKind.savings,
    ),
    // Bank of India: "Credited in your Ac XX5468"
    _CardPattern(
      RegExp(
        r'Credited in your Ac\s*(?:XX|xx)?(\d{4})\b',
        caseSensitive: false,
      ),
      bankFromMatch: _bankFromBoiOrSender,
      kind: AccountKind.savings,
    ),
    // Bank of Baroda: "Dr.|Cr. from|to A/c XX7788"
    _CardPattern(
      RegExp(
        r'(?:Dr|Cr)\.?\s+(?:from|to)\s+A/?c\s*(?:XX|xx|\*+)?(\d{4})\b',
        caseSensitive: false,
      ),
      bankFromMatch: _bankFromBobOrSender,
      kind: AccountKind.savings,
    ),
    // Bandhan: "debited from|deposited to A/c XXXXXXXXXX1234"
    _CardPattern(
      RegExp(
        r'(?:debited from|deposited to)\s+A/?c\s*X+(\d{4,})',
        caseSensitive: false,
      ),
      bankFromMatch: _bankFromBandhanOrSender,
      kind: AccountKind.savings,
      last4FromLongMask: true,
    ),
    // AU Bank: "Debited|Dr|Cr … A/c X7013"
    _CardPattern(
      RegExp(
        r'(?:Debited|Dr\.?|Cr\.?)\s+(?:INR|Rs\.?)?.{0,40}?A/?c\s*X?(\d{4})\b',
        caseSensitive: false,
      ),
      bankFromMatch: _bankFromAuOrSender,
      kind: AccountKind.savings,
    ),
    // Equitas: "from|to Equitas A/c 1234"
    _CardPattern(
      RegExp(
        r'Equitas A/?c\s*(\d{4})\b',
        caseSensitive: false,
      ),
      bankFromMatch: (_, __, ___) => 'Equitas',
      kind: AccountKind.savings,
    ),
    // IDBI: "IDBI Bank Acct XX1234"
    _CardPattern(
      RegExp(
        r'IDBI Bank Acct\s*(?:XX|xx)?(\d{4})\b',
        caseSensitive: false,
      ),
      bankFromMatch: (_, __, ___) => 'IDBI',
      kind: AccountKind.savings,
    ),
    // South Indian Bank: "Your A/c X7377 is credited" / "UPI debit … A/c X7477"
    _CardPattern(
      RegExp(
        r'(?:Your\s+)?A/?c\s*X+(\d{4})\b.{0,40}?(?:credited with|DEBIT:|UPI)',
        caseSensitive: false,
      ),
      bankFromMatch: _bankFromSibOrSender,
      kind: AccountKind.savings,
    ),
    // Central Bank: "credited to your A/c xxxxxx1234"
    _CardPattern(
      RegExp(
        r'(?:credited to|debited from)\s+your\s+A/?c\s*x+(\d{4})\b',
        caseSensitive: false,
      ),
      bankFromMatch: _bankFromCentralOrSender,
      kind: AccountKind.savings,
      last4FromLongMask: true,
    ),
    // IPPB: "A/C X4321" — require slash so "Card x1234" is not stolen.
    _CardPattern(
      RegExp(
        r'A/C\s*X+(\d{4})\b',
        caseSensitive: false,
      ),
      bankFromMatch: _bankFromIppbOrSender,
      kind: AccountKind.savings,
    ),
    // Karnataka Bank: "Your Account x001234x has been DEBITED"
    _CardPattern(
      RegExp(
        r'Your Account\s+x0*(\d{4})x?\s+has been DEBITED',
        caseSensitive: false,
      ),
      bankFromMatch: (_, __, ___) => 'Karnataka Bank',
      kind: AccountKind.savings,
    ),
  ];

  static final _loanPatterns = <_CardPattern>[
    _CardPattern(
      RegExp(
        r'EMI (?:of|Reminder:).*Loan\s+A/?c\s*(\d{4,})\b',
        caseSensitive: false,
      ),
      bankFromMatch: _bankFromSavingsMatch,
      kind: AccountKind.loan,
    ),
    _CardPattern(
      RegExp(
        r'EMI of Rs\.?\s*\d+(?:,\d+)*(?:\.\d{1,2})?\s+for\s+(?:ICICI Bank\s+)?(?:Personal Loan|Home Loan|Car Loan|Housing Loan)\s+(?:XX|xx)?(\d{4})\b',
        caseSensitive: false,
      ),
      bankFromMatch: _bankFromSenderOrBody,
      kind: AccountKind.loan,
    ),
    _CardPattern(
      RegExp(
        r'(?:Personal Loan|Home Loan|Car Loan|Housing Loan)\s+(?:XX|xx)?(\d{4})\b',
        caseSensitive: false,
      ),
      bankFromMatch: _bankFromSenderOrBody,
      kind: AccountKind.loan,
    ),
    _CardPattern(
      RegExp(
        r'(?:HDFC|SBI|ICICI|Axis|Kotak|IDFC(?:\s+FIRST)?|PNB)\s+Bank\s+Loan\s+A/?c\s*(\d{4,})\b',
        caseSensitive: false,
      ),
      bankFromMatch: _bankFromSavingsMatch,
      kind: AccountKind.loan,
    ),
    // PNB / generic: "against Loan Ac XX0310" / "Loan Ac XX0310"
    _CardPattern(
      RegExp(
        r'Loan\s+A/?c\s*(?:XX|xx|X{2,})?(\d{4})\b',
        caseSensitive: false,
      ),
      bankFromMatch: _bankFromSenderOrBody,
      kind: AccountKind.loan,
    ),
  ];

  static bool _bodyLooksLikeLoan(String body) {
    return RegExp(
      r'\b(emi|loan\s+a/?c|personal\s+loan|home\s+loan|housing\s+loan|car\s+loan|loan\s+instal)\b',
      caseSensitive: false,
    ).hasMatch(body);
  }

  static final _amount = RegExp(
    r'(?:INR|Rs\.?|₹)\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)',
    caseSensitive: false,
  );

  static DiscoveredAccount? _matchPatterns({
    required List<_CardPattern> patterns,
    required String sender,
    required String normalized,
    required String? owner,
    required double? amount,
    required bool isCredit,
    required bool isDebit,
    required AccountKind forceKind,
  }) {
    for (final pattern in patterns) {
      final match = pattern.regex.firstMatch(normalized);
      if (match == null) continue;
      final raw = match.group(1);
      if (raw == null) continue;
      final last4 = pattern.last4FromLongMask
          ? _last4FromMatch(raw, true)
          : (raw.length > 4 ? raw.substring(raw.length - 4) : raw);
      if (last4 == null || !_isValidLast4(last4)) continue;
      final bank = pattern.bankFromMatch(sender, normalized, match);
      if (bank == null) continue;
      return DiscoveredAccount(
        bank: bank,
        mask: '••••$last4',
        kind: forceKind,
        ownerName: owner,
        accountLabel: forceKind == AccountKind.loan
            ? _loanLabel(normalized)
            : forceKind == AccountKind.creditCard
                ? 'Credit Card'
                : null,
        spentTotal: isDebit && amount != null ? amount : 0,
        receivedTotal: isCredit && amount != null ? amount : 0,
      );
    }
    return null;
  }

  static String _loanLabel(String body) {
    final lower = body.toLowerCase();
    if (lower.contains('home loan') || lower.contains('housing loan')) {
      return 'Home Loan';
    }
    if (lower.contains('personal loan')) return 'Personal Loan';
    if (lower.contains('car loan')) return 'Car Loan';
    return 'Loan';
  }

  /// Returns a discovered account or null when SMS is not account-identifying.
  static DiscoveredAccount? discover({
    required String sender,
    required String body,
  }) {
    final normalized = body.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.length < 20) return null;
    if (_isPromo(normalized)) return null;

    final owner = _extractOwnerName(normalized);
    final amount = _extractAmount(normalized);
    final isCredit = RegExp(
      r'\b(?:credited|deposited|received)\b',
      caseSensitive: false,
    ).hasMatch(normalized);
    final isDebit = RegExp(
      r'\b(?:debited|spent|paid|purchase)\b',
      caseSensitive: false,
    ).hasMatch(normalized);

    // Loan product SMS often also mention a linked savings A/c — try loan
    // patterns first so Personal Loan XX1041 is not swallowed as savings XX3649.
    if (_bodyLooksLikeLoan(normalized)) {
      final loan = _matchPatterns(
        patterns: _loanPatterns,
        sender: sender,
        normalized: normalized,
        owner: owner,
        amount: amount,
        isCredit: isCredit,
        isDebit: isDebit,
        forceKind: AccountKind.loan,
      );
      if (loan != null) return loan;
    }

    final savings = _matchPatterns(
      patterns: _savingsPatterns,
      sender: sender,
      normalized: normalized,
      owner: owner,
      amount: amount,
      isCredit: isCredit,
      isDebit: isDebit,
      forceKind: AccountKind.savings,
    );
    // Prefer credit-card discovery when the SMS clearly names a card product,
    // so savings-shaped A/c masks do not swallow "AU Bank Credit Card x1234".
    final looksLikeCard = RegExp(
      r'credit\s*card|bobcard|indusind\s+card|avl\s+lmt',
      caseSensitive: false,
    ).hasMatch(normalized);
    if (savings != null && !looksLikeCard) return savings;

    final cc = _matchPatterns(
      patterns: _creditCardPatterns,
      sender: sender,
      normalized: normalized,
      owner: owner,
      amount: amount,
      isCredit: isCredit,
      isDebit: isDebit,
      forceKind: AccountKind.creditCard,
    );
    if (cc != null) return cc;
    if (savings != null) return savings;

    return _matchPatterns(
      patterns: _loanPatterns,
      sender: sender,
      normalized: normalized,
      owner: owner,
      amount: amount,
      isCredit: isCredit,
      isDebit: isDebit,
      forceKind: AccountKind.loan,
    );
  }

  static bool ownerMatchesProfile(String? ownerName, String profileName) {
    if (profileName.trim().isEmpty) return true;
    if (ownerName == null || ownerName.trim().isEmpty) return true;

    final profile = _normalizePersonName(profileName);
    final owner = _normalizePersonName(ownerName);
    if (profile.isEmpty || owner.isEmpty) return true;

    if (owner.contains(profile) || profile.contains(owner)) return true;

    final profileParts =
        profile.split(' ').where((p) => p.length >= 3).toList();
    final ownerParts = owner.split(' ').where((p) => p.length >= 3).toList();
    for (final pp in profileParts) {
      for (final op in ownerParts) {
        if (pp == op) return true;
      }
    }
    return false;
  }

  static bool ownerConflictsWithProfile(String? ownerName, String profileName) {
    if (profileName.trim().isEmpty) return false;
    if (ownerName == null || ownerName.trim().isEmpty) return false;
    return !ownerMatchesProfile(ownerName, profileName);
  }

  static String? _extractOwnerName(String body) {
    final dear = _ownerDear.firstMatch(body);
    if (dear != null) {
      final name = dear.group(1)?.trim();
      if (name != null && name.length >= 3 && !_isGenericSalutation(name)) {
        return _titleCase(name);
      }
    }
    final neft = _ownerNeft.firstMatch(body);
    if (neft != null) {
      return _titleCase(neft.group(1)!.trim());
    }
    return null;
  }

  static bool _isGenericSalutation(String name) {
    final lower = name.toLowerCase();
    return lower == 'customer' ||
        lower == 'user' ||
        lower == 'cardmember' ||
        lower.startsWith('upi ');
  }

  static double? _extractAmount(String body) {
    final match = _amount.firstMatch(body);
    if (match == null) return null;
    return double.tryParse(match.group(1)!.replaceAll(',', ''));
  }

  static String? _last4FromMatch(String? raw, bool fromLongMask) {
    if (raw == null || raw.isEmpty) return null;
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    if (digits.length >= 4) {
      return digits.substring(digits.length - 4);
    }
    if (fromLongMask) return digits.padLeft(4, '0');
    if (RegExp(r'^\d{4}$').hasMatch(raw)) return raw;
    return null;
  }

  static bool _isValidLast4(String last4) {
    if (!RegExp(r'^\d{4}$').hasMatch(last4)) return false;
    final n = int.tryParse(last4);
    if (n != null && n >= 2015 && n <= 2035) return false;
    return true;
  }

  static bool _isPromo(String body) {
    if (RegExp(r'\bemi of rs', caseSensitive: false).hasMatch(body)) {
      return false;
    }
    return RegExp(
      r'(pre[- ]?approved|apply now|click here|loan offer|credit card offer|'
      r'eligible for(?: a)? loan|limited period|t&c apply|get up to \d+ days|'
      r'visit smsp\.in|give a missed call)',
      caseSensitive: false,
    ).hasMatch(body);
  }

  /// Slice CC alerts end with " - slice" or come from SLCEIT/SLCBNK senders.
  static String? _bankFromSliceCard(
    String sender,
    String body,
    RegExpMatch match,
  ) {
    final haystack = '${sender.toUpperCase()} ${body.toLowerCase()}';
    if (haystack.contains('SLCEIT') ||
        haystack.contains('SLCBNK') ||
        haystack.contains('SLICE') ||
        RegExp(r'\bslice\b').hasMatch(body.toLowerCase())) {
      return 'Slice';
    }
    return null;
  }

  static String? _bankFromSliceSavings(
    String sender,
    String body,
    RegExpMatch match,
  ) {
    return _bankFromSliceCard(sender, body, match);
  }

  static String? _bankFromCreditCardPrefix(
    String sender,
    String body,
    RegExpMatch match,
  ) {
    final prefix = match.group(0)!.toLowerCase();
    if (prefix.contains('sbi')) return 'SBI';
    if (prefix.contains('icici')) return 'ICICI';
    if (prefix.contains('axis')) return 'Axis';
    if (prefix.contains('hdfc')) return 'HDFC';
    if (prefix.contains('kotak')) return 'Kotak';
    if (prefix.contains('idfc')) return 'IDFC';
    if (prefix.contains('yes')) return 'Yes Bank';
    if (prefix.contains('indus')) return 'IndusInd';
    if (prefix.contains('hsbc')) return 'HSBC';
    return _bankFromSenderOrBody(sender, body, match);
  }

  static String? _bankFromSavingsMatch(
    String sender,
    String body,
    RegExpMatch match,
  ) {
    final snippet = match.group(0)!.toLowerCase();
    if (snippet.contains('hdfc')) return 'HDFC';
    if (snippet.contains('sbi')) return 'SBI';
    if (snippet.contains('icici')) return 'ICICI';
    if (snippet.contains('axis')) return 'Axis';
    if (snippet.contains('kotak')) return 'Kotak';
    if (snippet.contains('idfc')) return 'IDFC';
    if (snippet.contains('yes')) return 'Yes Bank';
    if (snippet.contains('indus')) return 'IndusInd';
    if (snippet.contains('pnb')) return 'PNB';
    if (snippet.contains('federal')) return 'Federal';
    if (snippet.contains('hsbc')) return 'HSBC';
    return _bankFromSenderOrBody(sender, body, match);
  }

  /// HSBC hyphen/star masks like `074-260***-006` — only attribute when sender/body
  /// clearly says HSBC (avoid stealing unrelated A/c masks).
  static String? _bankFromHsbcAcMask(
    String sender,
    String body,
    RegExpMatch match,
  ) {
    final haystack = '${sender.toUpperCase()} ${body.toLowerCase()}';
    if (haystack.contains('HSBC') || haystack.contains('hsbc')) return 'HSBC';
    return null;
  }

  static String? _bankFromCanaraAcct(
    String sender,
    String body,
    RegExpMatch match,
  ) {
    final haystack = '${sender.toUpperCase()} ${body.toLowerCase()}';
    if (haystack.contains('CANBNK') ||
        haystack.contains('CANARA') ||
        haystack.contains('canarabank') ||
        haystack.contains('canara bank')) {
      return 'Canara';
    }
    return _bankFromSenderOrBody(sender, body, match);
  }

  static String? _bankFromUnionOrSender(
    String sender,
    String body,
    RegExpMatch match,
  ) {
    final haystack = '${sender.toUpperCase()} ${body.toLowerCase()}';
    if (haystack.contains('UNIONB') || haystack.contains('union bank')) {
      return 'Union Bank';
    }
    return _bankFromSenderOrBody(sender, body, match);
  }

  static String? _bankFromBoiOrSender(
    String sender,
    String body,
    RegExpMatch match,
  ) {
    final haystack = '${sender.toUpperCase()} ${body.toLowerCase()}';
    if (haystack.contains('BOIIND') ||
        haystack.contains('BOIBNK') ||
        haystack.contains('bank of india') ||
        RegExp(r'\s-boi\s*$').hasMatch(body.toLowerCase().trim())) {
      return 'Bank of India';
    }
    return _bankFromSenderOrBody(sender, body, match);
  }

  static String? _bankFromBobOrSender(
    String sender,
    String body,
    RegExpMatch match,
  ) {
    final haystack = '${sender.toUpperCase()} ${body.toLowerCase()}';
    if (haystack.contains('BOBSMS') ||
        haystack.contains('BOBTXN') ||
        haystack.contains('BOBCRD') ||
        haystack.contains('BARODA') ||
        haystack.contains('bobcard') ||
        haystack.contains('bank of baroda')) {
      return 'Bank of Baroda';
    }
    return _bankFromSenderOrBody(sender, body, match);
  }

  static String? _bankFromBandhanOrSender(
    String sender,
    String body,
    RegExpMatch match,
  ) {
    final haystack = '${sender.toUpperCase()} ${body.toLowerCase()}';
    if (haystack.contains('BDNSMS') ||
        haystack.contains('BNDNBK') ||
        haystack.contains('BANDHAN') ||
        haystack.contains('bandhan')) {
      return 'Bandhan';
    }
    return _bankFromSenderOrBody(sender, body, match);
  }

  static String? _bankFromAuOrSender(
    String sender,
    String body,
    RegExpMatch match,
  ) {
    final haystack = '${sender.toUpperCase()} ${body.toLowerCase()}';
    if (haystack.contains('AUBANK') ||
        haystack.contains('AUBSMS') ||
        haystack.contains('au bank')) {
      return 'AU Bank';
    }
    return _bankFromSenderOrBody(sender, body, match);
  }

  static String? _bankFromSibOrSender(
    String sender,
    String body,
    RegExpMatch match,
  ) {
    final haystack = '${sender.toUpperCase()} ${body.toLowerCase()}';
    if (haystack.contains('SIBSMS') ||
        haystack.contains('SIBBANK') ||
        haystack.contains('south indian bank')) {
      return 'South Indian Bank';
    }
    return _bankFromSenderOrBody(sender, body, match);
  }

  static String? _bankFromCentralOrSender(
    String sender,
    String body,
    RegExpMatch match,
  ) {
    final haystack = '${sender.toUpperCase()} ${body.toLowerCase()}';
    if (haystack.contains('CENTBK') ||
        haystack.contains('CBOI') ||
        haystack.contains('central bank') ||
        RegExp(r'-cboi\s*$').hasMatch(body.toLowerCase().trim())) {
      return 'Central Bank';
    }
    return _bankFromSenderOrBody(sender, body, match);
  }

  static String? _bankFromIppbOrSender(
    String sender,
    String body,
    RegExpMatch match,
  ) {
    final haystack = '${sender.toUpperCase()} ${body.toLowerCase()}';
    if (haystack.contains('IPBMSG') ||
        haystack.contains('MYIPPB') ||
        haystack.contains('IPPB') ||
        haystack.contains('ippb') ||
        haystack.contains('thru ippb')) {
      return 'IPPB';
    }
    return null;
  }

  static String? _bankFromAccountDebitSms(
    String sender,
    String body,
    RegExpMatch match,
  ) {
    final upper = sender.toUpperCase();
    if (upper.contains('KOTAK')) return 'Kotak';
    if (upper.contains('HDFC')) return 'HDFC';
    // SIBSMS before SBI (header substring collision).
    if (upper.contains('SIBSMS') || upper.contains('SIBBANK')) {
      return 'South Indian Bank';
    }
    if (upper.contains('SBI') || upper.contains('SBIN')) return 'SBI';
    if (upper.contains('ICICI')) return 'ICICI';
    if (upper.contains('AXIS')) return 'Axis';
    if (upper.contains('IDFC')) return 'IDFC';
    if (upper.contains('PNB')) return 'PNB';
    if (upper.contains('CANBNK') || upper.contains('CANARA')) return 'Canara';
    if (upper.contains('BOBSMS') ||
        upper.contains('BOBTXN') ||
        upper.contains('BOBCRD') ||
        upper.contains('BARODA')) {
      return 'Bank of Baroda';
    }
    if (upper.contains('UNIONB')) return 'Union Bank';
    if (upper.contains('BOIIND') || upper.contains('BOIBNK')) {
      return 'Bank of India';
    }
    // IndusInd before Indian Bank (INDBNK).
    if (upper.contains('INDUSB') || upper.contains('INDUS')) return 'IndusInd';
    if (upper.contains('INDBNK')) return 'Indian Bank';
    if (upper.contains('BDNSMS') ||
        upper.contains('BNDNBK') ||
        upper.contains('BANDHAN')) {
      return 'Bandhan';
    }
    if (upper.contains('IDBIBK') || upper.contains('IDBI')) return 'IDBI';
    if (upper.contains('AUBANK') || upper.contains('AUBSMS')) return 'AU Bank';
    if (upper.contains('EQUTAS') ||
        upper.contains('EQUITA') ||
        upper.contains('EQUITAS')) {
      return 'Equitas';
    }
    if (upper.contains('IPBMSG') || upper.contains('MYIPPB')) return 'IPPB';
    if (upper.contains('CENTBK') || upper.contains('CBOI')) {
      return 'Central Bank';
    }
    if (upper.contains('KBLBNK') ||
        upper.contains('KTKBANK') ||
        upper.contains('KARBANK')) {
      return 'Karnataka Bank';
    }
    if (upper.contains('FED') || upper.contains('MYJPTR')) return 'Federal';
    if (upper.contains('HSBC')) return 'HSBC';
    if (upper.contains('SLCEIT') ||
        upper.contains('SLCBNK') ||
        upper.contains('SLICE')) {
      return 'Slice';
    }
    if (body.toLowerCase().contains('kotak bank')) return 'Kotak';
    return _bankFromSenderOrBody(sender, body, match);
  }

  static String? _bankFromSenderOrBody(
    String sender,
    String body,
    RegExpMatch match,
  ) {
    final haystack = '${sender.toUpperCase()} ${body.toLowerCase()}';
    // Prefer DLT headers / trailing " - slice" so unrelated "slice" wording
    // in other banks' SMS does not steal the bank.
    if (haystack.contains('SLCEIT') ||
        haystack.contains('SLCBNK') ||
        haystack.contains('SLICE') ||
        RegExp(r'-\s*slice\s*$').hasMatch(body.toLowerCase().trim())) {
      return 'Slice';
    }
    if (haystack.contains('HDFC') || haystack.contains('hdfc')) return 'HDFC';
    if (haystack.contains('SBICRD') ||
        haystack.contains('SBI') ||
        haystack.contains('sbi')) {
      return 'SBI';
    }
    if (haystack.contains('ICICI') || haystack.contains('icici')) return 'ICICI';
    if (haystack.contains('AXIS') || haystack.contains('axis')) return 'Axis';
    if (haystack.contains('KOTAK') || haystack.contains('kotak')) return 'Kotak';
    if (haystack.contains('IDFC') || haystack.contains('idfc')) return 'IDFC';
    if (haystack.contains('YES') || haystack.contains('yes bank')) {
      return 'Yes Bank';
    }
    // IndusInd (INDUSB) before Indian Bank (INDBNK).
    if (haystack.contains('INDUSB') ||
        haystack.contains('INDUS') ||
        haystack.contains('indusind')) {
      return 'IndusInd';
    }
    // South Indian before bare "indian bank".
    if (haystack.contains('SIBSMS') ||
        haystack.contains('SIBBANK') ||
        haystack.contains('south indian bank')) {
      return 'South Indian Bank';
    }
    if (haystack.contains('INDBNK') || haystack.contains('indian bank')) {
      return 'Indian Bank';
    }
    if (haystack.contains('PNB') ||
        haystack.contains('pnb') ||
        haystack.contains('punjab national')) {
      return 'PNB';
    }
    if (haystack.contains('CANBNK') ||
        haystack.contains('CANARA') ||
        haystack.contains('canarabank') ||
        haystack.contains('canara')) {
      return 'Canara';
    }
    if (haystack.contains('BOBSMS') ||
        haystack.contains('BOBTXN') ||
        haystack.contains('BOBCRD') ||
        haystack.contains('BARODA') ||
        haystack.contains('bobcard') ||
        haystack.contains('bank of baroda')) {
      return 'Bank of Baroda';
    }
    if (haystack.contains('UNIONB') || haystack.contains('union bank')) {
      return 'Union Bank';
    }
    if (haystack.contains('BOIIND') ||
        haystack.contains('BOIBNK') ||
        haystack.contains('bank of india') ||
        RegExp(r'\s-boi\s*$').hasMatch(body.toLowerCase().trim())) {
      return 'Bank of India';
    }
    if (haystack.contains('BDNSMS') ||
        haystack.contains('BNDNBK') ||
        haystack.contains('BANDHAN') ||
        haystack.contains('bandhan')) {
      return 'Bandhan';
    }
    if (haystack.contains('IDBIBK') ||
        haystack.contains('IDBI') ||
        haystack.contains('idbi bank')) {
      return 'IDBI';
    }
    if (haystack.contains('AUBANK') ||
        haystack.contains('AUBSMS') ||
        haystack.contains('au bank')) {
      return 'AU Bank';
    }
    if (haystack.contains('EQUTAS') ||
        haystack.contains('EQUITA') ||
        haystack.contains('equitas')) {
      return 'Equitas';
    }
    if (haystack.contains('SIBSMS') ||
        haystack.contains('SIBBANK') ||
        haystack.contains('south indian bank')) {
      return 'South Indian Bank';
    }
    if (haystack.contains('CENTBK') ||
        haystack.contains('CBOI') ||
        haystack.contains('central bank') ||
        RegExp(r'-cboi\s*$').hasMatch(body.toLowerCase().trim())) {
      return 'Central Bank';
    }
    if (haystack.contains('IPBMSG') ||
        haystack.contains('MYIPPB') ||
        haystack.contains('ippb') ||
        haystack.contains('thru ippb')) {
      return 'IPPB';
    }
    if (haystack.contains('KBLBNK') ||
        haystack.contains('KTKBANK') ||
        haystack.contains('KARBANK') ||
        haystack.contains('karnataka bank')) {
      return 'Karnataka Bank';
    }
    // Federal Bank, incl. its neobanks Fi (FedFiB) and Jupiter (MYJPTR) which
    // ride on Federal Bank savings accounts.
    if (haystack.contains('FEDBNK') ||
        haystack.contains('FEDFIB') ||
        haystack.contains('MYJPTR') ||
        haystack.contains('federal bank') ||
        haystack.contains('federal')) {
      return 'Federal';
    }
    if (haystack.contains('HSBC') || haystack.contains('hsbc')) return 'HSBC';
    return null;
  }

  static String _normalizePersonName(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _titleCase(String input) {
    return input.split(' ').map((w) {
      if (w.isEmpty) return w;
      return '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}';
    }).join(' ');
  }
}

class _CardPattern {
  const _CardPattern(
    this.regex, {
    required this.bankFromMatch,
    this.kind = AccountKind.creditCard,
    this.last4FromLongMask = false,
  });

  final RegExp regex;
  final String? Function(String sender, String body, RegExpMatch match)
      bankFromMatch;
  final AccountKind kind;
  final bool last4FromLongMask;
}

/// Merges duplicate discoveries by [DiscoveredAccount.key].
Map<String, DiscoveredAccount> mergeDiscoveries(
  Iterable<DiscoveredAccount> items,
) {
  final merged = <String, DiscoveredAccount>{};
  for (final item in items) {
    final existing = merged[item.key];
    merged[item.key] = existing == null ? item : existing.merge(item);
  }
  return merged;
}
