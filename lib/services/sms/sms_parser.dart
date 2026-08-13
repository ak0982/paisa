import 'account_bank_registry.dart';
import 'bank_promo_filters.dart';
import 'parsed_sms_transaction.dart';
import 'sms_keyword_lists.dart';

/// Regex-based parser for Indian bank / UPI SMS alerts.
class SmsParser {
  SmsParser._();

  /// Indian (1,25,000) and Western (1,250,000) comma grouping.
  /// Decimal part allows 1–2 digits so "Rs 500.5" parses as 500.5 (ISSUE-14).
  static final _amount = r'(\d+(?:,\d+)*(?:\.\d{1,2})?)';
  static final _currency = r'(?:Rs\.?|INR|₹)\s*';
  /// Must be preceded by a/c marker or masked chars (XX**, *5300) — never bare
  /// digits inside amounts like 52000.00.
  static final _account = r'(?:'
      r'(?:a/c|acct|account|A/C)\s*[Xx*•]*'
      r'|'
      r'[Xx*•]{2,}'
      r')(\d{4})\b';

  /// Known financial sender ID fragments (case-insensitive).
  static final bankSenderPatterns = [
    RegExp(r'hdfc', caseSensitive: false),
    RegExp(r'sbi', caseSensitive: false),
    RegExp(r'icici', caseSensitive: false),
    RegExp(r'axis', caseSensitive: false),
    RegExp(r'kotak', caseSensitive: false),
    RegExp(r'paytm', caseSensitive: false),
    RegExp(r'phonepe', caseSensitive: false),
    RegExp(r'gpay|googlepay', caseSensitive: false),
    RegExp(r'mobikwik|mbkwik', caseSensitive: false),
    RegExp(r'freecharge|frchrg', caseSensitive: false),
    RegExp(r'amazonpay|amznpay', caseSensitive: false),
    RegExp(r'bhim', caseSensitive: false),
    RegExp(r'yesbank', caseSensitive: false),
    RegExp(r'indusind', caseSensitive: false),
    RegExp(r'pnb', caseSensitive: false),
    RegExp(r'canara', caseSensitive: false),
    RegExp(r'baroda', caseSensitive: false),
    RegExp(r'federal', caseSensitive: false),
    RegExp(r'idfc', caseSensitive: false),
    RegExp(r'lenden', caseSensitive: false),
    RegExp(r'hsbc', caseSensitive: false),
  ];

  /// Body must look like a transaction alert, not a promo OTP message.
  static final transactionSignals = RegExp(
    r'(debited|credited|spent|paid|received|withdrawn|deposited|depositing|txn|transaction|upi|neft|imps|rtgs|a/c|acct|account|loan ac|bal\s|balance)',
    caseSensitive: false,
  );

  static final _otpOnly = RegExp(
    r'^\s*(?:otp|one time password|verification code|do not share)',
    caseSensitive: false,
  );

  /// Loan offers, card promos, scam alerts, and marketing — not completed transactions.
  static final _promoOfferPattern = RegExp(
    r'(pre[- ]?approved|loan offer|personal loan|instant loan|'
    r'eligible for(?: a)? loan|apply now|click here|limited period|'
    r't&c apply|terms and conditions|sanction letter|loan eligibility|'
    r'avail(?:able)? loan|lakh loan|crore loan|processing fee offer|'
    r'credit card offer|get(?: a)? loan|loan at \d|interest rate starts|'
    r'offer for you|exclusive offer|zero processing|'
    r'loan\s+is\s+approv|loan\s+approved|withdraw\s+direct|zero\s+document|'
    r'to your wallet|wallet a/c|credited to wallet|'
    r'click to check|tap (?:here|to claim|now)|claim now|claim before|'
    r'finance guru|instant disbursal|zero docs|no docs|loan update:|'
    r"kyc needed|tap now|hurry!|offer expires|recharged!|talktime|"
    r"you(?:'ve| have) received rs\.?\s*[\d,]+(?:\.\d{1,2})?\s+(?:cashback|talktime)|"
    r'received rs\.?\s*[\d,]+(?:\.\d{1,2})?\s+loan|'
    r'earns?\s+rs\.?\s*[\d,]+\s+daily|in one place)',
    caseSensitive: false,
  );

  /// Scam SMS often obfuscate keywords (L0AN, Appr0ve).
  static final _scamObfuscationPattern = RegExp(
    r'(l0an|l[o0]an\s+is\s+appr|y0ur\s+received|withdraw\s+t0|'
    r'rs\.?\s*[\d,]+\s+l0an|wallet\s+a/c)',
    caseSensitive: false,
  );

  /// Completed money movement — distinguishes real txns from promos with amounts.
  static final _completedTxnPattern = RegExp(
    r'(debited|debited by|sent\s+rs|paid\s+to|paid\s+at|spent\s+at|withdrawn|deposited|'
    r'neft\s+(?:dr|cr)|imps\s+(?:dr|cr)|rtgs\s+(?:dr|cr)|'
    r'credited\s+to\s+(?:your\s+)?(?:a/c|acct|account)\s*(?:[x*•]{2,8})?\s*\d{4}|'
    r'credited with amount|credit alert!|'
    r'is debited to your account|has a credit by|'
    r'depositing an amount.*loan ac|against your loan ac|'
    r'payment of\s+(?:inr|rs).*(?:credited|received)|'
    r'credited\s+towards\s+your.*credit card|'
    r'received payment of.*bbps.*credit card|'
    r'payment of.*received for your bobcard|'
    r'payment of.*received towards your.*credit card|'
    r'payment of rs.*received towards your credit card ending|'
    r'is spent on your bobcard|'
    r'spent on your (?:\w+ ){0,4}credit card ending|'
    r'(?:delicious purchase|fueled up).*spent on your|'
    r'credited with rs\.?\s*[\d,]+.*(?:on \d|against reversal)|'
    r'deposited in (?:\w+ ){0,3}bank|'
    r'credit card (?:xx)?\d{4} debited for|'
    r'spent using (?:\w+\s+)+bank card|'
    // Live Axis CC: "Spent INR 663\nAxis Bank Card no. XX8341\n…"
    r'spent\s+(?:inr|rs\.?)\s*[\d,]+|'
    r'axis bank card no\.|'
    // Live HSBC India CC: "HSBC creditcard xxxxx3740 used at MERCHANT for INR …"
    r'credit\s*card\s+[x*\d]+\s+used at|'
    r'used at .+ for\s+(?:inr|rs\.?)|'
    r'cashback of\s+(?:inr|rs\.?).+credited to your|'
    r'refund of\s+(?:inr|rs\.?).+credited to|'
    // Slice SFB (live dump SLCEIT / public SLCBNK):
    // "Rs. X sent from a/c xx0856 …" / "received in a/c|slice A/c …" / IMPS
    r'sent from a/c|'
    r'received in (?:slice\s+)?a/c|'
    r'imps payment of\s+(?:inr|rs\.?)|'
    r'successfully paid\s+(?:inr|rs\.?)|'
    r'spent on your credit card\s+(?:xx|x{2,})?\d{3,4}|'
    r'a/c x?\d{4} debited by .*trf to mbk ccbp|'
    r'reversal of .*credited to .*credit card|'
    r'received\s+rs\.?\s*[\d,]+.*in your (?:kotak|hdfc|sbi|icici|axis|bank|a/c|account)|'
    r'spent on yes bank card|'
    r'credited to your\s+\w[\w .&-]{1,40}\s+account|'
    // Schema 33 live inbox: HDFC On/From Bank Card, ICICI cashback,
    // SBI reversal/cashback + e-mandate, CBS SBI, IDFC interest, PNB charges.
    r'cashback credited to .+credit card|'
    r'towards reversal/cashback|'
    r'against e-mandate|'
    r'credited by rs|'
    r'is credited by rs|'
    r'monthly interest of|'
    r'debited with rs\.?\s*[\d,]+.*bank charges|'
    r'thank you for payment of\s+(?:inr|rs)|'
    r'credited:rs|'
    // Live leftovers: HDFC "ALERT: Rs spent via Debit Card" / ICICI CC→savings refund.
    r'spent via|'
    r'refund of\s+(?:inr|rs\.?).+successfully transferred)',
    caseSensitive: false,
  );

