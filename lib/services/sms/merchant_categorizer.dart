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

  /// P2P/UPI moves, account-to-account, and card-bill payments — Transfer.
  static bool _looksLikeTransfer(String merchant, String haystack) {
    // Bank UPI "trf to MERCHANT" is a completed transfer for any merchant name.
    if (RegExp(r'\btrf to\b', caseSensitive: false).hasMatch(haystack)) {
      return true;
    }

    if (RegExp(r'to a/c\s*[\*x]', caseSensitive: false).hasMatch(haystack)) {
      return true;
    }

    if (haystack.contains('ccbp') ||
        haystack.contains('bbps') ||
        merchant.toLowerCase().contains('ccbp') ||
        merchant.toLowerCase().contains('mobikwikccbp')) {
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

    // ISSUE-13: check transfers BEFORE keyword rules so BBPS/CCBP card-bill
    // debits are not swallowed by the old 'bbps' → bills keyword.
    if (!isCredit && _looksLikeTransfer(merchant, haystack)) {
      return SpendCategory.transfer;
    }

    // Unknown NACH/ECS autopay without an explicit loan signal → bills, not EMI.
    if (!isCredit &&
        RegExp(r'\bnach\b|\becs\b', caseSensitive: false).hasMatch(haystack) &&
        !_hasExplicitLoanSignal(haystack)) {
      return SpendCategory.bills;
    }

    for (final entry in _rules.entries) {
      if (entry.key == SpendCategory.income) continue;
      for (final keyword in entry.value) {
        if (_keywordHits(haystack, keyword)) {
          return entry.key;
        }
      }
    }

    return SpendCategory.other;
  }
}
