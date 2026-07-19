/// Keyword lists and light helpers borrowed from open-source Indian SMS
/// parsers (e.g. MabudAlam/transaction_sms_parser) — Paisa-native copies only.
///
/// Used to tighten VPA/merchant extraction, wallet recognition, optional card
/// scheme hints, and balance-suffix stripping. Does not replace Paisa's
/// parsers, promo filters, or enrichment pipeline.
abstract final class SmsKeywordLists {
  /// Known UPI PSP / bank handles (lowercase, with leading `@`).
  static const upiHandles = <String>[
    '@apl',
    '@yapl',
    '@upi',
    '@boi',
    '@cnrb',
    '@dlb',
    '@indus',
    '@pnb',
    '@sbi',
    '@dbs',
    '@fam',
    '@okhdfcbank',
    '@okaxis',
    '@okicici',
    '@yesg',
    '@icici',
    '@jupiteraxis',
    '@ikwik',
    '@jio',
    '@axb',
    '@paytm',
    '@pz',
    '@ybl',
    '@ibl',
    '@axl',
    '@sliceaxis',
    '@tapicici',
    '@zoicici',
    '@barodampay',
    '@rbl',
    '@idbi',
    '@aubank',
    '@axisbank',
    '@bandhan',
    '@kbl',
    '@federal',
    '@uco',
    '@citi',
    '@citigold',
    '@freecharge',
    '@oksbi',
    '@hsbc',
    '@indianbank',
    '@allbank',
    '@kotak',
    '@unionbankofindia',
    '@uboi',
    '@unionbank',
    '@sib',
    '@yespay',
  ];

  /// Digital wallet / BNPL provider tokens (lowercase, space form).
  static const walletProviders = <String>[
    'paytm',
    'phonepe',
    'amazon pay',
    'amazon_pay',
    'mobikwik',
    'freecharge',
    'airtel money',
    'airtel_money',
    'ola money',
    'ola_money',
    'jio money',
    'jio_money',
    'payzapp',
    'oxigen',
    'itzcash',
    'simpl',
    'lazypay',
    'gpay',
    'google pay',
  ];

  /// Canonical display name for wallet tokens found in sender/body.
  static const walletDisplayNames = <String, String>{
    'paytm': 'Paytm',
    'phonepe': 'PhonePe',
    'amazon pay': 'Amazon Pay',
    'amazon_pay': 'Amazon Pay',
    'mobikwik': 'MobiKwik',
    'freecharge': 'Freecharge',
    'airtel money': 'Airtel Money',
    'airtel_money': 'Airtel Money',
    'ola money': 'Ola Money',
    'ola_money': 'Ola Money',
    'jio money': 'Jio Money',
    'jio_money': 'Jio Money',
    'payzapp': 'PayZapp',
    'oxigen': 'Oxigen',
    'itzcash': 'ItzCash',
    'simpl': 'Simpl',
    'lazypay': 'LazyPay',
    'gpay': 'GPay',
    'google pay': 'GPay',
  };

  /// Card network names → canonical scheme label.
  static const cardSchemeKeywords = <String, String>{
    'visa': 'Visa',
    'mastercard': 'Mastercard',
    'master card': 'Mastercard',
    'maestro': 'Maestro',
    'rupay': 'RuPay',
    'amex': 'Amex',
    'american express': 'Amex',
    'diners': 'Diners',
  };

  /// Specific available-balance / credit-limit phrases (avoid bare "bal"/"available").
  static const availableBalanceKeywords = <String>[
    'avbl bal',
    'available balance',
    'available credit limit',
    'available limit',
    'avbl. credit limit',
    'avbl credit limit',
    'limit available',
    'a/c bal',
    'ac bal',
    'available bal',
    'avl bal',
    'avl lmt',
    'updated balance',
    'total balance',
    'new balance',
    'outstanding',
  ];

  static final RegExp _upiVpaRegex = () {
    final handles = upiHandles
        .map((h) => RegExp.escape(h))
        .join('|');
    return RegExp(
      '([A-Za-z0-9][A-Za-z0-9._+\\-]{0,63})($handles)\\b',
      caseSensitive: false,
    );
  }();

  static final RegExp _currencyAmount = RegExp(
    r'(?:Rs\.?|INR|₹)\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)',
    caseSensitive: false,
  );

  /// First VPA in [text] whose handle is on the allowlist.
  static String? extractUpiVpa(String text) {
    final match = _upiVpaRegex.firstMatch(text);
    if (match == null) return null;
    return '${match.group(1)}${match.group(2)}'.toLowerCase();
  }

  /// True when [value] looks like a VPA with a known handle.
  static bool isKnownUpiVpa(String value) {
    final lower = value.trim().toLowerCase();
    final at = lower.lastIndexOf('@');
    if (at <= 0) return false;
    final handle = lower.substring(at);
    return upiHandles.contains(handle);
  }