  /// True when SMS looks like a loan/card/marketing offer, not a real transaction.
  static bool isPromoOrOfferSms(String body, {String sender = ''}) {
    if (_completedTxnPattern.hasMatch(body)) return false;

    if (_promoOfferPattern.hasMatch(body)) return true;
    if (_scamObfuscationPattern.hasMatch(body.toLowerCase())) return true;

    if (sender.isNotEmpty &&
        BankPromoFilters.matchesBankPromo(sender: sender, body: body)) {
      return true;
    }

    return false;
  }

  static bool isPersonalPhoneSender(String sender) {
    final s = sender.replaceAll(RegExp(r'[\s\-]'), '');
    // Indian mobiles are 10 digits starting 6–9. Scam SMS often omit the +91
    // prefix ("9876543210"); requiring 91 alone let those through the pipeline
    // because production calls parseTransaction after isRealTransactionSms.
    if (RegExp(r'^\+?91[6-9]\d{9}$').hasMatch(s)) return true;
    if (RegExp(r'^0?[6-9]\d{9}$').hasMatch(s)) return true;
    return false;
  }

  /// Strong bank alert verbs — used for trusted senders only.
  static final _bankAlertPattern = RegExp(
    r'(debited|credited|spent\s+on|spent\s+via|spent\s+(?:inr|rs\.?)|paid\s+to|sent\s+rs|'
    r'withdrawn|deposited|depositing|payment of\s+(?:inr|rs)|has a credit by|'
    r'is debited to|received\s+rs\.?\s*[\d,]+.*in your|'
    r'successfully transferred)',
    caseSensitive: false,
  );

  /// True when SMS shows evidence of completed money movement, not an offer.
  static bool hasCompletedTransactionSignal(String body) {
    return _completedTxnPattern.hasMatch(body);
  }

  /// Scam phishing that claims a wallet credit without a completed bank txn.
  /// Real "credited to your <platform> account" alerts are parsed normally.
  static bool isNonBankWalletMovement(String body) {
    final lower = body.toLowerCase();
    // Completed platform wallet top-ups (amount credited to a named account).
    if (RegExp(
      r'(?:inr|rs\.?)\s*[\d,]+\s+has been credited to your\s+\w',
      caseSensitive: false,
    ).hasMatch(lower)) {
      return false;
    }
    return lower.contains('credited to your wallet a/c') ||
        lower.contains('credited to wallet');
  }

  /// Multi-check filter: promos, scams, and weak "received Rs" alerts are rejected.
  static bool isRealTransactionSms(String sender, String body) {
    final trimmed = body.trim();
    if (trimmed.length < 20) return false;
    if (isOtpOnly(trimmed)) return false;
    if (isNonBankWalletMovement(trimmed)) return false;
    if (isPromoOrOfferSms(trimmed, sender: sender)) return false;

    // Failed UPI is never a completed ledger entry (R2-8). Drop both
    // failed+refunded and failed-retry alerts — the later success SMS is
    // the row we want. Do not require `refunded`: `'has failed'` already
    // implies `'failed'`, and retry alerts must not parse as spend.
    final lowerEarly = trimmed.toLowerCase();
    if (lowerEarly.contains('has failed')) {
      return false;
    }
    // Pending UPI status updates are not completed ledger entries
    // (Slice: "UPI payment of Rs. … is pending. The status will be updated…").
    if (lowerEarly.contains('is pending') &&
        (lowerEarly.contains('upi') ||
            lowerEarly.contains('status will be updated'))) {
      return false;
    }

    // Bill-due / EMI-due reminders mention amounts but are not completed txns.
    // Without this, `_bankAlertPattern`'s "payment of INR" pushes them to
    // parseFailed (evidence: Axis/ICICI due SMS in paisa_sms_analysis.db).
    final lower = trimmed.toLowerCase();
    if (_looksLikeDueReminder(lower)) return false;

    // Transactional bank/UPI alerts in India are delivered from registered DLT
    // sender headers (e.g. VM-HDFCBK), never from personal 10-digit numbers.
    // Reject personal senders BEFORE the completed-signal shortcut, otherwise a
    // scam text from a personal number that mimics a real alert ("Rs.4,999
    // debited from a/c XX1234") would be accepted as a transaction. See ISSUE-3.
    if (isPersonalPhoneSender(sender)) return false;

    if (hasCompletedTransactionSignal(trimmed)) return true;

    if (isFinancialSender(sender) &&
        _bankAlertPattern.hasMatch(trimmed) &&
        !isNonBankWalletMovement(trimmed)) {
      return true;
    }

    return false;
  }

  static bool _looksLikeDueReminder(String lower) {
    if (lower.contains('ignore if paid')) return true;
    if (RegExp(r'\bis due on\b').hasMatch(lower) &&
        !hasCompletedTransactionSignal(lower)) {
      return true;
    }
    if (RegExp(r'\b(?:total due|minimum due|min(?:imum)? amount due)\b')
            .hasMatch(lower) &&
        !RegExp(r'\b(?:spent|debited|used at|credited|received payment)\b')
            .hasMatch(lower)) {
      return true;
    }
    return false;
  }

  static bool isFinancialSender(String sender) {
    if (sender.isEmpty || isPersonalPhoneSender(sender)) return false;
    final upper = sender.toUpperCase();
    if (bankSenderPatterns.any((p) => p.hasMatch(upper))) return true;
    return _trustedSenderHints.any((hint) => upper.contains(hint));
  }

  static const _trustedSenderHints = [
    'HDFCBK',
    'KOTAKB',
    'CBSSBI',
    'PNBSMS',
    'CREDIN',
    'MOBIKW',
    'PLUXEE',
    'SBICRD',
    'SBIN',
    'LENDEN',
    'YESBNK',
    'IDFCFB',
    'ICICIT',
    'ICICIO',
    'AXISBK',
    'PHONEPE',
    'GPAY',
    'PAYTMB',
    'FRCHRG',
    'AMZNPAY',
    'AIRTEL',
    // HSBC India DLT headers (community dump + live inbox: AX-/AD-/VM-HSBCIN*).
    'HSBCIN',
    'HSBCBK',
    'HSBCEX',
    'HSBCIM',
    // Slice Small Finance Bank (DLT: SLCEIT historic app + SLCBNK SFB)
    'SLCEIT',
    'SLCBNK',
    'SLICE',
  ];

  static bool isOtpOnly(String body) {
    return _otpOnly.hasMatch(body) && !transactionSignals.hasMatch(body);
  }

  static bool hasTransactionSignal(String body) {
    return transactionSignals.hasMatch(body);
  }

  static bool isLikelyBankSms(String sender, String body) {
    final normalizedBody = body.trim();

    if (normalizedBody.length < 20) return false;
    if (!isRealTransactionSms(sender, normalizedBody)) return false;

    final senderMatch = bankSenderPatterns.any((p) => p.hasMatch(sender.toUpperCase())) ||
        isFinancialSender(sender);
    final bodyBank = _detectBankFromBody(normalizedBody) != null;

    return senderMatch || bodyBank;
  }

