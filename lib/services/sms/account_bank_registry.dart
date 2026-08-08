/// Learns which bank owns an account (last 4 digits) from unambiguous SMS,
/// then resolves misleading sender IDs — e.g. ICICI notifies credits into an
/// SBI/HDFC/Slice beneficiary account.
class AccountBankRegistry {
  final Map<String, Map<String, int>> _votes = {};

  /// Imports previously learned votes (e.g. from stored transactions) so an
  /// incremental scan does not start with an empty registry (ISSUE-12).
  void seedVotes(Map<String, Map<String, int>> votes) {
    for (final entry in votes.entries) {
      final bucket = _votes.putIfAbsent(entry.key, () => {});
      for (final bankVote in entry.value.entries) {
        bucket[bankVote.key] = (bucket[bankVote.key] ?? 0) + bankVote.value;
      }
    }
  }

  /// Snapshot of current votes for isolate round-trips / persistence.
  Map<String, Map<String, int>> exportVotes() {
    return {
      for (final entry in _votes.entries)
        entry.key: Map<String, int>.from(entry.value),
    };
  }

  /// Extracts the last four digits from a masked account like `••••0429`.
  static String? last4FromMask(String maskedAccount) {
    final digits = RegExp(r'(\d{4})\s*$').firstMatch(maskedAccount.trim());
    return digits?.group(1);
  }

  /// Records bank hints from SMS where the owning bank is clear.
  ///
  /// Skips ICICI settlement / misleading-sender relays — those announce credits
  /// into another bank's account and must not teach ICICI ownership onto the
  /// beneficiary last-4.
  void learn(String sender, String body) {
    if (isIciciSettlementNotification(sender, body)) return;
    if (isMisleadingSenderBank(sender, body, _bankFromSender(sender) ?? '')) {
      return;
    }

    final bank = _detectUnambiguousBank(sender, body);
    if (bank == null) return;

    for (final last4 in extractAccountLast4s(body)) {
      _votes.putIfAbsent(last4, () => {});
      _votes[last4]![bank] = (_votes[last4]![bank] ?? 0) + 1;
    }
  }

  /// Seeds ownership from discovered accounts (weighted by SMS hits).
  void seedFromDiscoveries(
    Iterable<({String bank, String mask, int smsHits})> discoveries,
  ) {
    for (final d in discoveries) {
      final last4 = last4FromMask(d.mask);
      if (last4 == null) continue;
      if (d.bank.isEmpty || d.bank == 'Bank') continue;
      final weight = d.smsHits < 1 ? 1 : d.smsHits;
      _votes.putIfAbsent(last4, () => {});
      _votes[last4]![d.bank] = (_votes[last4]![d.bank] ?? 0) + weight;
    }
  }

  String? lookup(String last4) {
    final votes = _votes[last4];
    if (votes == null || votes.isEmpty) return null;

    var bestBank = votes.keys.first;
    var bestCount = votes[bestBank]!;
    for (final entry in votes.entries) {
      if (entry.value > bestCount) {
        bestBank = entry.key;
        bestCount = entry.value;
      }
    }
    return bestBank;
  }

  /// Corrects a parsed bank using learned account ownership.
  String resolveBank({
    required String sender,
    required String body,
    required String? accountLast4,
    required String parsedBank,
  }) {
    final explicit = detectExplicitAccountBank(body);
    if (explicit != null) return explicit;

    if (accountLast4 != null) {
      final known = lookup(accountLast4);
      if (known != null) {
        if (isIciciSettlementNotification(sender, body)) return known;
        if (isMisleadingSenderBank(sender, body, parsedBank)) return known;
        // Placeholder / unknown bank on a known last-4 → owning bank.
        if (parsedBank.isEmpty || parsedBank == 'Bank') return known;
      }
    }

    return parsedBank;
  }

  /// ICICI sends LenDenClub repayment alerts for non-ICICI beneficiary accounts.
  static bool isIciciSettlementNotification(String sender, String body) {
    if (!sender.toUpperCase().contains('ICICI')) return false;
    if (RegExp(r'\bicici bank\b', caseSensitive: false).hasMatch(body)) {
      return false;
    }
    return RegExp(
      r'account\s+X+\d{4}\s+has been credited with amount',
      caseSensitive: false,
    ).hasMatch(body);
  }

