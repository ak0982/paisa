/// Bank-specific promotional SMS patterns for Indian financial institutions.
///
/// These complement the global promo blocklist. A message is treated as
/// promotional when it matches a bank-specific offer phrase and does not
/// contain a completed transaction signal.
abstract final class BankPromoFilters {
  static final _senderBank = <String, String>{
    'hdfc': 'HDFC',
    'sbi': 'SBI',
    'icici': 'ICICI',
    'axis': 'Axis',
    'kotak': 'Kotak',
    'paytm': 'Paytm',
    'phonepe': 'PhonePe',
  };

  static final _bodyBank = <String, String>{
    'hdfc bank': 'HDFC',
    'hdfc': 'HDFC',
    'state bank': 'SBI',
    'sbi': 'SBI',
    'icici': 'ICICI',
    'axis bank': 'Axis',
    'axis': 'Axis',
    'kotak': 'Kotak',
    'paytm': 'Paytm',
    'phonepe': 'PhonePe',
  };

  /// Per-bank promo / marketing phrases (case-insensitive regex fragments).
  static final _bankPromoPatterns = <String, List<RegExp>>{
    'HDFC': [
      RegExp(r'smartemi', caseSensitive: false),
      RegExp(r'easyemi', caseSensitive: false),
      RegExp(r'10x rewards', caseSensitive: false),
      RegExp(r'millennia offer', caseSensitive: false),
      RegExp(r'payzapp offer', caseSensitive: false),
      RegExp(r'infinia offer', caseSensitive: false),
      RegExp(r'regalia offer', caseSensitive: false),
      RegExp(r'hdfc bank offer', caseSensitive: false),
      RegExp(r'convert to emi', caseSensitive: false),
      RegExp(r'festive offer', caseSensitive: false),
    ],
    'SBI': [
      RegExp(r'yono offer', caseSensitive: false),
      RegExp(r'simplyclick', caseSensitive: false),
      RegExp(r'simplysave', caseSensitive: false),
      RegExp(r'sbi card offer', caseSensitive: false),
      RegExp(r'prime card offer', caseSensitive: false),
      RegExp(r'sbi credit card offer', caseSensitive: false),
      RegExp(r'apply for sbi card', caseSensitive: false),
      RegExp(r'sbi festive offer', caseSensitive: false),
    ],
    'ICICI': [
      RegExp(r'imobile offer', caseSensitive: false),
      RegExp(r'amazon pay icici', caseSensitive: false),
      RegExp(r'coral offer', caseSensitive: false),
      RegExp(r'ascend offer', caseSensitive: false),
      RegExp(r'icici bank offer', caseSensitive: false),
      RegExp(r'icici credit card offer', caseSensitive: false),
      RegExp(r'apply for icici card', caseSensitive: false),
      RegExp(r'emi on card offer', caseSensitive: false),
    ],
    'Axis': [
      RegExp(r'grab deals', caseSensitive: false),
      RegExp(r'axis neo offer', caseSensitive: false),
      RegExp(r'flipkart axis offer', caseSensitive: false),
      RegExp(r'axis bank offer', caseSensitive: false),
      RegExp(r'axis credit card offer', caseSensitive: false),
      RegExp(r'axis rewards offer', caseSensitive: false),
      RegExp(r'myzone offer', caseSensitive: false),
      RegExp(r'ace card offer', caseSensitive: false),
    ],
    'Kotak': [
      RegExp(r'kotak 811 offer', caseSensitive: false),
      RegExp(r'dream different offer', caseSensitive: false),
      RegExp(r'kotak bank offer', caseSensitive: false),
      RegExp(r'kotak credit card offer', caseSensitive: false),
      RegExp(r'811 super offer', caseSensitive: false),
      RegExp(r'kotak festive offer', caseSensitive: false),
    ],
    'Paytm': [
      RegExp(r'cashback offer', caseSensitive: false),
      RegExp(r'refer and earn', caseSensitive: false),
      RegExp(r'scratch card', caseSensitive: false),
      RegExp(r'paytm offer', caseSensitive: false),
      RegExp(r'paytm cashback', caseSensitive: false),
      RegExp(r'claim your reward', caseSensitive: false),
      RegExp(r'limited time offer', caseSensitive: false),
      RegExp(r'paytm postpaid offer', caseSensitive: false),
    ],
    'PhonePe': [
      RegExp(r'cashback offer', caseSensitive: false),
      RegExp(r'refer and earn', caseSensitive: false),
      RegExp(r'scratch card', caseSensitive: false),
      RegExp(r'phonepe offer', caseSensitive: false),
      RegExp(r'phonepe rewards', caseSensitive: false),
      RegExp(r'claim your reward', caseSensitive: false),
      RegExp(r'win upto', caseSensitive: false),
      RegExp(r'phonepe cashback', caseSensitive: false),
    ],
  };

  /// Shared wallet / UPI promo phrases when sender is Paytm or PhonePe.
  static final _walletSharedPromo = [
    RegExp(r'referral bonus', caseSensitive: false),
    RegExp(r'invite friends', caseSensitive: false),
    RegExp(r'gold offer', caseSensitive: false),
  ];

  static String? detectBank({required String sender, required String body}) {
    final s = sender.toLowerCase();
    for (final entry in _senderBank.entries) {
      if (s.contains(entry.key)) return entry.value;
    }

    final b = body.toLowerCase();
    for (final entry in _bodyBank.entries) {
      if (b.contains(entry.key)) return entry.value;
    }
    return null;
  }

  /// Returns true when [body] matches a bank-specific promotional pattern.
  static bool matchesBankPromo({
    required String sender,
    required String body,
  }) {
    final bank = detectBank(sender: sender, body: body);
    if (bank == null) return false;

    final patterns = _bankPromoPatterns[bank];
    if (patterns == null) return false;

    final matchesBank = patterns.any((p) => p.hasMatch(body));
    if (matchesBank) return true;

    if (bank == 'Paytm' || bank == 'PhonePe') {
      return _walletSharedPromo.any((p) => p.hasMatch(body));
    }

    return false;
  }
}
