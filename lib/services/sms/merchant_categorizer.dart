import '../../models/category_info.dart';

/// Maps merchant / SMS keywords to spending categories.
class MerchantCategorizer {
  static const _rules = <SpendCategory, List<String>>{
    SpendCategory.food: [
      'swiggy',
      'zomato',
      'dunzo',
      'bigbasket',
      'blinkit',
      'zepto',
      'dominos',
      'mcdonald',
      'kfc',
      'eatfit',
      'hungerbox',
      'food',
      'restaurant',
      'cafe',
    ],
    SpendCategory.travel: [
      'ola',
      'uber',
      'rapido',
      'irctc',
      'makemytrip',
      'goibibo',
      'redbus',
      'indigo',
      'spicejet',
      'air india',
      'metro',
      'fastag',
      'petrol',
      'fuel',
    ],
    SpendCategory.shopping: [
      'amazon',
      'flipkart',
      'myntra',
      'ajio',
      'meesho',
      'reliance digital',
      'reliance retail',
      'croma',
      'nykaa',
    ],
    SpendCategory.bills: [
      'jio',
      'airtel',
      'vi',
      'vodafone',
      'bsnl',
      'recharge',
      'electricity',
      'bescom',
      'tata power',
      'gas bill',
      'broadband',
      'act fibernet',
      // 'bbps' removed (ISSUE-13): BBPS card-bill debits are transfers, checked
      // via _looksLikeTransfer before the keyword loop.
    ],
    SpendCategory.entertainment: [
      'netflix',
      'hotstar',
      'spotify',
      'prime video',
      'sony liv',
      'bookmyshow',
      'pvr',
      'inox',
    ],
    SpendCategory.emi: [
      'emi of',
      'emi due',
      'emi reminder',
      'home loan',
      'personal loan',
      'car loan',
      'loan instalment',
      'loan installment',
      'loan a/c',
      // Personal NACH merchant strings / "hdfc bank limited" / "tp ach" removed
      // (ISSUE-13) — those misfired every HDFC NACH (SIPs, insurance) as EMI.
    ],
    SpendCategory.health: [
      'apollo',
      'pharmeasy',
      '1mg',
      'practo',
      'medplus',
      'hospital',
      'pharmacy',
    ],
    SpendCategory.atm: [
      'atm',
      'cash withdrawal',
      'cash wdl',
      'atm wdl',
    ],
    SpendCategory.income: [
      'salary',
      'payroll',
      'credited by',
      'neft cr',
      'imps cr',
      'refund',
      'cashback',
      'borrower repayment',
      'repayment',
      'tax refund',
    ],
  };

  /// Short tokens that false-fire as substrings (ola⊂Cola, jio⊂Jiomart, …).
  /// Matched with word boundaries; longer brand names keep substring match so
  /// composites like "IRCTCAutoPe" still hit "irctc".
  static const _wordBoundedKeywords = <String>{
    'ola',
    'jio',
    'food',
    'metro',
    'cafe',
    'atm',
    'vi',
    'fuel',
    'pvr',
    'kfc',
  };

  static final Map<String, RegExp> _boundedPatterns = {
    for (final kw in _wordBoundedKeywords)
      kw: RegExp('\\b${RegExp.escape(kw)}\\b', caseSensitive: false),
  };

  static bool _keywordHits(String haystack, String keyword) {
    final kw = keyword.trim().toLowerCase();
    if (kw.isEmpty) return false;
    final bounded = _boundedPatterns[kw];
    if (bounded != null) return bounded.hasMatch(haystack);
    return haystack.contains(kw);
  }

  static bool _isCreditCardPaymentCredit(String haystack) {
    if (!haystack.contains('credit card') &&
        !haystack.contains('bobcard') &&
        !haystack.contains('bbps')) {
      return false;
    }
    return haystack.contains('bbps') ||
        haystack.contains('credited towards') ||
        haystack.contains('payment of') && haystack.contains('received') ||
        haystack.contains('payment credited');
  }

  static bool _isGenericMerchant(String merchant) {
    final m = merchant.toLowerCase().trim();
    if (m.isEmpty) return true;
    return m == 'transaction' ||
        m == 'credit received' ||
        m == 'transfer' ||
        m.startsWith('trf to ') ||
        m.startsWith('nach');
  }

