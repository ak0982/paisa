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
      'vi ',
      'vodafone',
      'bsnl',
      'recharge',
      'electricity',
      'bescom',
      'tata power',
      'gas bill',
      'broadband',
      'act fibernet',
      'bbps',
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
      'nach-',
      'nach ',
      'towards nach',
      'home loan',
      'personal loan',
      'car loan',
      'loan instalment',
      'loan installment',
      'loan a/c',
      'hdfc bank limited',
      'tp ach',
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
        m == 'nach-10-hdfc bank limited kotak bank';
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
        if (haystack.contains(keyword)) {
          return SpendCategory.income;
        }
      }
      if (haystack.contains('credited') &&
          !haystack.contains('swiggy') &&
          !haystack.contains('zomato')) {
        return SpendCategory.income;
      }
    }

    for (final entry in _rules.entries) {
      if (entry.key == SpendCategory.income) continue;
      for (final keyword in entry.value) {
        if (haystack.contains(keyword)) {
          return entry.key;
        }
      }
    }

    if (!isCredit && _looksLikeTransfer(merchant, haystack)) {
      return SpendCategory.transfer;
    }

    return SpendCategory.other;
  }
}
