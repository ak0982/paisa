/// Result of parsing a single bank SMS body.
class ParsedSmsTransaction {
  const ParsedSmsTransaction({
    required this.amount,
    required this.isCredit,
    required this.merchant,
    required this.bank,
    required this.maskedAccount,
    required this.timestamp,
  });

  final double amount;
  final bool isCredit;
  final String merchant;
  final String bank;
  final String maskedAccount;
  final DateTime timestamp;
}

/// Raw SMS message passed into the parser.
class SmsMessageInput {
  const SmsMessageInput({
    required this.id,
    required this.sender,
    required this.body,
    required this.timestamp,
  });

  final String id;
  final String sender;
  final String body;
  final DateTime timestamp;
}