  static String? _detectBankFromSender(String sender) {
    final s = sender.toUpperCase();
    if (s.contains('HDFC')) return 'HDFC';
    if (s.contains('SBI') || s.contains('SBIN')) return 'SBI';
    if (s.contains('ICICI')) return 'ICICI';
    if (s.contains('AXIS')) return 'Axis';
    if (s.contains('KOTAK')) return 'Kotak';
    if (s.contains('PAYTM')) return 'Paytm';
    if (s.contains('PHONEPE')) return 'PhonePe';
    if (s.contains('MOBIKW')) return 'MobiKwik';
    if (s.contains('FRCHRG') || s.contains('FREECHARGE')) return 'Freecharge';
    if (s.contains('AMZNPAY') || s.contains('AMAZONPAY')) return 'Amazon Pay';
    if (s.contains('GPAY') || s.contains('GOOGLE')) return 'GPay';
    if (s.contains('YES')) return 'Yes Bank';
    if (s.contains('INDUS')) return 'IndusInd';
    if (s.contains('PNB')) return 'PNB';
    if (s.contains('CANARA')) return 'Canara';
    if (s.contains('BARODA')) return 'Bank of Baroda';
    if (s.contains('IDFC')) return 'IDFC';
    if (s.contains('FEDBNK') ||
        s.contains('FEDFIB') ||
        s.contains('MYJPTR') ||
        s.contains('FEDERAL')) {
      return 'Federal';
    }
    // HSBC before generic substring traps; headers HSBCIN / HSBCBK / etc.
    if (s.contains('HSBC')) return 'HSBC';
    // Slice SFB — SLCEIT (app era) / SLCBNK (bank alerts) / SLICE
    if (s.contains('SLCEIT') ||
        s.contains('SLCBNK') ||
        s.contains('SLICE')) {
      return 'Slice';
    }
    if (s.contains('LENDEN')) return 'LenDenClub';
    final wallet = SmsKeywordLists.detectWalletProvider(sender);
    if (wallet != null) return wallet;
    return null;
  }

  static String? _detectBankFromBody(String body) {
    final b = body.toLowerCase();
    if (b.contains('hdfc')) return 'HDFC';
    if (b.contains('state bank') || RegExp(r'\bsbi\b').hasMatch(b)) return 'SBI';
    if (b.contains('icici')) return 'ICICI';
    if (b.contains('axis bank') || RegExp(r'\baxis\b').hasMatch(b)) return 'Axis';
    if (b.contains('kotak')) return 'Kotak';
    if (b.contains('federal bank')) return 'Federal';
    if (RegExp(r'\bpnb\b').hasMatch(b) || b.contains('punjab national')) {
      return 'PNB';
    }
    if (b.contains('hsbc')) return 'HSBC';
    // Slice alerts usually end with " - slice"
    if (RegExp(r'-\s*slice\s*$', caseSensitive: false).hasMatch(b.trim()) &&
        (b.contains('a/c') ||
            b.contains('credit card') ||
            b.contains('upi ref') ||
            b.contains('neft') ||
            b.contains('sent from') ||
            b.contains('received in'))) {
      return 'Slice';
    }
    if (b.contains('lendenclub')) return 'LenDenClub';
    final wallet = SmsKeywordLists.detectWalletProvider(body);
    if (wallet != null) return wallet;
    return null;
  }

  /// Prefer the bank that owns the account in the SMS body. Some senders
  /// relay credits into another bank's account — use [registry] when the
  /// account last-4 is known from other SMS.
  static String _resolveBank(
    String sender,
    String body, {
    String? accountLast4,
    AccountBankRegistry? registry,
  }) {
    final fromSender = _detectBankFromSender(sender);
    if (fromSender != null &&
        RegExp(
          r'debited (?:from|to) your account|your kotak bank a/c|from kotak bank ac',
          caseSensitive: false,
        ).hasMatch(body)) {
      return fromSender;
    }

    final explicit = AccountBankRegistry.detectExplicitAccountBank(body);
    if (explicit != null) return explicit;

    if (AccountBankRegistry.isIciciSettlementNotification(sender, body)) {
      if (accountLast4 != null && registry != null) {
        final known = registry.lookup(accountLast4);
        if (known != null) return known;
      }
      return 'Bank';
    }

    if (fromSender != null) return fromSender;

    return _detectBankFromBody(body) ?? 'Bank';
  }

  static String? _normalizeAccountLast4(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    if (digits.length < 4) {
      return digits.padLeft(4, '0');
    }
    return digits.substring(digits.length - 4);
  }