  /// Card-bill rails — must beat the `bills` keyword loop (ISSUE-13 / R2-1).
  static bool _looksLikeCardBillTransfer(String merchant, String haystack) {
    final m = merchant.toLowerCase();
    return haystack.contains('ccbp') ||
        haystack.contains('bbps') ||
        haystack.contains('ccbbps') ||
        haystack.contains('bbpsbill') ||
        m.contains('ccbp') ||
        m.contains('ccbbps') ||
        m.contains('bbpsbill') ||
        m.contains('mobikwikccbp');
  }

  /// Generic P2P / A2A wording. Runs *after* brand keywords so SBI-style
  /// "trf to SWIGGY" stays food, not Transfer (R2-1).
  static bool _looksLikeGenericTransfer(String merchant, String haystack) {
    if (RegExp(r'\btrf to\b', caseSensitive: false).hasMatch(haystack)) {
      return true;
    }

    if (RegExp(r'to a/c\s*[\*x]', caseSensitive: false).hasMatch(haystack)) {
      return true;
    }

    if (haystack.contains('fund transfer') ||
        haystack.contains('upi transfer')) {
      return true;
    }

    if (_isGenericMerchant(merchant)) {
      if (haystack.contains('neft dr') ||
          haystack.contains('imps dr') ||
          haystack.contains('rtgs dr')) {
        return true;
      }
    }

    return false;
  }

  /// First matching non-income keyword, or null.
  static SpendCategory? _matchNonIncomeKeyword(String haystack) {
    for (final entry in _rules.entries) {
      if (entry.key == SpendCategory.income) continue;
      for (final keyword in entry.value) {
        if (_keywordHits(haystack, keyword)) return entry.key;
      }
    }
    return null;
  }

  /// Wallet / P2P platform credits (completed top-ups), not bank salary.
  static bool _isWalletPlatformCredit(String haystack) {
    if (haystack.contains('available for lending')) return true;
    return RegExp(
      r'credited to your\s+[a-z0-9 .&-]{2,40}\s+account',
      caseSensitive: false,
    ).hasMatch(haystack) &&
        !haystack.contains('savings') &&
        !haystack.contains('a/c') &&
        !RegExp(r'\b(?:hdfc|sbi|icici|axis|kotak|idfc|yes bank)\b')
            .hasMatch(haystack);
  }

  static bool _hasExplicitLoanSignal(String haystack) {
    return haystack.contains('home loan') ||
        haystack.contains('personal loan') ||
        haystack.contains('car loan') ||
        haystack.contains('housing loan') ||
        haystack.contains('loan instalment') ||
        haystack.contains('loan installment') ||
        haystack.contains('loan a/c') ||
        haystack.contains('emi of') ||
        haystack.contains('emi due');
  }

  static SpendCategory categorize({
    required String merchant,
    required String smsBody,
    required bool isCredit,
  }) {
    final haystack = '${merchant.toLowerCase()} ${smsBody.toLowerCase()}';

    // CC bill payment credits are liability reductions, not salary.
    if (isCredit && _isCreditCardPaymentCredit(haystack)) {
      return SpendCategory.transfer;
    }

    if (isCredit && _isWalletPlatformCredit(haystack)) {
      return SpendCategory.transfer;
    }

    if (isCredit) {
      for (final keyword in _rules[SpendCategory.income]!) {
        if (_keywordHits(haystack, keyword)) {
          return SpendCategory.income;
        }
      }
      if (haystack.contains('credited') &&
          !haystack.contains('swiggy') &&
          !haystack.contains('zomato')) {
        return SpendCategory.income;
      }
    }

    // ISSUE-13: CCBP/BBPS before keywords so card-bill debits stay Transfer.
    // R2-1: brand keywords before generic "trf to" so "trf to SWIGGY" is food.
    if (!isCredit && _looksLikeCardBillTransfer(merchant, haystack)) {
      return SpendCategory.transfer;
    }

    final branded = _matchNonIncomeKeyword(haystack);
    if (branded != null) return branded;

    if (!isCredit && _looksLikeGenericTransfer(merchant, haystack)) {
      return SpendCategory.transfer;
    }

    // Unknown NACH/ECS autopay without an explicit loan signal → bills, not EMI.
    if (!isCredit &&
        RegExp(r'\bnach\b|\becs\b', caseSensitive: false).hasMatch(haystack) &&
        !_hasExplicitLoanSignal(haystack)) {
      return SpendCategory.bills;
    }

    return SpendCategory.other;
  }
}
