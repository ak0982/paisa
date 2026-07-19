// ignore_for_file: avoid_print
//
// Coverage diagnostic: lists EVERY (bank, mask) the pipeline turns into an
// account AND every mask-like token found in raw SMS that did NOT become an
// account, with the reason it was dropped. Run with:
//   flutter test test/savings_coverage_diagnostic_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/models/transaction.dart';
import 'package:paisa_app/providers/finance_store.dart';
import 'package:paisa_app/services/sms/account_bank_registry.dart';
import 'package:paisa_app/services/sms/account_discovery.dart';
import 'package:paisa_app/services/sms/merchant_categorizer.dart';
import 'package:paisa_app/services/sms/parsed_sms_transaction.dart';
import 'package:paisa_app/services/sms/sms_parser.dart';
import 'package:paisa_app/services/sms/sms_scan_pipeline.dart';
import 'package:paisa_app/services/sms/transaction_enrichment.dart';

import '../tool/analyze_sms_export.dart' show parseAdbSmsExport;

void main() {
  test('savings account coverage diagnostic', () {
    final home = Platform.environment['HOME'];
    final candidates = [
      '$home/Downloads/my_sms.txt',
      '$home/Downloads/my_sms_live.txt',
    ];

    for (final path in candidates) {
      final file = File(path);
      if (!file.existsSync()) continue;
      print('\n\n########################################################');
      print('# DUMP: $path');
      print('########################################################');
      _analyzeDump(file.readAsStringSync());
    }
  });
}