  /// Wallet display name if [text] (sender or body) mentions a known provider.
  static String? detectWalletProvider(String text) {
    final lower = text.toLowerCase().trim();

    // Compact DLT sender IDs (no spaces): VM-MOBIKW-S, AD-FRCHRG-S, …
    if (!lower.contains(' ') && lower.length <= 32) {
      const senderHints = <String, String>{
        'mobikw': 'MobiKwik',
        'mbkwik': 'MobiKwik',
        'frchrg': 'Freecharge',
        'amznpay': 'Amazon Pay',
        'amazonpay': 'Amazon Pay',
        'paytmb': 'Paytm',
        'phonepe': 'PhonePe',
        'gpay': 'GPay',
      };
      for (final entry in senderHints.entries) {
        if (lower.contains(entry.key)) return entry.value;
      }
    }

    // Longer / multi-word tokens first.
    final ordered = walletProviders.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final token in ordered) {
      if (token.contains(' ')) {
        if (lower.contains(token)) {
          return walletDisplayNames[token];
        }
      } else if (token.contains('_')) {
        if (lower.contains(token.replaceAll('_', ' ')) ||
            lower.contains(token)) {
          return walletDisplayNames[token];
        }
      } else {
        if (RegExp('\\b${RegExp.escape(token)}\\b', caseSensitive: false)
            .hasMatch(lower)) {
          return walletDisplayNames[token];
        }
      }
    }
    return null;
  }

  /// Card scheme label if mentioned (Visa, Mastercard, RuPay, …).
  static String? detectCardScheme(String text) {
    final lower = text.toLowerCase();
    final ordered = cardSchemeKeywords.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final key in ordered) {
      if (lower.contains(key)) return cardSchemeKeywords[key];
    }
    return null;
  }

  /// Parses available balance / limit after a known keyword, if present.
  static double? extractAvailableBalance(String text) {
    final lower = text.toLowerCase();
    final ordered = availableBalanceKeywords.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final keyword in ordered) {
      final idx = lower.indexOf(keyword);
      if (idx < 0) continue;
      final after = text.substring(idx + keyword.length);
      final match = _currencyAmount.firstMatch(after);
      if (match != null) {
        return double.tryParse(match.group(1)!.replaceAll(',', ''));
      }
      // "10000.00 available" / "Rs.10000 available bal" already handled above;
      // also try bare number right after keyword.
      final bare = RegExp(r'^\s*[:=]?\s*(\d+(?:,\d+)*(?:\.\d{1,2})?)')
          .firstMatch(after);
      if (bare != null) {
        return double.tryParse(bare.group(1)!.replaceAll(',', ''));
      }
    }

    // Amount before keyword: "Rs.10000.00 Avl bal"
    for (final keyword in ordered) {
      final pattern = RegExp(
        '(?:Rs\\.?|INR|₹)\\s*(\\d+(?:,\\d+)*(?:\\.\\d{1,2})?)\\s+'
        '${RegExp.escape(keyword)}',
        caseSensitive: false,
      );
      final match = pattern.firstMatch(text);
      if (match != null) {
        return double.tryParse(match.group(1)!.replaceAll(',', ''));
      }
    }
    return null;
  }

  /// Strips trailing available-balance / limit phrases from merchant-like text.
  static String stripBalanceSuffix(String text) {
    var result = text;
    for (final keyword in availableBalanceKeywords) {
      final pattern = RegExp(
        '[.\\s,;]*${RegExp.escape(keyword)}.*\$',
        caseSensitive: false,
      );
      result = result.replaceAll(pattern, '');
    }
    // Common bank short forms not in the list as full phrases.
    result = result.replaceAll(
      RegExp(r'[.\s,;]*Avl(?:\s+Lmt|\s+Bal)?\b.*$', caseSensitive: false),
      '',
    );
    return result.trim();
  }

  /// Light currency / account-token normalization for match helpers only.
  ///
  /// Does **not** strip `/` globally (would break Paisa's `a/c` patterns).
  static String lightlyNormalize(String message) {
    var s = message.toLowerCase();
    s = s.replaceAll('\n', ' ').replaceAll('\r', ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    // a/c → ac for keyword matching (balance phrases, etc.)
    s = s.replaceAll(RegExp(r'\ba/c\b'), 'ac');
    s = s.replaceAll(RegExp(r'\bacct\b'), 'ac');
    s = s.replaceAll(RegExp(r'\baccount\b'), 'ac');
    // Currency spacing: "rs500" / "inr500" → "rs. 500"
    s = s.replaceAllMapped(
      RegExp(r'\b(rs|inr)(?=\d)', caseSensitive: false),
      (m) => '${m.group(1)}. ',
    );
    s = s.replaceAll(RegExp(r'\brs\s+', caseSensitive: false), 'rs. ');
    s = s.replaceAll(RegExp(r'\binr\s+', caseSensitive: false), 'rs. ');
    s = s.replaceAll(RegExp(r'rs\.\s*', caseSensitive: false), 'rs. ');
    return s.trim();
  }
}