  static bool isMisleadingSenderBank(
    String sender,
    String body,
    String parsedBank,
  ) {
    if (isIciciSettlementNotification(sender, body)) return true;

    final senderBank = _bankFromSender(sender);
    if (senderBank == null) return false;

    final explicit = detectExplicitAccountBank(body);
    if (explicit != null && explicit != senderBank) return true;

    if (senderBank == parsedBank &&
        body.toLowerCase().contains('lendenclub borrower repayment')) {
      return sender.toUpperCase().contains('ICICI');
    }

    return false;
  }

  /// Bank explicitly named next to the account in the SMS body.
  static String? detectExplicitAccountBank(String body) {
    final lower = body.toLowerCase();
    final trimmed = lower.trim();

    // Slice SFB alerts usually end with " - slice" or say "slice A/c".
    if (RegExp(r'-\s*slice\s*$').hasMatch(trimmed) ||
        RegExp(r'\bslice\s+a/c\b').hasMatch(lower) ||
        RegExp(r'received in slice\b').hasMatch(lower) ||
        RegExp(r'from slice\s+a/c\b').hasMatch(lower)) {
      return 'Slice';
    }

    if (RegExp(r'(?:account|a/c)\s*-\s*sbi\b').hasMatch(lower) ||
        RegExp(r'-sbi\s*$').hasMatch(trimmed) ||
        lower.contains('dear sbi') ||
        lower.contains('sbi upi user')) {
      return 'SBI';
    }
    if (RegExp(r'\bhdfc bank\b').hasMatch(lower)) return 'HDFC';
    if (RegExp(r'\bicici bank\b').hasMatch(lower)) return 'ICICI';
    if (RegExp(r'\baxis bank\b').hasMatch(lower)) return 'Axis';
    if (RegExp(r'\bkotak bank\b').hasMatch(lower)) return 'Kotak';
    if (RegExp(r'\bstate bank\b').hasMatch(lower)) return 'SBI';
    if (RegExp(r'\bhsbc\b').hasMatch(lower)) return 'HSBC';

    return null;
  }

  static String? _detectUnambiguousBank(String sender, String body) {
    final explicit = detectExplicitAccountBank(body);
    if (explicit != null) return explicit;

    return _bankFromSender(sender);
  }

  static String? _bankFromSender(String sender) {
    final s = sender.toUpperCase();
    if (s.contains('HDFC')) return 'HDFC';
    if (s.contains('SBI') || s.contains('SBIN')) return 'SBI';
    if (s.contains('ICICI')) return 'ICICI';
    if (s.contains('AXIS')) return 'Axis';
    if (s.contains('KOTAK')) return 'Kotak';
    if (s.contains('PAYTM')) return 'Paytm';
    if (s.contains('PHONEPE')) return 'PhonePe';
    if (s.contains('YES')) return 'Yes Bank';
    if (s.contains('IDFC')) return 'IDFC';
    if (s.contains('HSBC')) return 'HSBC';
    if (s.contains('SLCEIT') || s.contains('SLCBNK') || s.contains('SLICE')) {
      return 'Slice';
    }
    if (s.contains('LENDEN')) return 'LenDenClub';
    return null;
  }

  /// Pulls likely account suffixes from common Indian bank SMS formats.
  static List<String> extractAccountLast4s(String body) {
    final found = <String>{};
    final patterns = [
      // HSBC: A/c 074-260***-006
      RegExp(
        r'(?:a/c|acct)\s+([\d][\d\-*\s]{3,20}\d)',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:a/c|acct|account|A/C)\s*[Xx*•]*(\d{4})\b',
        caseSensitive: false,
      ),
      RegExp(r'[Xx*•]{2,}(\d{4})\b'),
      RegExp(
        r'(?:a/c|acct|account|A/C)\s*No\.?\s*[Xx*•]*(\d{4})\b',
        caseSensitive: false,
      ),
      RegExp(r'account\s+X+(\d{4})\b', caseSensitive: false),
      RegExp(r'Acct\s+XX(\d+)\b', caseSensitive: false),
      RegExp(r'Bank\s+AC\s+X(\d{4})\b', caseSensitive: false),
      RegExp(
        r'(?:credit\s*card|debit\s+card)\s+[xX*]*(\d{4})\b',
        caseSensitive: false,
      ),
    ];

    for (final pattern in patterns) {
      for (final match in pattern.allMatches(body)) {
        final raw = match.group(1);
        if (raw == null || raw.isEmpty) continue;
        final digits = raw.replaceAll(RegExp(r'\D'), '');
        if (digits.isEmpty) continue;
        final last4 =
            digits.length <= 4 ? digits.padLeft(4, '0') : digits.substring(digits.length - 4);
        if (last4.length == 4) found.add(last4);
      }
    }

    return found.toList();
  }
}