void _analyzeDump(String raw) {
  final rows = parseAdbSmsExport(raw);

  // --- Build the same inputs finance_store builds during a scan ---
  final registry = AccountBankRegistry();
  for (final r in rows) {
    registry.learn(r.sender, r.body);
  }

  // Discoveries: AccountDiscovery over every row (Pass 1 in sms_reader_service).
  final rawDiscoveries = <DiscoveredAccount>[];
  for (final r in rows) {
    final d = AccountDiscovery.discover(sender: r.sender, body: r.body);
    if (d != null) rawDiscoveries.add(d);
  }
  final discoveries = mergeDiscoveries(rawDiscoveries).values.toList();

  // Transactions: mirror finance_store._runSync per-hit transformation.
  final transactions = <Transaction>[];
  for (final r in rows) {
    final input = SmsMessageInput(
      id: '${r.row}',
      sender: r.sender,
      body: r.body,
      timestamp: DateTime.fromMillisecondsSinceEpoch(r.dateMs),
    );
    if (!SmsScanPipeline.process(input).isParsed) continue;
    final parsed = SmsParser.parseTransaction(input, registry: registry);
    if (parsed == null) continue;

    final category = MerchantCategorizer.categorize(
      merchant: parsed.merchant,
      smsBody: r.body,
      isCredit: parsed.isCredit,
    );
    final mask = TransactionEnrichment.resolveMaskedAccount(
      parsedMask: parsed.maskedAccount,
      sender: r.sender,
      body: r.body,
    );
    var bank = parsed.bank;
    var displayMask = mask;
    final kind = TransactionEnrichment.resolveAccountKind(
      bank: bank,
      mask: mask,
      body: r.body,
      discoveries: discoveries,
    );
    if (kind == AccountKind.loan) {
      final loan = TransactionEnrichment.resolveLoanDisplay(
        body: r.body,
        parsedBank: bank,
        parsedMask: mask,
        discoveries: discoveries,
      );
      bank = loan.bank;
      if (loan.mask.isNotEmpty) displayMask = loan.mask;
    } else if (kind == AccountKind.creditCard) {
      final cc = TransactionEnrichment.resolveCreditCardDisplay(
        body: r.body,
        parsedBank: bank,
        parsedMask: mask,
        discoveries: discoveries,
      );
      bank = cc.bank;
      if (cc.mask.isNotEmpty) displayMask = cc.mask;
    }
    final merchant = TransactionEnrichment.improveMerchant(
      merchant: parsed.merchant,
      body: r.body,
      isCredit: parsed.isCredit,
      accountKind: kind,
    );

    transactions.add(
      Transaction(
        id: 'sms_${r.row}',
        smsId: '${r.row}',
        merchant: merchant,
        bank: bank,
        maskedAccount: displayMask,
        category: category,
        amount: parsed.amount,
        isCredit: parsed.isCredit,
        timestamp: input.timestamp,
        accountKind: kind,
      ),
    );
  }

  final store = FinanceStore()
    ..seedDiscoveredAccounts(discoveries)
    ..seedTransactions(transactions);

  final accounts = store.bankAccounts();

  // --- Report: final account list per kind ---
  print('\n=== FINAL ACCOUNTS (${accounts.length} total) ===');
  final byKind = <AccountKind, List<String>>{
    AccountKind.savings: [],
    AccountKind.creditCard: [],
    AccountKind.loan: [],
  };
  for (final a in accounts) {
    byKind[a.kind]!.add(
      '  ${a.name.padRight(24)} ${a.mask}  '
      'in=${a.receivedTotal.toStringAsFixed(0)} '
      'out=${a.spentTotal.toStringAsFixed(0)} '
      'activity=${a.activityCount}',
    );
  }
  for (final kind in AccountKind.values) {
    print('${_kindName(kind)} (${byKind[kind]!.length}):');
    for (final line in byKind[kind]!) {
      print(line);
    }
  }

  // --- Report: dropped mask candidates + reason ---
  //
  // Enumerate every mask-like account token that appears in an SMS that looks
  // like it references a bank ACCOUNT (savings), then check which of those
  // (bank, mask) pairs never became an account and why.
  final surfacedMasks = accounts.map((a) => a.mask).toSet();
  final txnMasks = transactions.map((t) => t.maskedAccount).toSet();
  final discoveryMasks = discoveries.map((d) => d.mask).toSet();

  // Candidate masks seen in savings-ish SMS wording, with the strongest bank
  // and a representative body.
  final candidates = <String, _MaskCandidate>{};
  for (final r in rows) {
    final body = r.body.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ');
    if (!_looksLikeAccountSms(body)) continue;
    for (final last4 in _accountLast4Tokens(body)) {
      final mask = '••••$last4';
      final bank = _bankGuess(r.sender, body);
      final c = candidates.putIfAbsent(
        mask,
        () => _MaskCandidate(mask: mask),
      );
      c.count++;
      if (bank != null) c.bankVotes[bank] = (c.bankVotes[bank] ?? 0) + 1;
      c.sampleBody ??= body.length > 130 ? body.substring(0, 130) : body;
      c.sampleSender ??= r.sender;
    }
  }

  final dropped = <String>[];
  for (final c in candidates.values) {
    if (surfacedMasks.contains(c.mask)) continue;
    if (c.count < 2) continue; // ignore one-off / junk tokens
    final bank = c.dominantBank;
    final reason = _dropReason(
      mask: c.mask,
      bank: bank,
      inTxns: txnMasks.contains(c.mask),
      inDiscovery: discoveryMasks.contains(c.mask),
      discoveries: discoveries,
      transactions: transactions,
    );
    dropped.add(
      '  ${c.mask}  bank=${bank ?? "?"}  seen=${c.count}  '
      'sender=${c.sampleSender}\n'
      '      reason: $reason\n'
      '      e.g.: ${c.sampleBody}',
    );
  }
  dropped.sort();
  print('\n=== DROPPED ACCOUNT-MASK CANDIDATES (${dropped.length}) ===');
  print('(masks referenced in >=2 account-like SMS that never became an account)');
  for (final d in dropped) {
    print(d);
  }
}

class _MaskCandidate {
  _MaskCandidate({required this.mask});
  final String mask;
  int count = 0;
  final bankVotes = <String, int>{};
  String? sampleBody;
  String? sampleSender;

  String? get dominantBank {
    if (bankVotes.isEmpty) return null;
    return bankVotes.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }
}

/// SMS that references a bank savings account (not a card/loan/OTP/promo).
bool _looksLikeAccountSms(String body) {
  final lower = body.toLowerCase();
  if (lower.length < 20) return false;
  if (SmsParser.isOtpOnly(body)) return false;
  if (lower.contains('credit card') || lower.contains('card ending')) {
    return false;
  }
  // Must mention an account and money-movement / balance wording.
  final hasAccount = RegExp(
    r'\b(a/c|a/c\.|ac\b|acct|account|savings)\b',
    caseSensitive: false,
  ).hasMatch(lower);
  if (!hasAccount) return false;
  return RegExp(
    r'(credited|debited|deposited|withdrawn|received|salary|interest|'
    r'bal[:\s]|balance|neft|imps|upi|rtgs)',
    caseSensitive: false,
  ).hasMatch(lower);
}