  static String? extractAccountLast4(String body) {
    return _extractAccountFallback(
      body.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' '),
    );
  }

  static String maskFromLast4(String? last4) {
    if (last4 == null || last4.isEmpty) return '';
    return '••••$last4';
  }

  static String _maskAccount(String? last4) {
    return maskFromLast4(last4);
  }

  static double _parseAmount(String raw) {
    return double.parse(raw.replaceAll(',', ''));
  }

  static String _cleanMerchant(String raw) {
    var m = raw.trim();
    m = m.replaceAll(RegExp(r'\s+'), ' ');
    m = m.replaceAll(RegExp(r'[.\s]+$'), '');
    m = m.replaceAll(RegExp(r'^to\s+', caseSensitive: false), '');
    m = m.replaceAll(RegExp(r'\s+on\s+\d.*$', caseSensitive: false), '');
    m = SmsKeywordLists.stripBalanceSuffix(m);
    m = m.replaceAll(RegExp(r'\s+via\s+.*$', caseSensitive: false), '');
    if (m.length > 40) m = m.substring(0, 40).trim();
    if (m.isEmpty) return 'Unknown';
    // Keep VPAs readable (don't title-case local-part / handle).
    if (SmsKeywordLists.isKnownUpiVpa(m)) return m.toLowerCase();
    final embeddedVpa = SmsKeywordLists.extractUpiVpa(m);
    if (embeddedVpa != null && m.contains('@')) return embeddedVpa;
    return _titleCase(m);
  }

  static String _titleCase(String input) {
    return input.split(' ').map((w) {
      if (w.isEmpty) return w;
      if (w.length <= 3 && w == w.toUpperCase()) return w;
      return '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}';
    }).join(' ');
  }

  /// Returns parsed transaction or null if SMS doesn't match any pattern.
  static ParsedSmsTransaction? parse(SmsMessageInput message) {
    if (!isLikelyBankSms(message.sender, message.body)) return null;
    if (isPromoOrOfferSms(message.body, sender: message.sender)) return null;
    return parseTransaction(message);
  }

  /// Full regex extraction — caller must have already passed pipeline gates.
  static ParsedSmsTransaction? parseTransaction(
    SmsMessageInput message, {
    AccountBankRegistry? registry,
  }) {
    final body = message.body.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ');
    // ISSUE-9: reuse the once-built pattern list — rebuilding ~50 RegExps per
    // candidate was compiling ~1M regexes on a large inbox scan.
    for (final pattern in _patterns) {
      final match = pattern.regex.firstMatch(body);
      if (match == null) continue;

      try {
        final amount = _parseAmount(match.group(pattern.amountGroup)!);
        if (amount <= 0) continue;

        final isCredit = pattern.isCredit;
        final accountRaw = pattern.accountGroup != null
            ? match.group(pattern.accountGroup!)
            : _extractAccountFallback(body);
        final account = accountRaw == null
            ? null
            : _normalizeAccountLast4(accountRaw);
        if (pattern.accountGroup != null && account == null) continue;
        final merchant = pattern.merchantGroup != null
            ? () {
                final raw = match.group(pattern.merchantGroup!);
                if (raw != null && raw.trim().isNotEmpty) {
                  final cleaned = _cleanMerchant(raw);
                  // Prefer full allowlisted VPA when regex truncated at '.' / spaces.
                  final vpa = SmsKeywordLists.extractUpiVpa(body);
                  if (vpa != null &&
                      !SmsKeywordLists.isKnownUpiVpa(cleaned) &&
                      (cleaned.length < 4 ||
                          vpa.startsWith(cleaned.toLowerCase().split('@').first))) {
                    return _cleanMerchant(vpa);
                  }
                  return cleaned;
                }
                return _extractMerchantFallback(body, isCredit);
              }()
            : _extractMerchantFallback(body, isCredit);

        final infoMerchant = RegExp(
          r"Info[:\s]+([A-Za-z0-9 .&'-]{3,40})",
          caseSensitive: false,
        ).firstMatch(body);
        final resolvedMerchant = infoMerchant != null && isCredit
            ? _cleanMerchant(infoMerchant.group(1)!)
            : merchant;

        final accountLast4 = account;
        final bank = _resolveBank(
          message.sender,
          body,
          accountLast4: accountLast4,
          registry: registry,
        );
        final resolvedBank = registry?.resolveBank(
              sender: message.sender,
              body: body,
              accountLast4: accountLast4,
              parsedBank: bank,
            ) ??
            bank;

        return ParsedSmsTransaction(
          amount: amount,
          isCredit: isCredit,
          merchant: resolvedMerchant,
          bank: resolvedBank,
          maskedAccount: _maskAccount(account),
          timestamp: message.timestamp,
        );
      } catch (_) {
        continue;
      }
    }

    return null;
  }

  static String? _extractAccountFallback(String body) {
    final patterns = [
      // HSBC India: "A/c 074-260***-006" — digits+hyphens+stars; last-4 of digits.
      RegExp(
        r'(?:a/c|acct)\s+([\d][\d\-*\s]{3,20}\d)',
        caseSensitive: false,
      ),
      RegExp(_account, caseSensitive: false),
      RegExp(
        r'(?:a/c|acct|account|A/C)\s*No\.?\s*[Xx*•]*(\d{4,})\b',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:your\s+)?Account\s+[Xx*•]+(\d{4,})\b',
        caseSensitive: false,
      ),
      RegExp(
        r'Kotak Bank\s+(?:A/?c|AC)\s+X?(\d{4,})\b',
        caseSensitive: false,
      ),
      // HSBC creditcard / debit card masks: "creditcard xxxxx1234", "Debit Card XXXXX71xx"
      RegExp(
        r'(?:credit\s*card|debit\s+card)\s+([xX*\d]{4,})',
        caseSensitive: false,
      ),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(body);
      if (m != null) return _normalizeAccountLast4(m.group(1));
    }
    return null;
  }

  static String _extractMerchantFallback(String body, bool isCredit) {
      if (isCredit) {
      // Platform wallet credit: "Rs. X has been credited to your Foo account"
      final platformCredit = RegExp(
        r'(?:INR|Rs\.?)\s*\d+(?:,\d+)*(?:\.\d{1,2})?\s+has been credited to your\s+([A-Za-z0-9 .&-]{2,40}?)\s+account',
        caseSensitive: false,
      ).firstMatch(body);
      if (platformCredit != null) {
        return _cleanMerchant(platformCredit.group(1)!);
      }

      final thanks = RegExp(
        r"Thanks,\s+([A-Za-z0-9 .&'-]{3,60}?)(?:\s+ACCOUNT)?\.?\s*$",
        caseSensitive: false,
      ).firstMatch(body.trim());
      if (thanks != null) {
        return _cleanMerchant(thanks.group(1)!);
      }

      final thanksInline = RegExp(
        r"Thanks,\s+([A-Za-z0-9 .&'-]{3,60})",
        caseSensitive: false,
      ).firstMatch(body);
      if (thanksInline != null) {
        return _cleanMerchant(thanksInline.group(1)!);
      }

      final fromVpa = RegExp(
        r'from VPA\s+([A-Za-z0-9._+\-]+@[A-Za-z0-9._+\-]+)',
        caseSensitive: false,
      ).firstMatch(body);
      if (fromVpa != null) return _cleanMerchant(fromVpa.group(1)!);

      // Prefer allowlisted UPI handles when VPA appears without "from VPA".
      final allowlistedVpa = SmsKeywordLists.extractUpiVpa(body);
      if (allowlistedVpa != null) return _cleanMerchant(allowlistedVpa);

      final salary = RegExp(
        r"credited(?:\s+by|\s+from)\s+([A-Za-z0-9 .&'-]{3,40})",
        caseSensitive: false,
      ).firstMatch(body);
      if (salary != null) return _cleanMerchant(salary.group(1)!);
      return 'Credit received';
    }

    final info = RegExp(
      r"Info[:\s]+([A-Za-z0-9 .&'-]{3,40})",
      caseSensitive: false,
    ).firstMatch(body);
    if (info != null) return _cleanMerchant(info.group(1)!);

    final allowlistedVpa = SmsKeywordLists.extractUpiVpa(body);
    if (allowlistedVpa != null) return _cleanMerchant(allowlistedVpa);

    final upi = RegExp(
      r"(?:to|at|towards)\s+([A-Za-z0-9 .&'-]{3,40})",
      caseSensitive: false,
    ).firstMatch(body);
    if (upi != null) return _cleanMerchant(upi.group(1)!);

    return 'Transaction';
  }

  /// Compiled once for the process lifetime (ISSUE-9).
  static final List<_SmsPattern> _patterns = _buildPatterns();

  static List<_SmsPattern> _buildPatterns() {
    final amt = _amount;
    final cur = _currency;
    final acct = _account;

    return [
      // Platform wallet credit: Rs. 2500.00 has been credited to your Foo account
      _SmsPattern(
        RegExp(
          r'(?:INR|Rs\.?)\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+has been credited to your\s+([A-Za-z0-9 .&-]{2,40}?)\s+account',
          caseSensitive: false,
        ),
        amountGroup: 1,
        merchantGroup: 2,
        isCredit: true,
      ),
      // --- HSBC India (sender HSBCIN / XX-HSBCIN; templates from public OSS samples
      // + DLT headers HSBCIN/HSBCBK — Med–High conf for India phrasing; local dump
      // had OTP/promo only, no live txn SMS) ---
      // Outgoing NEFT/RTGS/IMPS confirmation (debit from HSBC, not income):
      // "your NEFT transaction ... for INR 150,000.00 has been credited to the HDFC A/c … of NAME"
      _SmsPattern(
        RegExp(
          r'(?:NEFT|RTGS|IMPS)\s+transaction.*?for\s+(?:INR|Rs\.?)\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+has been credited to the\s+\w+\s+A/c\s+[X\d*]+\s+of\s+([A-Za-z][A-Za-z .]{1,40}?)\s+on\s+',
          caseSensitive: false,
        ),
        amountGroup: 1,
        merchantGroup: 2,
      ),
      // Savings debit: "INR 1,234.56 is paid from your A/c 074-260***-006 to AMAZON on …"
      _SmsPattern(
        RegExp(
          r'(?:INR|Rs\.?)\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+is paid from (?:your\s+)?(?:A/?c|account)\s+([\d\-*\sXx]+?)\s+to\s+([A-Za-z0-9 .&-]{2,40}?)\s+on\s+',
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        merchantGroup: 3,
      ),
      // Savings credit: "INR 50,000.00 is credited to your A/c 074-260***-006 as NEFT …"
      _SmsPattern(
        RegExp(
          r'(?:INR|Rs\.?)\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+is credited to your\s+(?:A/?c|account)\s+([\d\-*\sXx]+?)(?:\s+as\s+|\s+on\s+|\s*\.)',
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        isCredit: true,
      ),
      // Savings credit alt: "A/c 074-260***-006 is credited with INR 5000.00 …"
      _SmsPattern(
        RegExp(
          r'(?:A/?c|account)\s+([\d\-*\sXx]+?)\s+is credited with\s+(?:INR|Rs\.?)\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)',
          caseSensitive: false,
        ),
        accountGroup: 1,
        amountGroup: 2,
        isCredit: true,
      ),
      // Debit card POS: "Thank you for using HSBC Debit Card XXXXX71xx for INR 305.00 … at IKEA"
      _SmsPattern(
        RegExp(
          r'Thank you for using\s+HSBC\s+Debit Card\s+([Xx*\d]+)\s+(?:for\s+)?(?:INR|Rs\.?)\s*(\d+(?:,\d+)*(?:\.\d{1,2})?).*?\bat\s+([A-Za-z0-9 .&-]{2,40}?)(?:\s*\.|$)',
          caseSensitive: false,
        ),
        accountGroup: 1,
        amountGroup: 2,
        merchantGroup: 3,
      ),
      // Debit card alt order: "… Debit Card XXXXX71xx at IKEA . for INR 49.00"
      _SmsPattern(
        RegExp(
          r'HSBC\s+Debit Card\s+([Xx*\d]+)\s+at\s+([A-Za-z0-9 .&-]{2,40}?)\s*\.\s*for\s+(?:INR|Rs\.?)\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)',
          caseSensitive: false,
        ),
        accountGroup: 1,
        merchantGroup: 2,
        amountGroup: 3,
      ),
      // Credit card spend (live inbox evidence):
      // "HSBC creditcard xxxxx3740 used at zepto marketplace private for INR 9975.00 on 28/07/26.Limit Rs …"
      _SmsPattern(
        RegExp(
          r'HSBC\s+credit\s*card\s+([Xx*\d]+)\s+used at\s+(.+?)\s+for\s+(?:INR|Rs\.?)\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)',
          caseSensitive: false,
        ),
        accountGroup: 1,
        merchantGroup: 2,
        amountGroup: 3,
      ),
      // CC payment received: "Payment of Rs … received towards/on your HSBC Credit Card …"
      _SmsPattern(
        RegExp(
          r'(?:Payment of|paid)\s+(?:INR|Rs\.?)\s*(\d+(?:,\d+)*(?:\.\d{1,2})?).*(?:received (?:towards|on) your).*HSBC\s+Credit\s+Card\s+(?:ending\s+)?(?:with\s+)?(?:XX|xx|X|\*+)?(\d{4})',
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        isCredit: true,
      ),
      // "spent on your HSBC Credit Card ending …" (majors cluster wording)
      _SmsPattern(
        RegExp(
          r"(?:INR|Rs\.?)\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+spent on your HSBC\s+(?:Bank\s+)?Credit Card ending (?:XX|xx)?(\d{4})\s+at\s+([A-Za-z0-9 .&'-]+)",
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        merchantGroup: 3,
      ),
      // --- Slice Small Finance Bank (live dump SLCEIT + public SLCBNK) ---
      // Account masks may show 3 or 4 trailing digits (e.g. xx0856 / XXX856).
      // UPI debit: "Rs. 550 sent from a/c xx0856 on 18-May-26 to CREW SPORTS (UPI Ref: …) - slice"
      _SmsPattern(
        RegExp(
          r'Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+sent from a/c\s*(?:xx|XX|X{2,}|\*+)?(\d{3,4})\s+on\s+\S+\s+to\s+(.+?)\s*\(',
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        merchantGroup: 3,
      ),
      // Credit NEFT/generic: "Rs. 3,735.60 received in a/c XXX856 from NAME on 11-May-26 (NEFT Ref …)"
      _SmsPattern(
        RegExp(
          r'Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+received in a/c\s*(?:xx|XX|X{2,}|\*+)?(\d{3,4})\s+from\s+(.+?)\s+on\s+',
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        merchantGroup: 3,
        isCredit: true,
      ),
      // Credit UPI/IMPS: "received in slice A/c … via UPI" / "received in A/c … via IMPS"
      _SmsPattern(
        RegExp(
          r'Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+received in (?:slice\s+)?A/c\s*(?:xx|XX|X{2,}|\*+)?(\d{3,4})\s+on\s+\S+\s+from\s+(.+?)\s+via\s+(?:UPI|IMPS)',
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        merchantGroup: 3,
        isCredit: true,
      ),
      // IMPS debit: "IMPS payment of Rs. 99,990 from A/c xx0856 done on … to NAME is successful"
      _SmsPattern(
        RegExp(
          r'IMPS payment of\s+Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+from\s+A/c\s*(?:xx|XX|X{2,}|\*+)?(\d{3,4})\s+done on\s+\S+\s+to\s+(.+?)\s+is successful',
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        merchantGroup: 3,
      ),
      // AutoPay: "Successfully paid Rs.1 from slice a/c XX2743 to OpenAI LLC on … via UPI AutoPay"
      _SmsPattern(
        RegExp(
          r'Successfully paid\s+Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+from slice\s+a/c\s*(?:xx|XX|X{2,}|\*+)?(\d{3,4})\s+to\s+(.+?)\s+on\s+',
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        merchantGroup: 3,
      ),
      // CC spend (SLCBNK): "Rs. 124 spent on your credit card xx7185 at MERCHANT on 18-Jun-26 (UPI Ref: …)"
      _SmsPattern(
        RegExp(
          r'Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+spent on your credit card\s*(?:xx|XX|X{2,}|\*+)?(\d{3,4})\s+at\s+(.+?)\s+on\s+',
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        merchantGroup: 3,
      ),
      // SBI UPI: Dear UPI user A/C X0429 debited by 3250.00 on date 04Jun26 trf to MERCHANT
      // Amount accepts optional thousands commas (1,246.50) like other bank patterns.
      _SmsPattern(
        RegExp(
          r"Dear UPI user A/C\s*X?(\d{4})\s+debited by\s+(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+on date\s+\S+\s+trf to\s+([A-Za-z0-9 .&'-]+?)(?:\s+Refno|\s+If not)",
          caseSensitive: false,
        ),
        amountGroup: 2,
        accountGroup: 1,
        merchantGroup: 3,
      ),
      // SBI UPI reversal credit: ur A/cX0429 credited with Rs500.00 on 04Jun26
      _SmsPattern(
        RegExp(
          r'ur A/cX?(\d{4})\s+credited with Rs\.?\s*(\d+(?:\.\d+)?)\s+on',
          caseSensitive: false,
        ),
        amountGroup: 2,
        accountGroup: 1,
        isCredit: true,
      ),
      // SBI Credit Card: Rs.605.29 spent on your SBI Credit Card ending 3452 at MERCHANT
      _SmsPattern(
        RegExp(
          r"Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+spent on your (?:SBI|ICICI|Axis|HDFC|Kotak|IDFC(?:\s+FIRST)?|HSBC)\s+(?:Bank\s+)?Credit Card ending (?:XX|xx)?(\d{4}) at ([A-Za-z0-9 .&'-]+)",
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        merchantGroup: 3,
      ),
      // IDFC: INR 80.00 spent on your IDFC FIRST Bank Credit Card ending XX7424 at HungerBox
      _SmsPattern(
        RegExp(
          r"(?:INR|Rs\.?)\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+spent on your (?:IDFC(?:\s+FIRST)?|HDFC|SBI|ICICI|Axis|Kotak|HSBC)\s+(?:Bank\s+)?(?:\w+\s+)*Credit Card ending (?:XX|xx)?(\d{4}) at ([A-Za-z0-9 .&'-]+)",
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        merchantGroup: 3,
      ),
      // ICICI: Payment of Rs 14,747.00 received on your ICICI Bank Credit Card XX2009
      _SmsPattern(
        RegExp(
          r'(?:Payment of|paid)\s+(?:INR|Rs\.?)\s*(\d+(?:,\d+)*(?:\.\d{1,2})?).*(?:received on your|received towards your).*Credit Card (?:XX|xx|X)?(\d{4})',
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        isCredit: true,
      ),
      // ICICI CC spend: INR 387.00 spent using ICICI Bank Card XX2009 on ... on AMAZON
      _SmsPattern(
        RegExp(
          r'INR\s+(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+spent using ICICI Bank Card (?:XX|xx)?(\d{4}) on \d+-\w+-\d+ on ([A-Za-z0-9 .*]+?)\.\s+Avl',
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        merchantGroup: 3,
      ),
      // Live dump: "USD 23.60 spent using ICICI Bank Card XX2009 on 30-Jul-26 on ANTHROPIC* CLAU. Avl Limit: INR …"
      _SmsPattern(
        RegExp(
          r'(?:USD|EUR|GBP)\s+(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+spent using ICICI Bank Card (?:XX|xx)?(\d{4}) on \d+-\w+-\d+ on ([A-Za-z0-9 .*]+?)(?:\.|,)\s*Avl',
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        merchantGroup: 3,
      ),
      // Live dump: "IRCTC … refund of Rs 80.36 credited to ICICI Bank Credit Card XX0003"
      // Also: "ZEPTO … refund of Rs 222.00 credited to your ICICI Bank Credit Card XX0003"
      _SmsPattern(
        RegExp(
          r'refund of\s+(?:INR|Rs\.?)\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+credited to (?:your\s+)?ICICI Bank Credit Card (?:XX|xx)?(\d{4})',
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        isCredit: true,
      ),
      // Live dump: "Cashback of INR 83 has been credited to your Axis Bank Flipkart Visa Credit Card XX8341"
      _SmsPattern(
        RegExp(
          r'Cashback of\s+(?:INR|Rs\.?)\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+has been credited to your .+?Credit Card (?:XX|xx)?(\d{4})',
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        isCredit: true,
      ),
      // ICICI CC UPI debit: Credit Card XX0003 debited for INR 50.00 on ... for UPI-xxx-MERCHANT
      _SmsPattern(
        RegExp(
          r'ICICI Bank Credit Card (?:XX|xx)?(\d{4}) debited for (?:INR|Rs\.?)\s*(\d+(?:,\d+)*(?:\.\d{1,2})?) on \d+-\w+-\d+ for (?:UPI-)?([A-Za-z0-9._-]+)',
          caseSensitive: false,
        ),
        amountGroup: 2,
        accountGroup: 1,
        merchantGroup: 3,
      ),
      // CRED / generic: Payment credited towards bank Credit Card (no mask in SMS)
      _SmsPattern(
        RegExp(
          r'Payment of (?:INR|Rs\.?)\s*(\d+(?:,\d+)*(?:\.\d{1,2})?).*credited towards your (?:ICICI Bank|Bank of Baroda|HDFC Bank|Axis Bank|HSBC) Credit Card',
          caseSensitive: false,
        ),
        amountGroup: 1,
        isCredit: true,
      ),
      // HDFC CC payment received
      _SmsPattern(
        RegExp(
          r'PAYMENT OF Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+RECEIVED TOWARDS YOUR CREDIT CARD ENDING WITH (\d{4})',
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        isCredit: true,
      ),
      // YES BANK CC payment received
      _SmsPattern(
        RegExp(
          r'payment of (?:INR|Rs\.?)\s*(\d+(?:,\d+)*(?:\.\d{1,2})?).*received towards your YES BANK Credit Card ending (\d{4})',
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        isCredit: true,
      ),
      // BOBCARD spend alert
      _SmsPattern(
        RegExp(
          r"INR\s+(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+is spent on your BOBCARD ending (\d{4})\s+at\s+([A-Za-z0-9 .&'_-]+)",
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        merchantGroup: 3,
      ),
      // ICICI CC reversal credit
      _SmsPattern(
        RegExp(
          r'Reversal of (?:INR|Rs\.?)\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+credited to (?:\w+ )*Credit Card X+(\d{4})',
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        isCredit: true,
      ),
      // SBI BBPS credit card payment
      _SmsPattern(
        RegExp(
          r'received payment of (?:INR|Rs\.?)\s*(\d+(?:,\d+)*(?:\.\d{1,2})?).*BBPS.*credited to your SBI Credit Card',
          caseSensitive: false,
        ),
        amountGroup: 1,
        isCredit: true,
      ),
      // BOBCARD payment received
      _SmsPattern(
        RegExp(
          r'Payment of (?:INR|Rs\.?)\s*(\d+(?:,\d+)*(?:\.\d{1,2})?).*received for your BOBCARD ending (\d{4})',
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        isCredit: true,
      ),
      // SBI UPI CCBP: debited from savings to pay credit card bill
      _SmsPattern(
        RegExp(
          r'A/C X?(\d{4}) debited by (\d+(?:,\d+)*(?:\.\d{1,2})?) on date \d+\w+ trf to MBK CCBP',
          caseSensitive: false,
        ),
        accountGroup: 1,
        amountGroup: 2,
        merchantGroup: null,
      ),
      // Yes Bank CC: INR 449.54 spent on YES BANK Card X9757 @UPI_MCDONALDS
      _SmsPattern(
        RegExp(
          r"INR\s+(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+spent on YES BANK Card X?(\d{4})\s+@([A-Za-z0-9_ .&'-]+)",
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        merchantGroup: 3,
      ),
      // Schema 33 — live inbox completed txns that were parseFailed.
      // HDFC CC: "Spent Rs.3035.4 On HDFC Bank Card 1949 At AIIMSOTHCRCARD On … BLOCK CC"
      _SmsPattern(
        RegExp(
          r"Spent\s+Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+On\s+(?:HDFC|SBI|ICICI|Axis|Kotak)\s+Bank\s+Card\s+[xX*]*(\d{4})\s+At\s+([A-Za-z0-9 .&'_-]+?)\s+On\s+",
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        merchantGroup: 3,
      ),
      // HDFC debit card / BBPS: "Spent Rs.31250 From HDFC Bank Card x3569 At CCBBPSNO On … Bal Rs … BLOCK DC"
      _SmsPattern(
        RegExp(
          r"Spent\s+Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+From\s+(?:HDFC|SBI|ICICI|Axis|Kotak)\s+Bank\s+Card\s+[xX*]*(\d{4})\s+At\s+([A-Za-z0-9 .&'_-]+?)\s+On\s+",
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        merchantGroup: 3,
      ),
      // Live leftover: "ALERT:Rs.X spent via HDFC BANK Debit Card xx3569 at CCBBPSNO on Aug 1 …"
      _SmsPattern(
        RegExp(
          r"(?:ALERT:)?\s*Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+spent via\s+(?:HDFC|SBI|ICICI|Axis|Kotak)\s+BANK\s+Debit Card\s+[xX*]*(\d{4})\s+at\s+([A-Za-z0-9 .&'_-]+?)\s+on\s+",
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        merchantGroup: 3,
      ),
      // ICICI cashback — often no card last-4: "Congrats! Rs 134.09 cashback credited to ICICI Bank Credit Card"
      _SmsPattern(
        RegExp(
          r'Congrats!\s*Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+cashback credited to ICICI Bank Credit Card',
          caseSensitive: false,
        ),
        amountGroup: 1,
        isCredit: true,
      ),
      // SBI CC reversal/cashback: "Rs. 1655.36 has been credited to your SBI Credit Card xxxx3452, towards reversal/cashback"
      _SmsPattern(
        RegExp(
          r'Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+has been credited to your SBI Credit Card\s+[xX*]+(\d{4})\s*,\s*towards reversal/cashback',
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        isCredit: true,
      ),
      // SBI CC e-mandate debit: "Transaction of Rs.2,340.58 at CURSORAIPOWEREDIDE against E-mandate … debited to your SBI Credit Card ending 3452"
      _SmsPattern(
        RegExp(
          r'Transaction of Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+at\s+([A-Za-z0-9]+)\s+against E-mandate.*?debited to your SBI Credit Card ending\s+(\d{4})',
          caseSensitive: false,
        ),
        amountGroup: 1,
        merchantGroup: 2,
        accountGroup: 3,
      ),
      // SBI UPI credit: "your A/c X6675-credited by Rs.10000 on 01Jul26 transfer from NAME"
      _SmsPattern(
        RegExp(
          r'your A/c\s*X?(\d{4})-credited by Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)',
          caseSensitive: false,
        ),
        accountGroup: 1,
        amountGroup: 2,
        isCredit: true,
      ),
      // SBI IMPS credit: "Your a/c no. XXXXXXXX6675 is credited by Rs.74000.00"
      _SmsPattern(
        RegExp(
          r'Your a/c no\.\s*X+(\d{4,})\s+is credited by Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)',
          caseSensitive: false,
        ),
        accountGroup: 1,
        amountGroup: 2,
        isCredit: true,
      ),
      // CBS SBI: "Your AC XXXXX460429 Debited INR 205.84 on 28/04/26 -ATM PENDING AMC"
      _SmsPattern(
        RegExp(
          r'Your A/?C\s+X+(\d{4,})\s+Debited\s+INR\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)',
          caseSensitive: false,
        ),
        accountGroup: 1,
        amountGroup: 2,
      ),
      // CBS SBI: "Your A/C XXXXX286675 Credited INR 50,000.00 on 20/03/26 -Deposited by Cash"
      _SmsPattern(
        RegExp(
          r'Your A/?C\s+X+(\d{4,})\s+Credited\s+INR\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)',
          caseSensitive: false,
        ),
        accountGroup: 1,
        amountGroup: 2,
        isCredit: true,
      ),
      // Kotak CC: "INR 282 spent on Kotak Credit Card x4310 on 02-Aug-2026 at SWIGGY PVT LTD FOOD2."
      _SmsPattern(
        RegExp(
          r"INR\s+(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+spent on Kotak Credit Card\s+[xX*]*(\d{4})\s+on\s+\S+\s+at\s+([A-Za-z0-9 .&'-]+?)(?:\.|$|\s+Avl)",
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        merchantGroup: 3,
      ),
      // PNB: "your A/c XX4720 debited with Rs.3.24 towards bank charges"
      _SmsPattern(
        RegExp(
          r'your A/c\s+X+(\d{4})\s+debited with Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+towards bank charges',
          caseSensitive: false,
        ),
        accountGroup: 1,
        amountGroup: 2,
      ),
      // IDFC interest: "Monthly interest of INR.4.00 earned on your Savings A/c XX0070 has been credited"
      _SmsPattern(
        RegExp(
          r'Monthly interest of\s+(?:INR|Rs)\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+earned on your Savings A/c\s+X+(\d{4}).*credited',
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        isCredit: true,
      ),
      // IDFC CC payment thank-you: "Thank you for payment of INR 325.50 towards your FIRST Power Plus Credit Card XX7424"
      _SmsPattern(
        RegExp(
          r'Thank you for payment of\s+(?:INR|Rs\.?)\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+towards your .+?Credit Card\s+(?:XX|xx|X)?(\d{4})',
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        isCredit: true,
      ),
      // Live Axis CC (multiline → spaces): "Spent INR 663 Axis Bank Card no. XX8341
      // 10-12-25 20:42:01 IST MYNTRA Avl Limit: INR …"
      _SmsPattern(
        RegExp(
          r"Spent\s+(?:INR|Rs\.?)\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+Axis Bank Card no\.?\s*(?:XX|xx)?(\d{4})\s+\d{1,2}-\d{1,2}-\d{2,4}\s+\d{1,2}:\d{2}:\d{2}\s+IST\s+([A-Za-z0-9 *._&'-]+?)\s+Avl",
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        merchantGroup: 3,
      ),
      // Axis / major bank CC: "INR 1,200.00 spent on Axis Bank Card XX8341 at AMAZON"
      _SmsPattern(
        RegExp(
          r"(?:INR|Rs\.?)\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+spent on (?:your\s+)?(?:Axis|HDFC|ICICI|SBI|Kotak)\s+Bank Card (?:XX|xx|X)?(\d{4})\s+at\s+([A-Za-z0-9 .&'*_-]+)",
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        merchantGroup: 3,
      ),
      // Kotak NACH: "is debited to|from your Account XXXXXX3649 towards NACH-…"
      // Live dumps use both prepositions interchangeably.
      _SmsPattern(
        RegExp(
          r"INR\s+(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+is debited (?:from|to) your Account\s+X+(\d{4,})\s+on.*?towards\s+([A-Za-z0-9 .&'-]+)",
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        merchantGroup: 3,
      ),
      // Kotak UPI: Sent Rs.20000.00 from Kotak Bank AC X3649 to merchant@upi
      _SmsPattern(
        RegExp(
          r"Sent Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+from Kotak Bank AC X?(\d{4,})\s+to\s+([A-Za-z0-9@._+\-]+)",
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        merchantGroup: 3,
      ),
      // Kotak NEFT credit: Rs. 72700 credited to your Kotak Bank a/c XX3649 via NEFT
      _SmsPattern(
        RegExp(
          r"Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+credited to your Kotak Bank a/c\s+X*(\d{4,})\s+via\s+NEFT",
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        isCredit: true,
      ),
      // SBI NACH credit: Your A/C XXXXX286675 has a credit by NACH- MERCHANT of Rs 733.50
      _SmsPattern(
        RegExp(
          r"Your A/C\s+X+(\d{4,})\s+has a credit by\s+([A-Za-z0-9 .&'-]+?)\s+of\s+(?:Rs\.?|INR)\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)",
          caseSensitive: false,
        ),
        accountGroup: 1,
        merchantGroup: 2,
        amountGroup: 3,
        isCredit: true,
      ),
      _SmsPattern(
        RegExp(
          r'(?:HDFC Bank:?\s*)?Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+debited\s+from\s+(?:HDFC Bank\s+)?A/?c\s*\*+(\d{4})\b',
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
      ),
      // HDFC: Rs.3700 debited from HDFC Bank A/c **5300 on DATE to A/c
      _SmsPattern(
        RegExp(
          r'Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+debited\s+from\s+HDFC Bank\s+A/?c\s*\*+(\d{4})\b',
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
      ),
      // HDFC NEFT salary: deposited in HDFC Bank A/c XX5300
      _SmsPattern(
        RegExp(
          r'(?:INR|Rs\.?)\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+deposited in HDFC Bank A/c\s*X*(\d{4})\b',
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        isCredit: true,
      ),
      // HDFC: INR 73,000 debited from HDFC Bank XX5300
      _SmsPattern(
        RegExp(
          r'(?:INR|Rs\.?)\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+debited\s+from\s+HDFC Bank\s+XX?(\d{4})\b',
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
      ),
      // HDFC: Sent Rs.3000.00 From HDFC Bank A/C *5300 To MERCHANT On 09/12/25
      _SmsPattern(
        RegExp(
          r"Sent\s+Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+From\s+HDFC Bank\s+A/C\s*\*?(\d{4})\s+To\s+([A-Za-z0-9 @.'&-]+?)\s+On",
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        merchantGroup: 3,
      ),
      // HDFC Credit Alert: Credit Alert! Rs.1000.00 credited to HDFC Bank A/c XX5300
      _SmsPattern(
        RegExp(
          r'Credit Alert!\s*Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+credited to HDFC Bank A/c\s*X*(\d{4})',
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        isCredit: true,
      ),
      // SBI NEFT credit: INR 2,782.61 credited to your A/c No XX0429 … ACCOUNT-SBI
      _SmsPattern(
        RegExp(
          r'(?:INR|Rs\.?)\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+credited to your A/c\s*No\.?\s*X*(\d{4})\b.*?(?:NEFT|neft)',
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        isCredit: true,
      ),
      // ICICI savings: "ICICI Bank Account XX1505 credited:Rs. …" (4+ digits only;
      // 3-digit XX505 is left unparsed on purpose — do not invent a padded mask).
      _SmsPattern(
        RegExp(
          r'ICICI Bank Account\s+X+(\d{4,})\s+credited:Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)',
          caseSensitive: false,
        ),
        accountGroup: 1,
        amountGroup: 2,
        isCredit: true,
      ),
      // Live leftover: CC refund landed in savings — "Refund of Rs X from ICICI
      // Bank Credit Card XX0003 to Savings Account XX1505 has been successfully transferred."
      _SmsPattern(
        RegExp(
          r'Refund of Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)\s+from ICICI Bank Credit Card\s+[Xx*]+\d+\s+to Savings Account\s+[Xx*]+(\d{4})\s+has been successfully transferred',
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        isCredit: true,
      ),
      // ICICI settlement relay: account XXXXXXXX0429 has been credited with amount
      // Live LenDenClub relays sometimes omit the leading 0: "amount  .85"
      _SmsPattern(
        RegExp(
          r'account\s+X+(\d{4})\s+has been credited with amount\s+(\d+(?:,\d+)*(?:\.\d{1,2})?|\.\d{1,2})',
          caseSensitive: false,
        ),
        amountGroup: 2,
        accountGroup: 1,
        isCredit: true,
      ),
      // ICICI IMPS: Acct XX505 debited with Rs 74,000.00
      _SmsPattern(
        RegExp(
          r'ICICI Bank Acct XX(\d+)\s+debited with Rs\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)',
          caseSensitive: false,
        ),
        amountGroup: 2,
        accountGroup: 1,
      ),
      // HDFC: Sent Rs.486.00 from a/c **4321 to Swiggy on 07-Jul
      // Merchant may be a name or allowlisted VPA (coffee.shop@ybl).
      _SmsPattern(
        RegExp(
          "Sent\\s+$cur$amt\\s+from\\s+a/c\\s*$acct\\s+to\\s+([A-Za-z0-9@._+&'\\-]+?)(?:\\s+on\\b|\\s+UPI\\b|\\s+Ref\\b|\\.\\s|\$)",
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        merchantGroup: 3,
      ),
      // Rs.500.00 debited from a/c **4321 on 07-Jul. Info: SWIGGY
      _SmsPattern(
        RegExp(
          "$cur$amt\\s+debited\\s+from\\s+(?:your\\s+)?(?:a/c|acct|account)\\s*$acct.*?(?:Info[:\\s]+|UPI[:\\s]+)([A-Za-z0-9 .&'\\-]+)",
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        merchantGroup: 3,
      ),
      // ICICI: Acct XX123 debited for Rs 500.00 on 07-Jul-25; Swiggy credited
      // Also accept "Acc" (fixture / truncated spelling seen in some alerts).
      _SmsPattern(
        RegExp(
          "(?:Acct|Acc|A/c|Account)\\s*(?:XX|xx|\\*\\*|••)?\\s*$acct\\s+debited\\s+for\\s+$cur$amt.*?(?:;|/|-)\\s*([A-Za-z0-9 .&'\\-]+?)\\s+credited",
          caseSensitive: false,
        ),
        amountGroup: 2,
        accountGroup: 1,
        merchantGroup: 3,
      ),
      // Axis: INR 500.00 debited on 07-07-25 Info: Swiggy
      _SmsPattern(
        RegExp(
          "$cur$amt\\s+debited.*?(?:Info[:\\s]+)([A-Za-z0-9 .&'\\-]+)",
          caseSensitive: false,
        ),
        amountGroup: 1,
        merchantGroup: 2,
      ),
      // SBI: Rs.500.00 debited from A/c XX1234 on 07Jul25. Info: SWIGGY
      _SmsPattern(
        RegExp(
          "$cur$amt\\s+debited\\s+from\\s+A/c\\s*(?:XX|xx|\\*\\*)?\\s*$acct.*?(?:Info[:\\s]+)([A-Za-z0-9 .&'\\-]+)",
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        merchantGroup: 3,
      ),
      // Kotak: Rs.500.00 debited from Kotak Bank a/c XXXX1234 towards Swiggy
      _SmsPattern(
        RegExp(
          "$cur$amt\\s+debited\\s+from\\s+.*?a/c\\s*(?:XXXX|xx|\\*\\*)?\\s*$acct\\s+towards\\s+([A-Za-z0-9 .&'\\-]+?)(?:\\s+on|\\.|\\s+ref)",
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        merchantGroup: 3,
      ),
      // Paytm / PhonePe: Rs.500 paid to Swiggy via Paytm
      _SmsPattern(
        RegExp(
          "$cur$amt\\s+paid\\s+(?:to|at)\\s+([A-Za-z0-9 .&'\\-]+?)(?:\\s+via|\\s+on|\\.|\\s+using)",
          caseSensitive: false,
        ),
        amountGroup: 1,
        merchantGroup: 2,
      ),
      // UPI: Rs 500.00 spent at AMAZON PAY
      _SmsPattern(
        RegExp(
          "$cur$amt\\s+spent\\s+at\\s+([A-Za-z0-9 .&'\\-]+)",
          caseSensitive: false,
        ),
        amountGroup: 1,
        merchantGroup: 2,
      ),
      // Credit: Rs. 68000.00 credited to your a/c **2015
      _SmsPattern(
        RegExp(
          '$cur$amt\\s+credited\\s+to\\s+(?:your\\s+)?(?:a/c|acct|account)\\s*$acct',
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
        isCredit: true,
      ),
      // Credit: credited with Rs. 5000.00
      _SmsPattern(
        RegExp(
          'credited\\s+with\\s+$cur$amt',
          caseSensitive: false,
        ),
        amountGroup: 1,
        isCredit: true,
      ),
      // Bank credit: You received Rs.500 in your account
      _SmsPattern(
        RegExp(
          r'(?:you\s+)?received\s+Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?).*in your (?:a/c|account|bank)',
          caseSensitive: false,
        ),
        amountGroup: 1,
        isCredit: true,
      ),
      // Kotak UPI/IMPS credit: Received Rs.456.25 in your Kotak Bank AC X3649
      _SmsPattern(
        RegExp(
          r'Received Rs\.?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?).*in your Kotak Bank',
          caseSensitive: false,
        ),
        amountGroup: 1,
        isCredit: true,
      ),
      // PNB loan payment: "amount of Rs. 5200" and live "amount Rs 5000" (optional of).
      _SmsPattern(
        RegExp(
          r'Thanks for depositing an amount(?: of)? (?:Rs\.?|INR)\s*(\d+(?:,\d+)*(?:\.\d{1,2})?).*Loan Ac\s*X*(\d{4,})',
          caseSensitive: false,
        ),
        amountGroup: 1,
        accountGroup: 2,
      ),
      // SBI ECS/NACH dishonor return charges
      _SmsPattern(
        RegExp(
          r'ECS/NACH dishonored in Acc\s+X+(\d{4,}).*?(?:Rs\.?|INR)\s*(\d+(?:,\d+)*(?:\.\d{1,2})?).*debited',
          caseSensitive: false,
        ),
        accountGroup: 1,
        amountGroup: 2,
      ),
      // EMI: Rs.8500.00 debited ... EMI / Home Loan
      _SmsPattern(
        RegExp(
          '$cur$amt\\s+debited.*?(?:EMI|Home Loan|Loan)',
          caseSensitive: false,
        ),
        amountGroup: 1,
        merchantGroup: null,
      ),
      // Generic debit with amount
      _SmsPattern(
        RegExp(
          '$cur$amt\\s+(?:has been\\s+)?debited',
          caseSensitive: false,
        ),
        amountGroup: 1,
      ),
    ];
  }
}

class _SmsPattern {
  const _SmsPattern(
    this.regex, {
    required this.amountGroup,
    this.accountGroup,
    this.merchantGroup,
    this.isCredit = false,
  });

  final RegExp regex;
  final int amountGroup;
  final int? accountGroup;
  final int? merchantGroup;
  final bool isCredit;
}