/// Every plausible masked account last-4 in the body (X**1234, A/c 1234, etc.).
Set<String> _accountLast4Tokens(String body) {
  final out = <String>{};
  final patterns = [
    RegExp(r'(?:a/c|acct|account|ac)\s*(?:no\.?)?\s*[Xx*•]+(\d{4,})',
        caseSensitive: false),
    RegExp(r'(?:a/c|acct|account)\s*(?:no\.?)?\s*(?:xx|XX)(\d{4})',
        caseSensitive: false),
    RegExp(r'savings\s+a/?c\s*[Xx*•]*(\d{4,})', caseSensitive: false),
    RegExp(r'[Xx*•]{2,}(\d{4,})', caseSensitive: false),
  ];
  for (final p in patterns) {
    for (final m in p.allMatches(body)) {
      final digits = m.group(1)!;
      final last4 = digits.substring(digits.length - 4);
      if (RegExp(r'^\d{4}$').hasMatch(last4)) {
        final n = int.tryParse(last4);
        if (n != null && n >= 2015 && n <= 2035) continue; // year-like
        out.add(last4);
      }
    }
  }
  return out;
}

String? _bankGuess(String sender, String body) {
  final h = '${sender.toUpperCase()} ${body.toUpperCase()}';
  if (h.contains('HDFC')) return 'HDFC';
  if (h.contains('SBICRD')) return 'SBI';
  if (h.contains('SBI') || h.contains('CBSSBI')) return 'SBI';
  if (h.contains('ICICI')) return 'ICICI';
  if (h.contains('AXIS')) return 'Axis';
  if (h.contains('KOTAK')) return 'Kotak';
  if (h.contains('IDFC')) return 'IDFC';
  if (h.contains('YES')) return 'Yes Bank';
  if (h.contains('INDUS')) return 'IndusInd';
  if (h.contains('PNB')) return 'PNB';
  if (h.contains('CANARA')) return 'Canara';
  if (h.contains('BARODA') || h.contains('BOBCARD')) return 'Bank of Baroda';
  if (h.contains('FEDBNK') || h.contains('FEDERAL') || h.contains('FEDFIB') ||
      h.contains('MYJPTR') || h.contains('JUPITER')) {
    return 'Federal';
  }
  return null;
}

String _dropReason({
  required String mask,
  required String? bank,
  required bool inTxns,
  required bool inDiscovery,
  required List<DiscoveredAccount> discoveries,
  required List<Transaction> transactions,
}) {
  const realBanks = {
    'HDFC', 'SBI', 'ICICI', 'Axis', 'Kotak', 'Yes Bank',
    'IndusInd', 'PNB', 'Canara', 'Bank of Baroda', 'IDFC',
  };
  if (!inTxns && !inDiscovery) {
    return 'mask never extracted by parser/discovery (regex gap) — '
        'no transaction row and no discovery carry mask $mask';
  }
  if (bank != null && !realBanks.contains(bank)) {
    return 'bank "$bank" not in _realBanks allowlist → savings account dropped';
  }
  if (!inTxns && inDiscovery) {
    final d = discoveries.firstWhere((d) => d.mask == mask);
    if (d.smsHits < 2) {
      return 'only a single discovery SMS (smsHits=${d.smsHits}) and no parsed '
          'transaction → dropped by "smsHits < 2" savings gate';
    }
    return 'discovery present but bank not real or wallet-filtered';
  }
  // In transactions but not surfaced.
  final txns = transactions.where((t) => t.maskedAccount == mask).toList();
  final banks = txns.map((t) => t.bank).toSet();
  if (banks.every((b) => !realBanks.contains(b))) {
    return 'transactions exist but resolved bank(s)=$banks not in _realBanks '
        '→ _isAccountTransaction(savings) rejects them';
  }
  return 'transactions exist (banks=$banks) but classified non-savings by '
      'balanced voting, or filtered — investigate';
}

String _kindName(AccountKind k) => switch (k) {
      AccountKind.savings => 'SAVINGS',
      AccountKind.creditCard => 'CREDIT CARD',
      AccountKind.loan => 'LOAN',
    };
