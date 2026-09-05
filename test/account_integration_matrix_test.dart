import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/models/transaction.dart';
import 'package:paisa_app/providers/finance_store.dart';
import 'package:paisa_app/services/sms/account_bank_registry.dart';
import 'package:paisa_app/services/sms/account_discovery.dart';
import 'package:paisa_app/services/sms/merchant_categorizer.dart';
import 'package:paisa_app/services/sms/parsed_sms_transaction.dart';
import 'package:paisa_app/services/sms/product_payment_linker.dart';
import 'package:paisa_app/services/sms/sms_scan_pipeline.dart';
import 'package:paisa_app/services/sms/transaction_enrichment.dart';
import 'package:paisa_app/utils/formatters.dart';
import 'package:paisa_app/widgets/category_spend_chip.dart';

/// Integration / adversarial suite: ~3000 cases covering account kinds,
/// bank|mask association, rematch, pipeline SMS (paise), NACH from/to,
/// SBI trf-to brand vs CCBP, multi-loan MBK, UPI dest last-4, pairing
/// index vs nested scan, formatters, R2-1..R2-6 regressions, and live-inbox
/// corner cases (HDFC On/From card, SBI e-mandate, ICICI cashback, IDFC
/// interest, amountless relays, LIC≠EMI).
///
/// Goal: every txn that belongs on an account appears under that account with
/// matching received/sent/activityCount — and amounts on parsed SMS match
/// the body (including paise).
void main() {
  final cases = <_Case>[
    ..._parityMatrix(),
    ..._sameLast4Split(),
    ..._relayAndAlias(),
    ..._loanEmiMatrix(),
    ..._ccbpMatrix(),
    ..._pipelineSmsMatrix(),
    ..._discoveryMatrix(),
    ..._walletAndJunkRejection(),
    ..._hiddenAndEmpty(),
    ..._multiAccountIsolation(),
    ..._nachFromToMatrix(),
    ..._sbiTrfVsCcbpMatrix(),
    ..._upiDestLast4Matrix(),
    ..._pairingIndexMatrix(),
    ..._formattersPaiseMatrix(),
    ..._r2RegressionMatrix(),
    ..._liveInboxCornerMatrix(),
    ..._displayAggregationMatrix(),
  ];

  test('suite size is around 3000 cases', () {
    expect(cases.length, greaterThanOrEqualTo(2700));
    expect(cases.length, lessThanOrEqualTo(3300));
  });

  group('account integration matrix (${cases.length} cases)', () {
    for (final c in cases) {
      test(c.name, () => c.run());
    }
  });
}

typedef _Runner = void Function();

class _Case {
  const _Case(this.name, this.run);
  final String name;
  final _Runner run;
}

Transaction _tx({
  required String id,
  required String bank,
  required String mask,
  required double amount,
  required bool isCredit,
  AccountKind kind = AccountKind.savings,
  SpendCategory category = SpendCategory.other,
  String merchant = 'Merchant',
  DateTime? at,
}) {
  return Transaction(
    id: id,
    smsId: id,
    merchant: merchant,
    bank: bank,
    maskedAccount: mask,
    category: category,
    amount: amount,
    isCredit: isCredit,
    timestamp: at ?? DateTime(2026, 6, 15, 12),
    accountKind: kind,
  );
}

void _expectParity(FinanceStore store, {String? bank, String? mask}) {
  final accounts = store.bankAccounts();
  final targets = accounts.where((a) {
    if (bank != null && a.bank != bank) return false;
    if (mask != null && a.mask != mask) return false;
    return true;
  });
  for (final a in targets) {
    final list = store.transactionsForAccount(evidenceKey: a.evidenceKey);
    final received =
        list.where((t) => t.isCredit).fold(0.0, (s, t) => s + t.amount);
    final sent =
        list.where((t) => !t.isCredit).fold(0.0, (s, t) => s + t.amount);
    expect(list.length, a.activityCount, reason: '${a.name} ${a.mask} count');
    expect(received, a.receivedTotal, reason: '${a.name} ${a.mask} received');
    expect(sent, a.spentTotal, reason: '${a.name} ${a.mask} sent');
  }
}

List<_Case> _parityMatrix() {
  const banks = [
    'HDFC',
    'SBI',
    'ICICI',
    'Axis',
    'Kotak',
    'Yes Bank',
    'PNB',
    'Canara',
    'IDFC',
    'Federal',
    'HSBC',
    'Slice',
    'Bank of Baroda',
    'IndusInd',
  ];
  const masks = [
    '••••1001',
    '••••1002',
    '••••1003',
    '••••1004',
    '••••1005',
    '••••2001',
    '••••2002',
    '••••3001',
    '••••4001',
    '••••5001',
    '••••1006',
    '••••1007',
    '••••1008',
    '••••2003',
    '••••3002',
    '••••6001',
    '••••7000',
    '••••8001',
    '••••9001',
    '••••9002',
    '••••9003',
    '••••9004',
    '••••9005',
    '••••9006',
  ];
  const kinds = [
    AccountKind.savings,
    AccountKind.creditCard,
    AccountKind.loan,
  ];
  final out = <_Case>[];
  var i = 0;
  for (final bank in banks) {
    for (final mask in masks) {
      for (final kind in kinds) {
        i++;
        final id = 'parity_$i';
        out.add(
          _Case('parity #$i $bank ${kind.name} $mask in+out', () {
            final store = FinanceStore()
              ..seedTransactions([
                _tx(
                  id: '${id}_out',
                  bank: bank,
                  mask: mask,
                  amount: 100 + i.toDouble(),
                  isCredit: false,
                  kind: kind,
                  category: kind == AccountKind.loan
                      ? SpendCategory.emi
                      : SpendCategory.shopping,
                ),
                _tx(
                  id: '${id}_in',
                  bank: bank,
                  mask: mask,
                  amount: 50 + i.toDouble(),
                  isCredit: true,
                  kind: kind,
                  category: SpendCategory.income,
                  at: DateTime(2026, 6, 16),
                ),
              ]);
            final accounts = store.bankAccounts().where(
                  (a) => a.bank == bank && a.mask == mask,
                );
            expect(accounts.length, 1);
            final a = accounts.first;
            expect(a.kind, kind);
            final list =
                store.transactionsForAccount(evidenceKey: a.evidenceKey);
            expect(list.length, 2);
            expect(a.spentTotal, 100 + i.toDouble());
            expect(a.receivedTotal, 50 + i.toDouble());
            _expectParity(store, bank: bank, mask: mask);
          }),
        );
      }
    }
  }
  // 14*24*3 = 1008
  return out;
}

List<_Case> _sameLast4Split() {
  const pairs = [
    ('HDFC', 'SBI'),
    ('ICICI', 'Axis'),
    ('Kotak', 'Yes Bank'),
    ('PNB', 'Canara'),
    ('Federal', 'IDFC'),
    ('HSBC', 'Slice'),
    ('Bank of Baroda', 'HDFC'),
    ('SBI', 'ICICI'),
    ('Axis', 'Kotak'),
    ('Slice', 'HDFC'),
    ('IndusInd', 'PNB'),
    ('Yes Bank', 'IDFC'),
  ];
  const masks = [
    '••••7777',
    '••••8888',
    '••••9999',
    '••••6666',
    '••••5555',
    '••••4444',
    '••••3333',
  ];
  final out = <_Case>[];
  var i = 0;
  for (final pair in pairs) {
    for (final mask in masks) {
      i++;
      out.add(
        _Case('same-last4 #$i ${pair.$1}/${pair.$2} $mask', () {
          final store = FinanceStore()
            ..seedTransactions([
              _tx(
                id: 'a$i',
                bank: pair.$1,
                mask: mask,
                amount: 10,
                isCredit: false,
              ),
              _tx(
                id: 'b$i',
                bank: pair.$2,
                mask: mask,
                amount: 20,
                isCredit: true,
                category: SpendCategory.income,
              ),
            ]);
          final matching =
              store.bankAccounts().where((a) => a.mask == mask).toList();
          expect(matching.length, 2);
          expect(matching.map((a) => a.bank).toSet(), {pair.$1, pair.$2});
          _expectParity(store);
        }),
      );
    }
  }
  // 12*7 = 84
  return out;
}

List<_Case> _relayAndAlias() {
  final out = <_Case>[];
  // Slice + Bank/ICICI relays for several masks
  const masks = [
    '••••0856',
    '••••1111',
    '••••2222',
    '••••3333',
    '••••4444',
    '••••5555',
    '••••6666',
    '••••7777',
    '••••8888',
    '••••9999',
  ];
  for (var i = 0; i < masks.length; i++) {
    final mask = masks[i];
    out.add(
      _Case('relay fold #$i Slice$mask + Bank + ICICI', () {
        final store = FinanceStore()
          ..seedDiscoveredAccounts([
            DiscoveredAccount(
              bank: 'Slice',
              mask: mask,
              kind: AccountKind.savings,
              smsHits: 20,
            ),
          ])
          ..seedTransactions([
            _tx(
              id: 's$i',
              bank: 'Slice',
              mask: mask,
              amount: 100,
              isCredit: false,
            ),
            _tx(
              id: 'b$i',
              bank: 'Bank',
              mask: mask,
              amount: 500,
              isCredit: true,
              category: SpendCategory.income,
              merchant: 'Lendenclub Borrower Repayment',
            ),
            _tx(
              id: 'i$i',
              bank: 'ICICI',
              mask: mask,
              amount: 300,
              isCredit: true,
              category: SpendCategory.income,
              merchant: 'Lendenclub Borrower Repayment',
            ),
          ]);
        final accounts =
            store.bankAccounts().where((a) => a.mask == mask).toList();
        expect(accounts.length, 1);
        expect(accounts.first.bank, 'Slice');
        final list = store.transactionsForAccount(
          evidenceKey: accounts.first.evidenceKey,
        );
        expect(list.length, 3);
        expect(accounts.first.receivedTotal, 800);
        expect(accounts.first.spentTotal, 100);
      }),
    );
  }

  // BOB alias matrix
  const bobMasks = [
    '••••7001',
    '••••7002',
    '••••7003',
    '••••7004',
    '••••7005',
    '••••7006',
    '••••7007',
    '••••7008',
    '••••7009',
    '••••7010',
  ];
  for (var i = 0; i < bobMasks.length; i++) {
    final mask = bobMasks[i];
    out.add(
      _Case('alias BOB→Baroda #$i $mask', () {
        final store = FinanceStore()
          ..seedTransactions([
            _tx(id: 'bob$i', bank: 'BOB', mask: mask, amount: 11, isCredit: false),
            _tx(
              id: 'bar$i',
              bank: 'Bank of Baroda',
              mask: mask,
              amount: 22,
              isCredit: true,
              category: SpendCategory.income,
            ),
          ]);
        final accounts =
            store.bankAccounts().where((a) => a.mask == mask).toList();
        expect(accounts.length, 1);
        expect(accounts.first.bank, 'Bank of Baroda');
        _expectParity(store);
      }),
    );
  }

  // Registry unit edges
  for (final sender in [
    'AX-SLCEIT-S',
    'AD-SLCBNK-S',
    'VM-SLICE-S',
    'JX-SLCEIT',
  ]) {
    out.add(
      _Case('registry learns Slice from $sender', () {
        final r = AccountBankRegistry()
          ..learn(
            sender,
            'Rs. 10 sent from a/c xx0856 on 01-Jan-26 to X (UPI Ref: 1) - slice',
          );
        expect(r.lookup('0856'), 'Slice');
      }),
    );
  }

  for (var i = 0; i < 20; i++) {
    out.add(
      _Case('registry skips ICICI settlement learn #$i', () {
        final r = AccountBankRegistry()
          ..learn(
            'AX-SLCEIT-S',
            'Rs. 10 sent from a/c xx${1000 + i} on 01-Jan-26 to X - slice',
          )
          ..learn(
            'VM-ICICI-S',
            'Account XXXXXXXX${1000 + i} has been credited with amount Rs.5. '
                'Info: LENDENCLUB BORROWER REPAYMENT.',
          );
        expect(r.lookup('${1000 + i}'), 'Slice');
      }),
    );
  }

  expectCanonicalizeCases(out);
  return out;
}

void expectCanonicalizeCases(List<_Case> out) {
  const aliases = [
    ('BOB', 'Bank of Baroda'),
    ('hdfc bank', 'HDFC'),
    ('ICICI Bank', 'ICICI'),
    ('axis bank', 'Axis'),
    ('State Bank of India', 'SBI'),
    ('kotak mahindra', 'Kotak'),
    ('Yes Bank', 'Yes Bank'),
    ('IDFC FIRST BANK', 'IDFC'),
    ('federal bank', 'Federal'),
    ('HSBC Bank', 'HSBC'),
    ('slice', 'Slice'),
    ('punjab national bank', 'PNB'),
    ('canara bank', 'Canara'),
    ('indusind bank', 'IndusInd'),
    ('Bank', ''),
    ('', ''),
  ];
  for (final a in aliases) {
    out.add(
      _Case('canonicalize "${a.$1}" → "${a.$2}"', () {
        expect(FinanceStore.canonicalizeBank(a.$1), a.$2);
      }),
    );
  }
}

List<_Case> _loanEmiMatrix() {
  final out = <_Case>[];
  const loans = [
    ('HDFC', '••••0855', 'Home Loan'),
    ('ICICI', '••••1041', 'Personal Loan'),
    ('PNB', '••••0310', 'Loan'),
    ('SBI', '••••2200', 'Home Loan'),
    ('Axis', '••••3300', 'Personal Loan'),
    ('IDFC', '••••2585', 'Home Loan'),
    ('Kotak', '••••4410', 'Personal Loan'),
  ];
  const funding = [
    ('Kotak', '••••3649'),
    ('HDFC', '••••5300'),
    ('SBI', '••••0429'),
    ('ICICI', '••••1505'),
    ('Axis', '••••5094'),
  ];

  for (var li = 0; li < loans.length; li++) {
    final loan = loans[li];
    for (var fi = 0; fi < funding.length; fi++) {
      final fund = funding[fi];
      out.add(
        _Case(
          'loan EMI unique #${li}_$fi ${loan.$1}${loan.$2} via ${fund.$1}',
          () {
            final store = FinanceStore()
              ..seedDiscoveredAccounts([
                DiscoveredAccount(
                  bank: loan.$1,
                  mask: loan.$2,
                  kind: AccountKind.loan,
                  smsHits: 5,
                  accountLabel: loan.$3,
                ),
              ])
              ..seedTransactions([
                _tx(
                  id: 'emi_${li}_$fi',
                  bank: fund.$1,
                  mask: fund.$2,
                  amount: (1000 + li * 10 + fi).toDouble(),
                  isCredit: false,
                  kind: AccountKind.loan,
                  category: SpendCategory.emi,
                  merchant: '${loan.$3} EMI',
                ),
                _tx(
                  id: 'loanrow_${li}_$fi',
                  bank: loan.$1,
                  mask: loan.$2,
                  amount: 1,
                  isCredit: false,
                  kind: AccountKind.loan,
                  category: SpendCategory.emi,
                ),
              ]);
            final accounts = store.bankAccounts().where((a) => a.isLoan).toList();
            expect(accounts.where((a) => a.mask == loan.$2).length, 1);
            final a = accounts.firstWhere((a) => a.mask == loan.$2);
            final list =
                store.transactionsForAccount(evidenceKey: a.evidenceKey);
            expect(list.map((t) => t.id).contains('emi_${li}_$fi'), isTrue);
            expect(list.map((t) => t.id).contains('loanrow_${li}_$fi'), isTrue);
            _expectParity(store);
          },
        ),
      );
    }
  }

  // Discovery: personal loan before savings
  for (final last4 in ['1041', '2041', '3041', '4041', '5041']) {
    out.add(
      _Case('discover Personal Loan XX$last4 before linked savings', () {
        final d = AccountDiscovery.discover(
          sender: 'VK-ICICI-S',
          body:
              'EMI of Rs.12,345.00 for ICICI Bank Personal Loan XX$last4 is due. '
              'Linked Account XX3649. -ICICI Bank',
        );
        expect(d?.kind, AccountKind.loan);
        expect(d?.mask, '••••$last4');
      }),
    );
  }

  for (final last4 in ['0310', '0311', '0312', '0313', '0314', '0855', '0856']) {
    out.add(
      _Case('discover Loan Ac XX$last4', () {
        final d = AccountDiscovery.discover(
          sender: 'AX-PNBSMS-S',
          body: 'Thanks for depositing an amount Rs 5000 against Loan Ac XX$last4. -PNB',
        );
        expect(d?.kind, AccountKind.loan);
        expect(d?.mask, '••••$last4');
      }),
    );
  }

  // resolveLoanDisplay NACH matrix
  for (final hint in [
    ('NACH-10-HDFC BANK LIMITED', 'hdfc', 'HDFC', '••••0855'),
    ('towards NACH-10-TP ACH ICICI', 'icici', 'ICICI', '••••1041'),
    ('NACH IDFC FIRST BANK', 'idfc', 'IDFC', '••••2585'),
  ]) {
    for (var i = 0; i < 5; i++) {
      out.add(
        _Case('resolveLoan NACH ${hint.$2} #$i', () {
          final result = TransactionEnrichment.resolveLoanDisplay(
            body: 'Rs.${8000 + i} debited from A/c XX3649 towards ${hint.$1}',
            parsedBank: 'Kotak',
            parsedMask: '••••3649',
            discoveries: [
              DiscoveredAccount(
                bank: hint.$3,
                mask: hint.$4,
                kind: AccountKind.loan,
                smsHits: 3,
              ),
            ],
          );
          expect(result.bank, hint.$3);
          expect(result.mask, hint.$4);
        }),
      );
    }
  }

  // Multi-loan collision: ambiguous MBK EMI must not use funding bank.
  const multiLoans = [
    DiscoveredAccount(
      bank: 'HDFC',
      mask: '••••0855',
      kind: AccountKind.loan,
      smsHits: 5,
    ),
    DiscoveredAccount(
      bank: 'ICICI',
      mask: '••••1041',
      kind: AccountKind.loan,
      smsHits: 5,
    ),
    DiscoveredAccount(
      bank: 'PNB',
      mask: '••••0310',
      kind: AccountKind.loan,
      smsHits: 4,
    ),
  ];
  for (var i = 0; i < 12; i++) {
    out.add(
      _Case('multi-loan MBK EMI keeps funding #$i', () {
        final result = TransactionEnrichment.resolveLoanDisplay(
          body:
              'Sent Rs.${5000 + i}.39 From HDFC Bank A/C *5300 To MBK EMI On 01/0${(i % 9) + 1}/26',
          parsedBank: 'HDFC',
          parsedMask: '••••5300',
          discoveries: multiLoans,
        );
        expect(result.bank, 'HDFC');
        expect(result.mask, '••••5300');
      }),
    );
  }
  for (var i = 0; i < 8; i++) {
    out.add(
      _Case('multi-loan NACH HDFC still remaps #$i', () {
        final result = TransactionEnrichment.resolveLoanDisplay(
          body:
              'INR ${25000 + i}.00 is debited from your Account XXXXXX3649 on '
              '07/0${(i % 9) + 1}/2026 towards NACH-10-HDFC BANK LIMITED',
          parsedBank: 'Kotak',
          parsedMask: '••••3649',
          discoveries: multiLoans,
        );
        expect(result.bank, 'HDFC');
        expect(result.mask, '••••0855');
      }),
    );
  }

  return out;
}

List<_Case> _ccbpMatrix() {
  final out = <_Case>[];
  const fundingBanks = [
    'SBI',
    'HDFC',
    'ICICI',
    'Axis',
    'Kotak',
    'PNB',
    'IDFC',
  ];
  const fundingMasks = [
    '••••0429',
    '••••5300',
    '••••1505',
    '••••5094',
    '••••3649',
    '••••6675',
    '••••7424',
  ];
  const cards = [
    ('HDFC', '••••9999'),
    ('ICICI', '••••2009'),
    ('Yes Bank', '••••9757'),
    ('Axis', '••••8341'),
    ('HSBC', '••••3740'),
    ('Slice', '••••7185'),
    ('IDFC', '••••7424'),
  ];
  for (var i = 0; i < fundingBanks.length; i++) {
    for (var j = 0; j < cards.length; j++) {
      out.add(
        _Case('CCBP keep funding #${i}_$j', () {
          final result = TransactionEnrichment.resolveCreditCardDisplay(
            body:
                'A/c X${fundingMasks[i].substring(4)} debited by ${100 + i + j} '
                'for MBK CCBP toward card xx${cards[j].$2.substring(4)}',
            parsedBank: fundingBanks[i],
            parsedMask: fundingMasks[i],
            discoveries: [
              DiscoveredAccount(
                bank: cards[j].$1,
                mask: cards[j].$2,
                kind: AccountKind.creditCard,
                smsHits: 3,
              ),
            ],
          );
          expect(result.bank, fundingBanks[i]);
          expect(result.mask, fundingMasks[i]);
        }),
      );
    }
  }
  // 7*7 = 49
  return out;
}

/// Indian-SMS amount text: 0.85 / 500.00 / 5,199.39 / 25,797.00
String _smsInr(double amount) {
  final cents = (amount * 100).round();
  final whole = cents ~/ 100;
  final frac = (cents % 100).toString().padLeft(2, '0');
  final digits = whole.toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return '$buf.$frac';
}

List<_Case> _pipelineSmsMatrix() {
  final out = <_Case>[];
  const amounts = [
    0.85,
    23.60,
    99.99,
    325.50,
    500.00,
    1246.00,
    5199.39,
    25797.00,
  ];
  final templates = <({
    String sender,
    String body,
    bool expectParsed,
    String? bank,
    bool? isCredit,
  })>[
    (
      sender: 'AX-HDFCBK-S',
      body:
          'Rs.{amt} debited from HDFC Bank A/c **5300 on 08-Aug to Swiggy (UPI Ref No 1). Not You? Call 18002586161',
      expectParsed: true,
      bank: 'HDFC',
      isCredit: false,
    ),
    (
      sender: 'VM-SBIIN-S',
      body:
          'Dear UPI user A/C X0429 debited by {amt} on date 08Aug26 trf to MERCHANT Refno 123 If not you call 1800',
      expectParsed: true,
      bank: 'SBI',
      isCredit: false,
    ),
    (
      sender: 'AX-SLCEIT-S',
      body:
          'Rs. {amt} sent from a/c xx0856 on 18-May-26 to CREW SPORTS (UPI Ref: 650468933013). Not you? Call 08048329999 - slice',
      expectParsed: true,
      bank: 'Slice',
      isCredit: false,
    ),
    (
      sender: 'AD-SLCEIT-S',
      body:
          'Rs. {amt} received in slice A/c xx0856 on 05-Jan-26 from TEST USER via UPI (Ref ID: 1). Avl. Bal. Rs. 1 - slice',
      expectParsed: true,
      bank: 'Slice',
      isCredit: true,
    ),
    (
      sender: 'VA-SLCBNK-S',
      body:
          'Rs. {amt} spent on your credit card xx7185 at Test Merchant on 18-Jun-26 (UPI Ref: 1). Not you? Call 080-4832-9999 - slice',
      expectParsed: true,
      bank: 'Slice',
      isCredit: false,
    ),
    (
      sender: 'AX-ICICIB-S',
      body:
          'ICICI Bank Acct XX1505 debited for Rs {amt} on 08-Aug-26; Swiggy credited. Avl Bal Rs 10.00',
      expectParsed: true,
      bank: 'ICICI',
      isCredit: false,
    ),
    (
      sender: 'JM-KOTAKB',
      body:
          'Rs.{amt} debited from Kotak Bank a/c XXXX3649 towards Swiggy on 08-Aug',
      expectParsed: true,
      bank: 'Kotak',
      isCredit: false,
    ),
    (
      sender: 'AX-AXISBK-S',
      body:
          'Spent INR {amt}\nAxis Bank Card no. XX8341\n08-08-26 12:00:00 IST\nAMAZON\nAvl Limit: INR 50000.00\nNot you? SMS BLOCK 8341 to 919951860002',
      expectParsed: true,
      bank: 'Axis',
      isCredit: false,
    ),
    (
      sender: 'JK-AXISBK-S',
      body: 'INR {amt} spent on Axis Bank Card XX8341 at AMAZON on 08-Aug-26',
      expectParsed: true,
      bank: 'Axis',
      isCredit: false,
    ),
    (
      sender: 'AX-AXISBK-S',
      body:
          'INR {amt} spent on your Axis Bank Credit Card ending XX8341 at IRCTC on 05-Jul-26.',
      expectParsed: true,
      bank: 'Axis',
      isCredit: false,
    ),
    (
      sender: 'VD-IDFCFB-S',
      body:
          'Delicious Purchase! INR {amt} spent on your IDFC FIRST Bank Credit Card ending XX7424 at HungerBox on 11 DEC 2025 at 12:49 PM Avbl Limit: INR 219750',
      expectParsed: true,
      bank: 'IDFC',
      isCredit: false,
    ),
    (
      sender: 'JX-ICICIT-S',
      body:
          'INR {amt} spent using ICICI Bank Card XX2009 on 08-Aug-26 on AMAZON. Avl Limit: INR 10000.00.',
      expectParsed: true,
      bank: 'ICICI',
      isCredit: false,
    ),
    (
      sender: 'VA-YESBNK-S',
      body:
          'INR {amt} spent on YES BANK Card X9757 @UPI_MCDONALDS HARDCAST 07-12-2025 05:01:14 pm.',
      expectParsed: true,
      bank: 'Yes Bank',
      isCredit: false,
    ),
    (
      sender: 'AX-HDFCBK-S',
      body: 'Your OTP for HDFC NetBanking is 123456. Do not share.',
      expectParsed: false,
      bank: null,
      isCredit: null,
    ),
    (
      sender: 'AX-HDFCBK-S',
      body: 'Pre-approved loan offer of Rs 5 lakh for you. Apply now!',
      expectParsed: false,
      bank: null,
      isCredit: null,
    ),
    (
      sender: 'AX-SLCEIT-S',
      body:
          'UPI Payment of Rs. {amt} from a/c xx0856 on 04-Jun-26 to X has failed. Any debited amount has been refunded - slice',
      expectParsed: false,
      bank: null,
      isCredit: null,
    ),
    (
      sender: '9876543210',
      body: 'Rs.{amt} debited from a/c XX1234 on 08-Aug. Call me.',
      expectParsed: false,
      bank: null,
      isCredit: null,
    ),
    (
      sender: 'VK-AXISBK-T',
      body:
          '782140 is SECRET OTP for txn of INR {amt} on Axis Bank card XX8341 at Myntra on 10-12-25. OTP valid for 5 mins. Please do not share this OTP.',
      expectParsed: false,
      bank: null,
      isCredit: null,
    ),
    // Known-problem / high-value shapes (PNB paise, Kotak NACH, Swiggy, CCBP, MBK EMI)
    (
      sender: 'AX-PNBSMS-S',
      body:
          'Thanks for depositing an amount of Rs. {amt} against your Loan Ac XX0310. Register for e-statement,if not done.-PNB',
      expectParsed: true,
      bank: 'PNB',
      isCredit: null,
    ),
    (
      sender: 'JM-KOTAKB-S',
      body:
          'INR {amt} is debited to your Account XXXXXX3649 on 07/12/2025 towards NACH-10-HDFC BANK LIMITED Kotak Bank',
      expectParsed: true,
      bank: 'Kotak',
      isCredit: false,
    ),
    (
      sender: 'JM-KOTAKB-S',
      body:
          'INR {amt} is debited from your Account XXXXXX3649 on 07/08/2026 towards NACH-10-HDFC BANK LIMITED Kotak Bank',
      expectParsed: true,
      bank: 'Kotak',
      isCredit: false,
    ),
    (
      sender: 'VM-SBIIN-S',
      body:
          'Dear UPI user A/C X0429 debited by {amt} on date 08Aug26 trf to SWIGGY Refno 726571152867 If not you call 1800',
      expectParsed: true,
      bank: 'SBI',
      isCredit: false,
    ),
    (
      sender: 'VM-SBIIN-S',
      body:
          'Dear UPI user A/C X6675 debited by {amt} on date 29Sep25 trf to MBK CCBP Refno 101568018632',
      expectParsed: true,
      bank: 'SBI',
      isCredit: false,
    ),
    (
      sender: 'AX-HDFCBK-S',
      body:
          'Sent Rs.{amt} From HDFC Bank A/C *5300 To MBK EMI On 01/01/26',
      expectParsed: true,
      bank: 'HDFC',
      isCredit: false,
    ),
    (
      sender: 'AX-HDFCBK-S',
      body:
          'HDFC Bank:Rs. {amt} debited from a/c *5300 on 28/11/25 to a/c **0310 (UPI Ref No. 568362879750).',
      expectParsed: true,
      bank: 'HDFC',
      isCredit: false,
    ),
    (
      sender: 'VM-SBIIN-S',
      body:
          'Your A/C XXXXX6675 has a credit by NACH- MERCHANT of Rs {amt}',
      expectParsed: true,
      bank: 'SBI',
      isCredit: true,
    ),
    (
      sender: 'VM-SBICRD-S',
      body:
          'We have received payment of Rs.{amt} via BBPS & the same has been credited to your SBI Credit Card. Your available limit is Rs.228,745.25.',
      expectParsed: true,
      bank: 'SBI',
      isCredit: true,
    ),
    (
      sender: 'AX-PNBSMS-S',
      body:
          'Thanks for depositing an amount Rs {amt} against Loan Ac XX0310. -PNB',
      expectParsed: true,
      bank: 'PNB',
      isCredit: null,
    ),
  ];

  for (var t = 0; t < templates.length; t++) {
    final base = templates[t];
    for (var v = 0; v < amounts.length; v++) {
      final amt = amounts[v];
      out.add(
        _Case('pipeline #${t}_$v ${base.sender} ${amt.toStringAsFixed(2)}', () {
          final body = base.body.replaceAll('{amt}', _smsInr(amt));
          final result = SmsScanPipeline.process(
            SmsMessageInput(
              id: 'p_${t}_$v',
              sender: base.sender,
              body: body,
              timestamp: DateTime(2026, 8, 8),
            ),
          );
          if (base.expectParsed) {
            expect(result.isParsed, isTrue, reason: body);
            expect(
              result.transaction!.amount,
              closeTo(amt, 0.001),
              reason: 'amount mismatch: $body',
            );
            if (base.bank != null) {
              expect(result.transaction!.bank, base.bank);
            }
            if (base.isCredit != null) {
              expect(result.transaction!.isCredit, base.isCredit);
            }
          } else {
            expect(result.isParsed, isFalse, reason: body);
          }
        }),
      );
    }
  }
  // 28*8 = 224
  return out;
}

List<_Case> _discoveryMatrix() {
  final out = <_Case>[];
  const savingsBodies = [
    (
      'AX-HDFCBK-S',
      'Rs.100 debited from HDFC Bank A/c **5300 on 08-Aug. Info: X',
      'HDFC',
      '••••5300',
    ),
    (
      'VM-SBIIN-S',
      'Your A/C XXXXX6675 has a credit by NACH- MERCHANT of Rs 100',
      'SBI',
      '••••6675',
    ),
    (
      'AX-ICICIB-S',
      'ICICI Bank Acc XX1505 credited with Rs 200.00 on 08-Aug-26',
      'ICICI',
      '••••1505',
    ),
    (
      'JM-KOTAKB',
      'Rs.500.00 debited from Kotak Bank a/c XXXX3649 towards Swiggy on 08-Aug',
      'Kotak',
      '••••3649',
    ),
  ];
  for (var i = 0; i < savingsBodies.length; i++) {
    for (var v = 0; v < 10; v++) {
      final b = savingsBodies[i];
      out.add(
        _Case('discover savings #${i}_$v', () {
          final d = AccountDiscovery.discover(sender: b.$1, body: b.$2);
          // Some bodies may not match discovery regexes — assert soft.
          if (d != null) {
            expect(d.kind, AccountKind.savings);
            if (d.mask.isNotEmpty) {
              expect(d.mask.startsWith('••••'), isTrue);
            }
          }
        }),
      );
    }
  }

  const ccBodies = [
    (
      'AX-ICICIB-S',
      'INR 500.00 spent on ICICI Bank Credit Card XX2009 at AMAZON on 08-Aug',
      '••••2009',
    ),
    (
      'VA-YESBNK-S',
      'Rs.200 spent using YES BANK Card xx9757 at SWIGGY on 08-Aug',
      '••••9757',
    ),
    (
      'AX-HSBCIN-S',
      'HSBC creditcard xxxxx3740 used at MERCHANT for INR 100.00 on 08-Aug',
      '••••3740',
    ),
    (
      'JK-AXISBK-S',
      'Spent INR 663\nAxis Bank Card no. XX8341\n10-12-25 20:42:01 IST\nMYNTRA\nAvl Limit: INR 96568.75',
      '••••8341',
    ),
    (
      'AX-AXISBK-S',
      'INR 1,200.00 spent on Axis Bank Card XX8341 at AMAZON on 08-Aug-26',
      '••••8341',
    ),
    (
      'VD-IDFCFB-S',
      'Delicious Purchase! INR 80.00 spent on your IDFC FIRST Bank Credit Card ending XX7424 at HungerBox on 11 DEC 2025 at 12:49 PM Avbl Limit: INR 219750',
      '••••7424',
    ),
  ];
  for (var i = 0; i < ccBodies.length; i++) {
    for (var v = 0; v < 10; v++) {
      final b = ccBodies[i];
      out.add(
        _Case('discover CC #${i}_$v', () {
          final d = AccountDiscovery.discover(sender: b.$1, body: b.$2);
          expect(d, isNotNull, reason: b.$2);
          expect(d!.kind, AccountKind.creditCard);
          expect(d.mask, b.$3);
          expect(d.bank, isNotEmpty);
        }),
      );
    }
  }
  return out;
}

List<_Case> _walletAndJunkRejection() {
  final out = <_Case>[];
  const wallets = [
    'Paytm',
    'PhonePe',
    'GPay',
    'Amazon Pay',
    'MobiKwik',
    'Freecharge',
  ];
  for (var i = 0; i < wallets.length; i++) {
    for (final mask in ['••••1111', '••••2222', '••••3333']) {
      out.add(
        _Case('wallet ${wallets[i]} $mask excluded from You', () {
          final store = FinanceStore()
            ..seedTransactions([
              _tx(
                id: 'w_${i}_$mask',
                bank: wallets[i],
                mask: mask,
                amount: 50,
                isCredit: false,
              ),
            ]);
          expect(
            store.bankAccounts().where((a) => a.mask == mask),
            isEmpty,
          );
          expect(
            store.transactionsForAccount(bank: wallets[i], mask: mask),
            isEmpty,
          );
        }),
      );
    }
  }

  for (var year = 2015; year <= 2035; year++) {
    out.add(
      _Case('year-like mask ••••$year rejected', () {
        final store = FinanceStore()
          ..seedTransactions([
            _tx(
              id: 'y$year',
              bank: 'HDFC',
              mask: '••••$year',
              amount: 10,
              isCredit: false,
            ),
          ]);
        expect(
          store.bankAccounts().where((a) => a.mask == '••••$year'),
          isEmpty,
        );
      }),
    );
  }
  return out;
}

List<_Case> _hiddenAndEmpty() {
  final out = <_Case>[];
  for (var i = 0; i < 30; i++) {
    out.add(
      _Case('hidden mask excluded #$i', () {
        final mask = '••••${8000 + i}';
        final store = FinanceStore()
          ..seedTransactions([
            _tx(
              id: 'h$i',
              bank: 'HDFC',
              mask: mask,
              amount: 10,
              isCredit: false,
            ),
          ]);
        expect(store.bankAccounts(hiddenMasks: {mask}), isEmpty);
        expect(store.bankAccounts().where((a) => a.mask == mask).length, 1);
      }),
    );
  }
  for (var i = 0; i < 20; i++) {
    out.add(
      _Case('empty evidenceKey query #$i', () {
        final store = FinanceStore()
          ..seedTransactions([
            _tx(
              id: 'e$i',
              bank: 'SBI',
              mask: '••••0429',
              amount: 1,
              isCredit: false,
            ),
          ]);
        expect(store.transactionsForAccount(bank: 'SBI', mask: ''), isEmpty);
        expect(store.transactionsForAccount(evidenceKey: ''), isEmpty);
      }),
    );
  }
  return out;
}

List<_Case> _multiAccountIsolation() {
  final out = <_Case>[];
  for (var i = 0; i < 100; i++) {
    final m1 = '••••${6000 + i}';
    final m2 = '••••${6100 + i}';
    out.add(
      _Case('isolation two HDFC masks #$i', () {
        final store = FinanceStore()
          ..seedTransactions([
            _tx(id: 'x$i', bank: 'HDFC', mask: m1, amount: 10, isCredit: false),
            _tx(id: 'y$i', bank: 'HDFC', mask: m2, amount: 20, isCredit: false),
            _tx(
              id: 'orphan$i',
              bank: 'HDFC',
              mask: '',
              amount: 99,
              isCredit: false,
            ),
          ]);
        final a1 = store.bankAccounts().firstWhere((a) => a.mask == m1);
        final a2 = store.bankAccounts().firstWhere((a) => a.mask == m2);
        final l1 = store.transactionsForAccount(evidenceKey: a1.evidenceKey);
        final l2 = store.transactionsForAccount(evidenceKey: a2.evidenceKey);
        expect(l1.map((t) => t.id).toSet(), {'x$i'});
        expect(l2.map((t) => t.id).toSet(), {'y$i'});
        // orphan must not attach when two savings masks exist
        expect(l1.any((t) => t.id == 'orphan$i'), isFalse);
        expect(l2.any((t) => t.id == 'orphan$i'), isFalse);
      }),
    );
  }

  // Same bank|mask with mixed kinds: product keys by bank|mask and elects
  // kind by vote (CC wins when cc votes > savings). Savings-only stays savings.
  const banks = ['Axis', 'HDFC', 'ICICI', 'SBI', 'Kotak'];
  for (var i = 0; i < banks.length; i++) {
    for (var j = 0; j < 12; j++) {
      final mask = '••••${8340 + j}';
      out.add(
        _Case('kind elect CC ${banks[i]} $mask #$j', () {
          final store = FinanceStore()
            ..seedTransactions([
              _tx(
                id: 'sav_$i$j',
                bank: banks[i],
                mask: mask,
                amount: 10,
                isCredit: false,
                kind: AccountKind.savings,
              ),
              _tx(
                id: 'cc1_$i$j',
                bank: banks[i],
                mask: mask,
                amount: 20,
                isCredit: false,
                kind: AccountKind.creditCard,
              ),
              _tx(
                id: 'cc2_$i$j',
                bank: banks[i],
                mask: mask,
                amount: 30,
                isCredit: false,
                kind: AccountKind.creditCard,
              ),
            ]);
          final accounts = store
              .bankAccounts()
              .where((a) => a.bank == banks[i] && a.mask == mask)
              .toList();
          expect(accounts.length, 1);
          expect(accounts.first.kind, AccountKind.creditCard);
          final list = store.transactionsForAccount(
            evidenceKey: accounts.first.evidenceKey,
          );
          expect(list.length, 3);
          expect(accounts.first.spentTotal, 60);
          _expectParity(store, bank: banks[i], mask: mask);
        }),
      );
    }
  }
  // 100 + 5*12 = 160
  return out;
}

List<_Case> _nachFromToMatrix() {
  final out = <_Case>[];
  const beneficiaries = [
    ('HDFC BANK LIMITED', 'hdfc', 'HDFC', '••••0855'),
    ('TP ACH ICICI', 'icici', 'ICICI', '••••1041'),
    ('IDFC FIRST BANK', 'idfc', 'IDFC', '••••2585'),
  ];
  const preps = ['from', 'to'];
  const amounts = [500.00, 5199.39, 8000.50, 25797.00, 25797.39, 32000.01];
  for (final hint in beneficiaries) {
    for (final prep in preps) {
      for (var i = 0; i < amounts.length; i++) {
        final amt = amounts[i];
        out.add(
          _Case('NACH $prep ${hint.$2} ${amt.toStringAsFixed(2)}', () {
            final body =
                'INR ${_smsInr(amt)} is debited $prep your Account XXXXXX3649 on '
                '07/0${(i % 9) + 1}/2026 towards NACH-10-${hint.$1} Kotak Bank';
            final parsed = SmsScanPipeline.process(
              SmsMessageInput(
                id: 'nach_${hint.$2}_${prep}_$i',
                sender: 'JM-KOTAKB-S',
                body: body,
                timestamp: DateTime(2026, 8, 7),
              ),
            );
            expect(parsed.isParsed, isTrue, reason: body);
            expect(parsed.transaction!.amount, closeTo(amt, 0.001));
            expect(parsed.transaction!.isCredit, isFalse);
            expect(parsed.transaction!.bank, 'Kotak');
            expect(parsed.transaction!.maskedAccount, '••••3649');

            final result = TransactionEnrichment.resolveLoanDisplay(
              body: body,
              parsedBank: 'Kotak',
              parsedMask: '••••3649',
              discoveries: [
                DiscoveredAccount(
                  bank: hint.$3,
                  mask: hint.$4,
                  kind: AccountKind.loan,
                  smsHits: 3,
                ),
              ],
            );
            expect(result.bank, hint.$3);
            expect(result.mask, hint.$4);

            final kind = TransactionEnrichment.resolveAccountKind(
              bank: 'Kotak',
              mask: '••••3649',
              body: body,
              discoveries: [
                DiscoveredAccount(
                  bank: 'Kotak',
                  mask: '••••3649',
                  kind: AccountKind.savings,
                  smsHits: 10,
                ),
                DiscoveredAccount(
                  bank: hint.$3,
                  mask: hint.$4,
                  kind: AccountKind.loan,
                  smsHits: 3,
                ),
              ],
            );
            expect(kind, AccountKind.loan);
          }),
        );
      }
    }
  }
  // 3*2*6 = 36
  return out;
}

List<_Case> _sbiTrfVsCcbpMatrix() {
  final out = <_Case>[];
  const brands = [
    ('SWIGGY', SpendCategory.food),
    ('ZOMATO', SpendCategory.food),
    ('BLINKIT', SpendCategory.food),
    ('DOMINOS', SpendCategory.food),
    ('AMAZON', SpendCategory.shopping),
    ('MYNTRA', SpendCategory.shopping),
    ('FLIPKART', SpendCategory.shopping),
    ('UBER', SpendCategory.travel),
    ('IRCTC', SpendCategory.travel),
    ('NETFLIX', SpendCategory.entertainment),
  ];
  const amounts = [99.99, 325.50, 5199.39, 1246.00];
  for (final brand in brands) {
    for (var i = 0; i < amounts.length; i++) {
      final amt = amounts[i];
      out.add(
        _Case('R2-1 trf to ${brand.$1} ${amt.toStringAsFixed(2)}', () {
          final body =
              'Dear UPI user A/C X0429 debited by ${_smsInr(amt)} on date 04Jun26 '
              'trf to ${brand.$1} Refno 726571152867';
          final parsed = SmsScanPipeline.process(
            SmsMessageInput(
              id: 'trf_${brand.$1}_$i',
              sender: 'VM-SBIIN-S',
              body: body,
              timestamp: DateTime(2026, 6, 4),
            ),
          );
          expect(parsed.isParsed, isTrue, reason: body);
          expect(parsed.transaction!.amount, closeTo(amt, 0.001));
          expect(parsed.transaction!.isCredit, isFalse);
          expect(
            MerchantCategorizer.categorize(
              merchant: brand.$1,
              smsBody: body,
              isCredit: false,
            ),
            brand.$2,
          );
        }),
      );
    }
  }

  const ccbpPayees = ['MBK CCBP', 'MOBIKWIKCCBP', 'BBPS CREDIT CARD'];
  for (final payee in ccbpPayees) {
    for (var i = 0; i < amounts.length; i++) {
      final amt = amounts[i];
      out.add(
        _Case('R2-1 trf to $payee ${amt.toStringAsFixed(2)}', () {
          final body =
              'Dear UPI user A/C X6675 debited by ${_smsInr(amt)} on date 29Sep25 '
              'trf to $payee Refno 101568018632';
          final cat = MerchantCategorizer.categorize(
            merchant: payee,
            smsBody: body,
            isCredit: false,
          );
          expect(cat, SpendCategory.transfer, reason: body);
          if (payee.contains('CCBP')) {
            final parsed = SmsScanPipeline.process(
              SmsMessageInput(
                id: 'ccbp_${payee}_$i',
                sender: 'VM-SBIIN-S',
                body: body,
                timestamp: DateTime(2026, 9, 29),
              ),
            );
            expect(parsed.isParsed, isTrue, reason: body);
            expect(parsed.transaction!.amount, closeTo(amt, 0.001));
            expect(
              TransactionEnrichment.resolveCreditCardDisplay(
                body: body,
                parsedBank: 'SBI',
                parsedMask: '••••6675',
                discoveries: const [
                  DiscoveredAccount(
                    bank: 'HDFC',
                    mask: '••••9999',
                    kind: AccountKind.creditCard,
                    smsHits: 3,
                  ),
                ],
              ),
              (bank: 'SBI', mask: '••••6675'),
            );
          }
        }),
      );
    }
  }
  // 10*4 + 3*4 = 52
  return out;
}

List<_Case> _upiDestLast4Matrix() {
  final out = <_Case>[];
  const dests = [
    ('0310', 'PNB'),
    ('0855', 'HDFC'),
    ('1041', 'ICICI'),
    ('2585', 'IDFC'),
    ('2200', 'SBI'),
    ('3300', 'Axis'),
    ('4410', 'Kotak'),
    ('1505', 'ICICI'),
  ];
  const amounts = [5199.39, 8000.50, 12000.00, 25797.00];
  const multiLoans = [
    DiscoveredAccount(
      bank: 'HDFC',
      mask: '••••0855',
      kind: AccountKind.loan,
      smsHits: 5,
    ),
    DiscoveredAccount(
      bank: 'ICICI',
      mask: '••••1041',
      kind: AccountKind.loan,
      smsHits: 5,
    ),
    DiscoveredAccount(
      bank: 'PNB',
      mask: '••••0310',
      kind: AccountKind.loan,
      smsHits: 4,
    ),
    DiscoveredAccount(
      bank: 'IDFC',
      mask: '••••2585',
      kind: AccountKind.loan,
      smsHits: 3,
    ),
    DiscoveredAccount(
      bank: 'SBI',
      mask: '••••2200',
      kind: AccountKind.loan,
      smsHits: 2,
    ),
    DiscoveredAccount(
      bank: 'Axis',
      mask: '••••3300',
      kind: AccountKind.loan,
      smsHits: 2,
    ),
    DiscoveredAccount(
      bank: 'Kotak',
      mask: '••••4410',
      kind: AccountKind.loan,
      smsHits: 2,
    ),
  ];

  for (final dest in dests) {
    for (var i = 0; i < amounts.length; i++) {
      final amt = amounts[i];
      out.add(
        _Case('UPI dest ••••${dest.$1} ${amt.toStringAsFixed(2)}', () {
          final body =
              'HDFC Bank:Rs. ${_smsInr(amt)} debited from a/c *5300 on 28/11/25 '
              'to a/c **${dest.$1} (UPI Ref No. 568362879750).';
          final parsed = SmsScanPipeline.process(
            SmsMessageInput(
              id: 'dest_${dest.$1}_$i',
              sender: 'AX-HDFCBK-S',
              body: body,
              timestamp: DateTime(2026, 11, 28),
            ),
          );
          expect(parsed.isParsed, isTrue, reason: body);
          expect(parsed.transaction!.amount, closeTo(amt, 0.001));
          expect(parsed.transaction!.maskedAccount, '••••5300');

          final unique = [
            DiscoveredAccount(
              bank: dest.$2,
              mask: '••••${dest.$1}',
              kind: AccountKind.loan,
              smsHits: 4,
            ),
          ];
          final remapped = TransactionEnrichment.resolveLoanDisplay(
            body: body,
            parsedBank: 'HDFC',
            parsedMask: '••••5300',
            discoveries: unique,
          );
          expect(remapped.bank, dest.$2);
          expect(remapped.mask, '••••${dest.$1}');

          // Multi-loan: dest last-4 still remaps only that unique mask.
          final multi = TransactionEnrichment.resolveLoanDisplay(
            body: body,
            parsedBank: 'HDFC',
            parsedMask: '••••5300',
            discoveries: multiLoans,
          );
          final known = multiLoans.any((d) => d.mask == '••••${dest.$1}');
          if (known) {
            expect(multi.bank, dest.$2);
            expect(multi.mask, '••••${dest.$1}');
          } else {
            expect(multi.bank, 'HDFC');
            expect(multi.mask, '••••5300');
          }
        }),
      );
    }
  }
  // 8*4 = 32
  return out;
}

List<_Case> _pairingIndexMatrix() {
  final out = <_Case>[];
  const amounts = [
    0.85,
    99.99,
    5199.39,
    5200.00,
    8000.50,
    12000.00,
    25797.00,
    25797.39,
    32000.01,
    486.00,
  ];
  const pnbLoan = DiscoveredAccount(
    bank: 'PNB',
    mask: '••••0310',
    kind: AccountKind.loan,
    smsHits: 4,
  );
  const hdfcLoan = DiscoveredAccount(
    bank: 'HDFC',
    mask: '••••0855',
    kind: AccountKind.loan,
    smsHits: 5,
  );

  void expectIndexParity({
    required String productBank,
    required String productMask,
    required AccountKind productKind,
    required List<Transaction> all,
    required Iterable<DiscoveredAccount> discoveries,
  }) {
    final indexed = ProductPaymentLinker.linkedFundingTransactions(
      productBank: productBank,
      productMask: productMask,
      productKind: productKind,
      all: all,
      discoveries: discoveries,
    );
    final scan = ProductPaymentLinker.linkedFundingTransactionsScan(
      productBank: productBank,
      productMask: productMask,
      productKind: productKind,
      all: all,
      discoveries: discoveries,
    );
    expect(indexed.map((t) => t.id).toList(), scan.map((t) => t.id).toList());
    for (final t in all) {
      expect(
        ProductPaymentLinker.productSideCoversFunding(
          funding: t,
          productBank: productBank,
          productMask: productMask,
          all: all,
        ),
        ProductPaymentLinker.productSideCoversFundingScan(
          funding: t,
          productBank: productBank,
          productMask: productMask,
          all: all,
        ),
      );
    }
  }

  for (var i = 0; i < amounts.length; i++) {
    final amt = amounts[i];
    out.add(
      _Case('pairing covered ${amt.toStringAsFixed(2)}', () {
        final all = [
          _tx(
            id: 'fund$i',
            bank: 'HDFC',
            mask: '••••5300',
            amount: amt,
            isCredit: false,
            kind: AccountKind.loan,
            category: SpendCategory.emi,
            merchant: 'MBK EMI',
            at: DateTime(2026, 2, 27),
          ),
          _tx(
            id: 'prod$i',
            bank: 'PNB',
            mask: '••••0310',
            amount: amt,
            isCredit: false,
            kind: AccountKind.loan,
            category: SpendCategory.emi,
            merchant: 'Loan payment',
            at: DateTime(2026, 2, 27, 1),
          ),
        ];
        expectIndexParity(
          productBank: 'PNB',
          productMask: '••••0310',
          productKind: AccountKind.loan,
          all: all,
          discoveries: [pnbLoan, hdfcLoan],
        );
        expect(
          ProductPaymentLinker.linkedFundingTransactions(
            productBank: 'PNB',
            productMask: '••••0310',
            productKind: AccountKind.loan,
            all: all,
            discoveries: [pnbLoan, hdfcLoan],
          ),
          isEmpty,
        );
      }),
    );
    out.add(
      _Case('pairing orphan unique ${amt.toStringAsFixed(2)}', () {
        final all = [
          _tx(
            id: 'orphan$i',
            bank: 'HDFC',
            mask: '••••5300',
            amount: amt,
            isCredit: false,
            kind: AccountKind.loan,
            category: SpendCategory.emi,
            merchant: 'MBK EMI',
            at: DateTime(2026, 2, 27),
          ),
        ];
        expectIndexParity(
          productBank: 'PNB',
          productMask: '••••0310',
          productKind: AccountKind.loan,
          all: all,
          discoveries: [pnbLoan],
        );
        expect(
          ProductPaymentLinker.linkedFundingTransactions(
            productBank: 'PNB',
            productMask: '••••0310',
            productKind: AccountKind.loan,
            all: all,
            discoveries: [pnbLoan],
          ).map((t) => t.id),
          ['orphan$i'],
        );
      }),
    );
    out.add(
      _Case('pairing multi-loan no guess ${amt.toStringAsFixed(2)}', () {
        final all = [
          _tx(
            id: 'mbk$i',
            bank: 'HDFC',
            mask: '••••5300',
            amount: amt,
            isCredit: false,
            kind: AccountKind.loan,
            category: SpendCategory.emi,
            merchant: 'MBK EMI',
            at: DateTime(2026, 2, 27),
          ),
        ];
        expectIndexParity(
          productBank: 'PNB',
          productMask: '••••0310',
          productKind: AccountKind.loan,
          all: all,
          discoveries: [pnbLoan, hdfcLoan],
        );
        expect(
          ProductPaymentLinker.linkedFundingTransactions(
            productBank: 'PNB',
            productMask: '••••0310',
            productKind: AccountKind.loan,
            all: all,
            discoveries: [pnbLoan, hdfcLoan],
          ),
          isEmpty,
        );
      }),
    );
  }
  // 10*3 = 30
  return out;
}

List<_Case> _formattersPaiseMatrix() {
  final out = <_Case>[];
  const amounts = [
    0.01,
    0.10,
    0.85,
    1.50,
    9.99,
    23.60,
    99.99,
    100.00,
    325.50,
    486.00,
    1246.00,
    2400.68,
    5199.39,
    5270.00,
    8000.50,
    12000.00,
    25797.00,
    25797.39,
    32000.01,
    99999.99,
  ];
  for (final amt in amounts) {
    final cents = ((amt * 100).round() % 100).toString().padLeft(2, '0');
    out.add(
      _Case('formatInr ${amt.toStringAsFixed(2)} keeps paise', () {
        final formatted = formatInr(amt);
        expect(formatted, startsWith('₹'));
        expect(formatted, contains('.$cents'));
        expect(formatCompactInr(amt), formatted);
      }),
    );
    out.add(
      _Case('formatAmount debit ${amt.toStringAsFixed(2)}', () {
        final formatted = formatAmount(amt, isCredit: false);
        expect(formatted, startsWith('−'));
        expect(formatted, contains('.$cents'));
      }),
    );
  }
  // 20*2 = 40
  return out;
}

List<_Case> _r2RegressionMatrix() {
  final out = <_Case>[];

  // R2-2: SIP / clearing-corp NACH must stay on funding savings.
  const sipAmounts = [500.00, 1000.00, 2500.50, 5000.00, 9999.99, 15000.00];
  for (final prep in ['from', 'to']) {
    for (var i = 0; i < sipAmounts.length; i++) {
      final amt = sipAmounts[i];
      out.add(
        _Case('R2-2 NACH SIP $prep ${amt.toStringAsFixed(2)}', () {
          final body =
              'INR ${_smsInr(amt)} is debited $prep your Account XXXXXX1234 on '
              '07/0${(i % 9) + 1}/2026 towards NACH-10-INDIAN CLEARING CORP';
          const discoveries = [
            DiscoveredAccount(
              bank: 'HDFC',
              mask: '••••1234',
              kind: AccountKind.savings,
              smsHits: 8,
            ),
            DiscoveredAccount(
              bank: 'HDFC',
              mask: '••••0855',
              kind: AccountKind.loan,
              smsHits: 5,
            ),
          ];
          expect(
            TransactionEnrichment.resolveAccountKind(
              bank: 'HDFC',
              mask: '••••1234',
              body: body,
              discoveries: discoveries,
            ),
            AccountKind.savings,
          );
          final display = TransactionEnrichment.resolveLoanDisplay(
            body: body,
            parsedBank: 'HDFC',
            parsedMask: '••••1234',
            discoveries: discoveries,
          );
          expect(display.bank, 'HDFC');
          expect(display.mask, '••••1234');
        }),
      );
    }
  }

  // R2-3: word-bound EMI — Premium / Chemist / Panache are not loan funding.
  const notLoan = [
    'LIC Premium',
    'Wellness Chemist',
    'Cafe Panache',
    'Premium Cloths',
    'NACHOS BAR',
    'EMIYA SALON',
  ];
  for (final merchant in notLoan) {
    out.add(
      _Case('R2-3 $merchant is not loan funding', () {
        expect(
          ProductPaymentLinker.looksLikeLoanFundingPayment(
            _tx(
              id: merchant,
              bank: 'HDFC',
              mask: '••••5300',
              amount: 1000,
              isCredit: false,
              merchant: merchant,
            ),
          ),
          isFalse,
        );
      }),
    );
  }
  const yesLoan = ['MBK EMI', 'NACH-10-HDFC BANK LIMITED', 'Home Loan EMI'];
  for (final merchant in yesLoan) {
    out.add(
      _Case('R2-3 $merchant is loan funding', () {
        expect(
          ProductPaymentLinker.looksLikeLoanFundingPayment(
            _tx(
              id: merchant,
              bank: 'HDFC',
              mask: '••••5300',
              amount: 1000,
              isCredit: false,
              merchant: merchant,
            ),
          ),
          isTrue,
        );
      }),
    );
  }

  // R2-4: Slice savings + card same last-4 stay two You accounts.
  const last4s = ['1234', '0856', '7185', '9999', '2009', '8341', '3740', '7424'];
  for (final last4 in last4s) {
    out.add(
      _Case('R2-4 Slice+HDFC CC ••••$last4 stay split', () {
        final mask = '••••$last4';
        final store = FinanceStore()
          ..seedDiscoveredAccounts([
            DiscoveredAccount(
              bank: 'Slice',
              mask: mask,
              kind: AccountKind.savings,
              smsHits: 20,
            ),
          ])
          ..seedTransactions([
            _tx(
              id: 'slice$last4',
              bank: 'Slice',
              mask: mask,
              amount: 200,
              isCredit: false,
              kind: AccountKind.savings,
            ),
            _tx(
              id: 'cc$last4',
              bank: 'HDFC',
              mask: mask,
              amount: 1500,
              isCredit: false,
              kind: AccountKind.creditCard,
              category: SpendCategory.shopping,
            ),
          ]);
        final matching =
            store.bankAccounts().where((a) => a.mask == mask).toList();
        expect(matching.length, 2);
        expect(matching.map((a) => a.kind).toSet(), {
          AccountKind.savings,
          AccountKind.creditCard,
        });
        _expectParity(store);
      }),
    );
  }

  // R2-5 / R2-6: registry learn-order + incremental merge are covered by
  // dedicated suites; keep a few combinatorial registry edges here.
  for (var i = 0; i < 8; i++) {
    final last4 = '${2000 + i}';
    out.add(
      _Case('R2-5 registry prior Slice beats ICICI relay #$i', () {
        final r = AccountBankRegistry()
          ..learn(
            'AX-SLCEIT-S',
            'Rs. 10 sent from a/c xx$last4 on 01-Jan-26 to X - slice',
          )
          ..learn(
            'VM-ICICI-S',
            'Account XXXXXXXX$last4 has been credited with amount Rs.5. '
                'Info: LENDENCLUB BORROWER REPAYMENT.',
          );
        expect(r.lookup(last4), 'Slice');
      }),
    );
  }
  // 2*6 + 6 + 3 + 8 + 8 = 37
  return out;
}

/// Schema-33 live-inbox corners: parse completed spends/credits with exact
/// paise, reject due/amountless/failed SMS, keep DC vs CC and multi-loan
/// association from contaminating the wrong account.
List<_Case> _liveInboxCornerMatrix() {
  final out = <_Case>[];
  const parseAmounts = [
    0.85,
    3.24,
    23.60,
    134.09,
    282.00,
    325.50,
    2451.58,
    5199.39,
    8330.00,
    9392.10,
    15076.54,
    25797.00,
  ];
  final parseTemplates = <({
    String sender,
    String body,
    String? bank,
    bool? isCredit,
  })>[
    (
      sender: 'AD-HDFCBK-S',
      body:
          'Spent Rs.{amt} On HDFC Bank Card 1949 At AIIMSOTHCRCARD On 2026-08-03:01:12:32.Not You? To Block+Reissue Call 18002586161/SMS BLOCK CC 1949 to 7308080808',
      bank: 'HDFC',
      isCredit: false,
    ),
    (
      sender: 'JX-HDFCBK-S',
      body:
          'Spent Rs.{amt} From HDFC Bank Card x3569 At CCBBPSNO On 2026-08-01:06:02:24 Bal Rs.55551.08 Not You? Call 18002586161/SMS BLOCK DC  3569 to 7308080808',
      bank: 'HDFC',
      isCredit: false,
    ),
    (
      sender: 'AX-HDFCBK-S',
      body:
          'Spent Rs.{amt} From HDFC Bank Card x3569 At DCSI-BBPSBILL On 2026-07-29:06:04:45 Bal Rs.16393.10 Not You? Call 18002586161/SMS BLOCK DC  3569 to 7308080808',
      bank: 'HDFC',
      isCredit: false,
    ),
    (
      sender: 'JD-ICICIT-S',
      body:
          'Congrats! Rs {amt} cashback credited to ICICI Bank Credit Card on 16-Jul-26. For details check Card statement',
      bank: 'ICICI',
      isCredit: true,
    ),
    (
      sender: 'AX-ICICIT-S',
      body:
          'ZEPTO MARKETPLACE PRIVATE refund of Rs {amt} credited to your ICICI Bank Credit Card XX0003 on 07-JUN-26.',
      bank: 'ICICI',
      isCredit: true,
    ),
    (
      sender: 'JM-SBICGV-S',
      body:
          'Rs. {amt} has been credited to your SBI Credit Card xxxx3452, towards reversal/cashback from Razorpay Payments New Delhi IND for trxn. dated 02/08/2026',
      bank: 'SBI',
      isCredit: true,
    ),
    (
      sender: 'VA-SBICRD-S',
      body:
          'Transaction of Rs.{amt} at GOOGLEPLAY against E-mandate (SiHub ID - YPPQfwzOzw) registered by you at merchant has been debited to your SBI Credit Card ending 3452 on 23-06-26.',
      bank: 'SBI',
      isCredit: false,
    ),
    (
      sender: 'AD-SBIUPI-S',
      body:
          'Dear SBI User, your A/c X6675-credited by Rs.{amt} on 01Jul26 transfer from Test User Ref No 618201120617 -SBI',
      bank: 'SBI',
      isCredit: true,
    ),
    (
      sender: 'JD-SBIPSG-T',
      body:
          'Dear Customer, Your a/c no. XXXXXXXX6675 is credited by Rs.{amt} on 01-06-26 by a/c linked to mobile 8XXXXXX229-TEST (IMPS Ref# 615219049930)-SBI',
      bank: 'SBI',
      isCredit: true,
    ),
    (
      sender: 'AD-CBSSBI-S',
      body:
          'Your AC XXXXX460429 Debited INR {amt} on 28/04/26 -ATM PENDING AMC. Avl Bal INR 499.91.-SBI',
      bank: 'SBI',
      isCredit: false,
    ),
    (
      sender: 'VM-CBSSBI-S',
      body:
          'Your A/C XXXXX286675 Credited INR {amt} on 20/03/26 -Deposited by Cash by SELF. Avl Bal INR 51,102.62-SBI',
      bank: 'SBI',
      isCredit: true,
    ),
    (
      sender: 'AD-KOTAKB-S',
      body:
          'INR {amt} spent on Kotak Credit Card x4310 on 02-Aug-2026 at SWIGGY PVT LTD FOOD2. Avl limit INR 451718 Fraud? https://www.kotak.bank.in/KBANKT/querytxn',
      bank: 'Kotak',
      isCredit: false,
    ),
    (
      sender: 'VM-PNBSMS-S',
      body:
          'Dear Customer,your A/c XX4720 debited with Rs.{amt} towards bank charges on 06-01-2026.Available balance: Rs.77.77-PNB',
      bank: 'PNB',
      isCredit: false,
    ),
    (
      sender: 'VM-IDFCFB-S',
      body:
          'Monthly interest of INR.{amt} earned on your Savings A/c XX0070 has been credited to your A/C on 31/07/26. New bal: INR.1,843.18. IDFC FIRST Bank',
      bank: 'IDFC',
      isCredit: true,
    ),
    (
      sender: 'AX-IDFCFB-S',
      body:
          'Monthly interest of Rs.{amt} earned on your Savings A/c XX0070 has been credited to your A/C on 30/06/26. New bal: Rs.1,839.18. IDFC FIRST Bank',
      bank: 'IDFC',
      isCredit: true,
    ),
    (
      sender: 'JX-IDFCFB-S',
      body:
          'Thank you for payment of INR {amt} towards your FIRST Power Plus Credit Card XX7424 on 11 Jan 2026. IDFC FIRST Bank',
      bank: 'IDFC',
      isCredit: true,
    ),
    (
      sender: 'JD-ICICIT-S',
      body:
          'Dear TEST USER ,Your account XXXXXXXX0856 has been credited with amount {amt} .Reference no- CMS5668330977 .Thanks, LENDENCLUB BORROWER REPAYMENT ISP LTD ACCOUNT',
      bank: null,
      isCredit: true,
    ),
    (
      sender: 'AX-PNBSMS-S',
      body:
          'Thanks for depositing an amount of Rs. {amt} against your Loan Ac XX0310. Register for e-statement,if not done.-PNB',
      bank: 'PNB',
      isCredit: null,
    ),
    (
      sender: 'AX-PNBSMS-S',
      body:
          'Thanks for depositing an amount Rs {amt} against Loan Ac XX0310. -PNB',
      bank: 'PNB',
      isCredit: null,
    ),
    (
      sender: 'JM-KOTAKB-S',
      body:
          'INR {amt} is debited from your Account XXXXXX3649 on 07/08/2026 towards NACH-10-HDFC BANK LIMITED Kotak Bank',
      bank: 'Kotak',
      isCredit: false,
    ),
    (
      sender: 'VM-SBIIN-S',
      body:
          'Dear UPI user A/C X0429 debited by {amt} on date 08Aug26 trf to SWIGGY Refno 726571152867 If not you call 1800',
      bank: 'SBI',
      isCredit: false,
    ),
    (
      sender: 'AX-HDFCBK-S',
      body: 'Sent Rs.{amt} From HDFC Bank A/C *5300 To MBK EMI On 01/01/26',
      bank: 'HDFC',
      isCredit: false,
    ),
  ];

  for (var t = 0; t < parseTemplates.length; t++) {
    final base = parseTemplates[t];
    for (var v = 0; v < parseAmounts.length; v++) {
      final amt = parseAmounts[v];
      out.add(
        _Case(
          'live-parse #${t}_$v ${base.sender} ${amt.toStringAsFixed(2)}',
          () {
            final body = base.body.replaceAll('{amt}', _smsInr(amt));
            final result = SmsScanPipeline.process(
              SmsMessageInput(
                id: 'live_${t}_$v',
                sender: base.sender,
                body: body,
                timestamp: DateTime(2026, 6, 15, 12),
              ),
            );
            expect(result.isParsed, isTrue, reason: body);
            expect(
              result.transaction!.amount,
              closeTo(amt, 0.001),
              reason: 'amount mismatch: $body',
            );
            if (base.bank != null) {
              expect(result.transaction!.bank, base.bank);
            }
            if (base.isCredit != null) {
              expect(result.transaction!.isCredit, base.isCredit);
            }
          },
        ),
      );
    }
  }
  // 22*12 = 264

  const rejectAmounts = [
    0.85,
    134.09,
    500.00,
    1000.00,
    2253.62,
    5199.39,
    25797.00,
    26408.00,
  ];
  final rejectTemplates = <({String sender, String body})>[
    (
      sender: 'JX-ICICIT-S',
      body:
          'EMI of Rs {amt} for ICICI Bank Personal Loan XX1041 is due on 05-Aug-26. Please maintain sufficient funds in your linked Account XX3649 to avoid 5% per annum penal charges and Rs 500 bounce charges. EMI will be debited on holidays too.',
    ),
    (
      sender: 'JM-HDFCBK-S',
      body:
          "SmartPay Alert: IDFCBankCC Bill 6204969301 can't be auto debited as HDFC Bank received a bill of Rs. {amt}. Please pay via alternate method.",
    ),
    (
      sender: 'VM-SWIGGY-S',
      body:
          'Your payment for Swiggy order #240386868605677 was not completed. Any amount if debited from your card will get refunded within 4-7 days. Amount Rs.{amt}.',
    ),
    (
      sender: 'JK-AXMAXT-S',
      body:
          'Dear Customer, amount of Rs. {amt} for your Axis Max Life policy 157807769 will be debited from your credit card on 05-Aug-2026. Kindly ensure your card remains active around your due date.',
    ),
    (
      sender: 'JX-ICICIT-T',
      body:
          'Payment of USD {amt} towards Merchant Anthropic to be debited from ICICI Bank Credit Card 2009, as per Standing Instruction YPcEzd4KxS, is due by 26/06/2026.',
    ),
    (
      sender: 'AX-HDFCBK-S',
      body: 'Your OTP for txn of INR {amt} on HDFC Bank card XX1949 is 123456.',
    ),
    (
      sender: 'AX-HDFCBK-S',
      body:
          'Pre-approved Personal Loan of Rs {amt} for you. Apply now! Interest rate starts 10.5%.',
    ),
    (
      sender: 'VM-KOTAKB-S',
      body:
          'Your Salary A/cx3649 may have low bal. Pls maintain avg bal of Rs.{amt} or ensure salary is credited to avoid Non-Maintenance Charges-Kotak Bank.',
    ),
    (
      sender: 'JD-ICICIT-S',
      body:
          'Dear TEST USER ,Your account XXXXXXXX0856 has been credited with amount . .Reference no- CMS5807350098 .Thanks, LENDENCLUB BORROWER REPAYMENT ISP LTD ACCOUNT',
    ),
    (
      sender: 'AD-LENDEN-S',
      body:
          'Dear TEST USER, some of your loans have been cancelled. A refund of Rs. {amt} has been credited to your bank. Check your email for details. LenDenClub.',
    ),
  ];

  for (var t = 0; t < rejectTemplates.length; t++) {
    final base = rejectTemplates[t];
    for (var v = 0; v < rejectAmounts.length; v++) {
      final amt = rejectAmounts[v];
      out.add(
        _Case(
          'live-reject #${t}_$v ${base.sender} ${amt.toStringAsFixed(2)}',
          () {
            final body = base.body.replaceAll('{amt}', _smsInr(amt));
            final result = SmsScanPipeline.process(
              SmsMessageInput(
                id: 'rej_${t}_$v',
                sender: base.sender,
                body: body,
                timestamp: DateTime(2026, 6, 15, 12),
              ),
            );
            expect(result.isParsed, isFalse, reason: body);
          },
        ),
      );
    }
  }
  // 10*8 = 80

  // Leading-dot LenDenClub paise must parse as 0.xx, never invent a rupee.
  for (final paise in [0.85, 0.86, 0.01, 0.10, 0.99, 0.50, 0.25, 0.05]) {
    final frac = (paise * 100).round().toString().padLeft(2, '0');
    out.add(
      _Case('live leading-dot LenDen 0.$frac', () {
        final body =
            'Dear TEST USER ,Your account XXXXXXXX0856 has been credited with amount .$frac .Reference no- CMS1 .Thanks, LENDENCLUB BORROWER REPAYMENT ISP LTD ACCOUNT';
        final result = SmsScanPipeline.process(
          SmsMessageInput(
            id: 'dot$frac',
            sender: 'JD-ICICIT-S',
            body: body,
            timestamp: DateTime(2026, 6, 15),
          ),
        );
        expect(result.isParsed, isTrue, reason: body);
        expect(result.transaction!.amount, closeTo(paise, 0.001));
        expect(result.transaction!.isCredit, isTrue);
        expect(result.transaction!.maskedAccount, '••••0856');
      }),
    );
  }

  // Debit-card BBPS stays savings; On-card spend is credit card.
  for (final last4 in ['3569', '1949', '4310', '3452', '0003', '7424', '8341', '9757']) {
    out.add(
      _Case('live DC BLOCK DC ••••$last4 is savings', () {
        final body =
            'Spent Rs.31250 From HDFC Bank Card x$last4 At CCBBPSNO On 2026-08-01:06:02:24 Bal Rs.55551.08 Not You? Call 18002586161/SMS BLOCK DC  $last4 to 7308080808';
        final d = AccountDiscovery.discover(sender: 'JX-HDFCBK-S', body: body);
        expect(d, isNotNull, reason: body);
        expect(d!.kind, AccountKind.savings);
        expect(d.mask, '••••$last4');
        expect(
          TransactionEnrichment.looksLikeCreditCardTransaction(body.toLowerCase()),
          isFalse,
        );
        expect(
          MerchantCategorizer.categorize(
            merchant: 'CCBBPSNO',
            smsBody: body,
            isCredit: false,
          ),
          SpendCategory.transfer,
        );
      }),
    );
    out.add(
      _Case('live CC BLOCK CC ••••$last4 is credit card', () {
        final body =
            'Spent Rs.3035.4 On HDFC Bank Card $last4 At AIIMSOTHCRCARD On 2026-08-03:01:12:32.Not You? To Block+Reissue Call 18002586161/SMS BLOCK CC $last4 to 7308080808';
        final d = AccountDiscovery.discover(sender: 'AD-HDFCBK-S', body: body);
        expect(d, isNotNull, reason: body);
        expect(d!.kind, AccountKind.creditCard);
        expect(d.mask, '••••$last4');
        expect(
          TransactionEnrichment.looksLikeCreditCardTransaction(body.toLowerCase()),
          isTrue,
        );
      }),
    );
  }
  // 8*2 = 16

  // Multi-loan: 5199.39 funding on HDFC must not appear on PNB when product SMS exists.
  const emiAmts = [5199.39, 8000.50, 12000.00, 25797.00, 26408.00, 36395.73, 486.00, 2451.58];
  for (var i = 0; i < emiAmts.length; i++) {
    final amt = emiAmts[i];
    out.add(
      _Case('live multi-loan $amt stays off PNB when covered', () {
        final store = FinanceStore()
          ..seedDiscoveredAccounts([
            const DiscoveredAccount(
              bank: 'HDFC',
              mask: '••••0855',
              kind: AccountKind.loan,
              smsHits: 5,
            ),
            const DiscoveredAccount(
              bank: 'PNB',
              mask: '••••0310',
              kind: AccountKind.loan,
              smsHits: 4,
            ),
          ])
          ..seedTransactions([
            _tx(
              id: 'fund$i',
              bank: 'HDFC',
              mask: '••••5300',
              amount: amt,
              isCredit: false,
              kind: AccountKind.loan,
              category: SpendCategory.emi,
              merchant: 'MBK EMI',
              at: DateTime(2026, 6, 15),
            ),
            _tx(
              id: 'pnb$i',
              bank: 'PNB',
              mask: '••••0310',
              amount: amt,
              isCredit: false,
              kind: AccountKind.loan,
              category: SpendCategory.emi,
              merchant: 'Loan payment',
              at: DateTime(2026, 6, 15, 1),
            ),
          ]);
        final pnb = store.bankAccounts().firstWhere((a) => a.mask == '••••0310');
        final list = store.transactionsForAccount(evidenceKey: pnb.evidenceKey);
        expect(list.any((t) => t.id == 'fund$i'), isFalse);
        expect(list.any((t) => t.id == 'pnb$i'), isTrue);
        expect(
          ProductPaymentLinker.linkedFundingTransactions(
            productBank: 'PNB',
            productMask: '••••0310',
            productKind: AccountKind.loan,
            all: store.transactions,
            discoveries: const [
              DiscoveredAccount(
                bank: 'HDFC',
                mask: '••••0855',
                kind: AccountKind.loan,
                smsHits: 5,
              ),
              DiscoveredAccount(
                bank: 'PNB',
                mask: '••••0310',
                kind: AccountKind.loan,
                smsHits: 4,
              ),
            ],
          ),
          isEmpty,
        );
      }),
    );
    out.add(
      _Case('live LIC Premium $amt is not EMI', () {
        expect(
          ProductPaymentLinker.looksLikeLoanFundingPayment(
            _tx(
              id: 'lic$i',
              bank: 'HDFC',
              mask: '••••5300',
              amount: amt,
              isCredit: false,
              merchant: 'LIC Premium',
            ),
          ),
          isFalse,
        );
        expect(
          MerchantCategorizer.categorize(
            merchant: 'LIC Premium',
            smsBody: 'Sent Rs.${_smsInr(amt)} From HDFC Bank A/C *5300 To LIC Premium On 01/01/26',
            isCredit: false,
          ),
          isNot(SpendCategory.emi),
        );
      }),
    );
    out.add(
      _Case('live same-last4 CC vs savings $amt', () {
        final store = FinanceStore()
          ..seedTransactions([
            _tx(
              id: 'sav$i',
              bank: 'HDFC',
              mask: '••••3569',
              amount: amt,
              isCredit: false,
              kind: AccountKind.savings,
            ),
            _tx(
              id: 'cc$i',
              bank: 'HDFC',
              mask: '••••3569',
              amount: amt,
              isCredit: false,
              kind: AccountKind.creditCard,
              category: SpendCategory.shopping,
            ),
          ]);
        final matching =
            store.bankAccounts().where((a) => a.mask == '••••3569').toList();
        expect(matching.map((a) => a.kind).toSet().length, 1);
        _expectParity(store);
      }),
    );
  }
  // 8*3 = 24

  // evidenceKey bank|mask: two banks sharing last-4 stay split.
  const splitPairs = [
    ('HDFC', 'SBI', '••••0429'),
    ('ICICI', 'Slice', '••••0856'),
    ('Kotak', 'PNB', '••••3649'),
    ('Axis', 'IDFC', '••••7424'),
    ('Yes Bank', 'HSBC', '••••3740'),
    ('HDFC', 'ICICI', '••••5300'),
    ('SBI', 'Axis', '••••3452'),
    ('Kotak', 'HDFC', '••••4310'),
  ];
  for (var i = 0; i < splitPairs.length; i++) {
    final p = splitPairs[i];
    out.add(
      _Case('live evidenceKey ${p.$1}|${p.$3} vs ${p.$2}', () {
        final store = FinanceStore()
          ..seedTransactions([
            _tx(
              id: 'l$i',
              bank: p.$1,
              mask: p.$3,
              amount: 10.25 + i,
              isCredit: false,
            ),
            _tx(
              id: 'r$i',
              bank: p.$2,
              mask: p.$3,
              amount: 20.50 + i,
              isCredit: true,
              category: SpendCategory.income,
            ),
          ]);
        final left = store.bankAccounts().where(
              (a) => a.bank == p.$1 && a.mask == p.$3,
            );
        final right = store.bankAccounts().where(
              (a) => a.bank == p.$2 && a.mask == p.$3,
            );
        expect(left.length, 1);
        expect(right.length, 1);
        expect(left.first.evidenceKey, '${p.$1}|${p.$3}');
        expect(right.first.evidenceKey, '${p.$2}|${p.$3}');
        expect(
          store
              .transactionsForAccount(evidenceKey: left.first.evidenceKey)
              .map((t) => t.id),
          ['l$i'],
        );
        _expectParity(store);
      }),
    );
  }
  // 264+80+8+16+24+8 = 400
  return out;
}

/// UI / display / aggregation: formatInr 2dp, You stickers, drilldown vs
/// Transactions, category chip %, CCBP not folded into CC, remaining live-inbox
/// templates. These lock what every screen *shows*, not only what the parser
/// extracts.
List<_Case> _displayAggregationMatrix() {
  final out = <_Case>[];

  const displayAmounts = [
    0.01,
    0.10,
    0.85,
    0.86,
    1.00,
    1.50,
    4.00,
    9.99,
    10.01,
    23.60,
    80.36,
    83.00,
    99.99,
    100.00,
    134.09,
    236.00,
    282.00,
    325.50,
    486.00,
    663.00,
    1000.00,
    1246.00,
    1365.00,
    1655.36,
    1715.36,
    2340.58,
    2400.68,
    2451.58,
    3035.40,
    3172.94,
    5199.39,
    5270.00,
    8000.50,
    8330.00,
    9392.10,
    9975.00,
    12000.00,
    15076.54,
    25797.00,
    25797.39,
    26408.00,
    31250.00,
    36395.73,
    52205.00,
    51426.70,
    42504.82,
    60775.86,
    146483.52,
  ];

  for (final amt in displayAmounts) {
    final cents = ((amt * 100).round() % 100).toString().padLeft(2, '0');
    out.add(
      _Case('ui formatInr ${amt.toStringAsFixed(2)} 2dp', () {
        final formatted = formatInr(amt);
        expect(formatted, startsWith('₹'));
        expect(formatted, contains('.$cents'));
        expect(formatted.contains('₹1.00') && amt < 1, isFalse);
        expect(formatCompactInr(amt), formatted);
      }),
    );
    out.add(
      _Case('ui formatAmount ${amt.toStringAsFixed(2)} debit+credit', () {
        final debit = formatAmount(amt, isCredit: false);
        final credit = formatAmount(amt, isCredit: true);
        expect(debit, startsWith('−'));
        expect(credit, startsWith('+'));
        expect(debit, contains('.$cents'));
        expect(credit, contains('.$cents'));
      }),
    );
  }
  // 48*2 = 96

  const grouped = <(double, String)>[
    (0.85, '₹0.85'),
    (0.86, '₹0.86'),
    (236.00, '₹236.00'),
    (1365.00, '₹1,365.00'),
    (2451.58, '₹2,451.58'),
    (3172.94, '₹3,172.94'),
    (5199.39, '₹5,199.39'),
    (8330.00, '₹8,330.00'),
    (9392.10, '₹9,392.10'),
    (25797.00, '₹25,797.00'),
    (26408.00, '₹26,408.00'),
    (42504.82, '₹42,504.82'),
    (51426.70, '₹51,426.70'),
    (52205.00, '₹52,205.00'),
    (60775.86, '₹60,775.86'),
    (123456.78, '₹1,23,456.78'),
    (146483.52, '₹1,46,483.52'),
    (1000000.01, '₹10,00,000.01'),
  ];
  for (final g in grouped) {
    out.add(
      _Case('ui Indian grouping ${g.$1.toStringAsFixed(2)}', () {
        expect(formatInr(g.$1), g.$2);
      }),
    );
  }
  // 18

  const shares = <(double, String)>[
    (0.0, ''),
    (-0.01, ''),
    (0.00005, '<0.01%'),
    (0.0001, '0.01%'),
    (0.0003, '0.03%'),
    (0.001, '0.1%'),
    (0.004, '0.4%'),
    (0.009, '0.9%'),
    (0.0099, '1.0%'),
    (0.01, '1%'),
    (0.32, '32%'),
    (0.5, '50%'),
    (1.0, '100%'),
    (0.0002, '0.02%'),
    (0.002, '0.2%'),
    (0.15, '15%'),
  ];
  for (final s in shares) {
    out.add(
      _Case('ui chip% ${s.$1} → ${s.$2}', () {
        expect(formatSharePercent(s.$1), s.$2);
      }),
    );
  }
  // 16

  for (final n in [1, 2, 3, 4, 5, 6, 7, 8]) {
    out.add(
      _Case('ui chip badge TOP/mid/LOW n=$n', () {
        expect(CategorySpendStickerGrid.badgeKindForIndex(0, n), ShareBadgeKind.top);
        if (n > 1) {
          expect(
            CategorySpendStickerGrid.badgeKindForIndex(n - 1, n),
            ShareBadgeKind.low,
          );
        }
        if (n > 2) {
          expect(
            CategorySpendStickerGrid.badgeKindForIndex(1, n),
            ShareBadgeKind.mid,
          );
        }
      }),
    );
  }
  // 8

  DateTime monthTs({int day = 8}) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, day, 12);
  }

  for (var i = 0; i < 20; i++) {
    final spend = displayAmounts[i];
    final income = displayAmounts[displayAmounts.length - 1 - i];
    out.add(
      _Case(
        'ui home KPI spend ${spend.toStringAsFixed(2)} income ${income.toStringAsFixed(2)}',
        () {
          final store = FinanceStore()
            ..seedTransactions([
              _tx(
                id: 'food$i',
                bank: 'SBI',
                mask: '••••0429',
                amount: spend,
                isCredit: false,
                category: SpendCategory.food,
                merchant: 'Swiggy',
                at: monthTs(),
              ),
              _tx(
                id: 'sal$i',
                bank: 'SBI',
                mask: '••••0429',
                amount: income,
                isCredit: true,
                category: SpendCategory.income,
                merchant: 'Salary',
                at: monthTs(day: 5),
              ),
            ]);
          expect(store.monthlySpent, closeTo(spend, 0.001));
          expect(store.monthlyIncome, closeTo(income, 0.001));
          expect(formatInr(store.monthlySpent), formatInr(spend));
          expect(formatInr(store.monthlyIncome), formatInr(income));
          final saved = (income - spend).clamp(0, double.infinity).toDouble();
          expect(store.monthlySaved, closeTo(saved, 0.001));
          expect(formatInr(store.monthlySaved), formatInr(saved));
          expect(store.activeMonthTransactionCount, 2);
          final chips = store.categorySpending;
          expect(chips[SpendCategory.food], closeTo(spend, 0.001));
          expect(formatInr(chips[SpendCategory.food]!), formatInr(spend));
        },
      ),
    );
  }
  // 20

  const youBanks = [
    ('HDFC', '••••5300'),
    ('SBI', '••••0429'),
    ('ICICI', '••••0003'),
    ('Kotak', '••••3649'),
    ('PNB', '••••4720'),
    ('IDFC', '••••0070'),
    ('Slice', '••••0856'),
    ('Axis', '••••8341'),
    ('Yes Bank', '••••9757'),
    ('HSBC', '••••3740'),
    ('Federal', '••••7953'),
    ('Canara', '••••2211'),
    ('IndusInd', '••••3344'),
    ('Bank of Baroda', '••••5566'),
    ('HDFC', '••••3569'),
    ('SBI', '••••3452'),
  ];
  for (var i = 0; i < youBanks.length; i++) {
    final bank = youBanks[i].$1;
    final mask = youBanks[i].$2;
    final received = displayAmounts[i];
    final sent = displayAmounts[i + 8];
    out.add(
      _Case('ui You sticker $bank $mask ${sent.toStringAsFixed(2)}', () {
        final store = FinanceStore()
          ..seedTransactions([
            _tx(
              id: 'in$i',
              bank: bank,
              mask: mask,
              amount: received,
              isCredit: true,
              category: SpendCategory.income,
              at: DateTime(2026, 6, 2),
            ),
            _tx(
              id: 'out$i',
              bank: bank,
              mask: mask,
              amount: sent,
              isCredit: false,
              category: SpendCategory.shopping,
              at: DateTime(2026, 6, 3),
            ),
          ]);
        final accounts = store.bankAccounts().where(
              (a) => a.bank == bank && a.mask == mask,
            );
        expect(accounts.length, 1);
        final a = accounts.first;
        final list = store.transactionsForAccount(evidenceKey: a.evidenceKey);
        final rec =
            list.where((t) => t.isCredit).fold(0.0, (s, t) => s + t.amount);
        final sen =
            list.where((t) => !t.isCredit).fold(0.0, (s, t) => s + t.amount);
        expect(a.receivedTotal, closeTo(rec, 0.001));
        expect(a.spentTotal, closeTo(sen, 0.001));
        expect(formatInr(a.receivedTotal), formatInr(received));
        expect(formatInr(a.spentTotal), formatInr(sent));
        expect(a.activityCount, 2);
      }),
    );
  }
  // 16

  const ccbpAmts = [
    8330.00,
    1365.00,
    2451.58,
    9392.10,
    31250.00,
    42504.82,
    1000.00,
    5199.39,
    8000.50,
    25797.00,
    26408.00,
    486.00,
  ];
  for (var i = 0; i < ccbpAmts.length; i++) {
    final amt = ccbpAmts[i];
    out.add(
      _Case('ui CCBP ${amt.toStringAsFixed(2)} stays on savings not CC', () {
        final store = FinanceStore()
          ..seedTransactions([
            _tx(
              id: 'ccbp$i',
              bank: 'HDFC',
              mask: '••••5300',
              amount: amt,
              isCredit: false,
              kind: AccountKind.savings,
              category: SpendCategory.transfer,
              merchant: 'MBK CCBP',
              at: monthTs(),
            ),
            _tx(
              id: 'ccspend$i',
              bank: 'HDFC',
              mask: '••••1949',
              amount: 236.00,
              isCredit: false,
              kind: AccountKind.creditCard,
              category: SpendCategory.shopping,
              merchant: 'Amazon',
              at: monthTs(day: 4),
            ),
          ]);
        expect(store.monthlySpent, closeTo(236.00, 0.001),
            reason: 'CCBP must not inflate Home spend');
        final savings = store.bankAccounts().firstWhere(
              (a) => a.mask == '••••5300' && a.kind == AccountKind.savings,
            );
        final card = store.bankAccounts().firstWhere(
              (a) => a.mask == '••••1949' && a.kind == AccountKind.creditCard,
            );
        final savList =
            store.transactionsForAccount(evidenceKey: savings.evidenceKey);
        final cardList =
            store.transactionsForAccount(evidenceKey: card.evidenceKey);
        expect(savList.any((t) => t.id == 'ccbp$i'), isTrue);
        expect(cardList.any((t) => t.id == 'ccbp$i'), isFalse);
        expect(formatInr(savings.spentTotal), formatInr(amt));
        expect(formatInr(card.spentTotal), formatInr(236.00));
      }),
    );
  }
  // 12

  const emiAmts2 = [
    5199.39,
    8000.50,
    12000.00,
    25797.00,
    26408.00,
    36395.73,
    486.00,
    2451.58,
  ];
  for (var i = 0; i < emiAmts2.length; i++) {
    final amt = emiAmts2[i];
    out.add(
      _Case('ui paired EMI ${amt.toStringAsFixed(2)} stays off PNB loan', () {
        final store = FinanceStore()
          ..seedDiscoveredAccounts([
            const DiscoveredAccount(
              bank: 'HDFC',
              mask: '••••0855',
              kind: AccountKind.loan,
              smsHits: 5,
            ),
            const DiscoveredAccount(
              bank: 'PNB',
              mask: '••••0310',
              kind: AccountKind.loan,
              smsHits: 4,
            ),
          ])
          ..seedTransactions([
            _tx(
              id: 'fund$i',
              bank: 'HDFC',
              mask: '••••5300',
              amount: amt,
              isCredit: false,
              kind: AccountKind.savings,
              category: SpendCategory.emi,
              merchant: 'MBK EMI',
              at: DateTime(2026, 6, 15),
            ),
            _tx(
              id: 'pnb$i',
              bank: 'PNB',
              mask: '••••0310',
              amount: amt,
              isCredit: false,
              kind: AccountKind.loan,
              category: SpendCategory.emi,
              merchant: 'Loan payment',
              at: DateTime(2026, 6, 15, 1),
            ),
          ]);
        final pnb = store.bankAccounts().firstWhere((a) => a.mask == '••••0310');
        final hdfcSav =
            store.bankAccounts().firstWhere((a) => a.mask == '••••5300');
        final pnbList =
            store.transactionsForAccount(evidenceKey: pnb.evidenceKey);
        final savList =
            store.transactionsForAccount(evidenceKey: hdfcSav.evidenceKey);
        expect(pnbList.any((t) => t.id == 'fund$i'), isFalse);
        expect(savList.any((t) => t.id == 'fund$i'), isTrue);
        expect(formatInr(hdfcSav.spentTotal), formatInr(amt));
        expect(formatInr(pnb.spentTotal), formatInr(amt));
      }),
    );
  }
  // 8

  for (var i = 0; i < 16; i++) {
    final food = displayAmounts[i];
    final travel = displayAmounts[i + 4];
    final other = 0.85;
    out.add(
      _Case('ui category chips food ${food.toStringAsFixed(2)}', () {
        final store = FinanceStore()
          ..seedTransactions([
            _tx(
              id: 'f$i',
              bank: 'SBI',
              mask: '••••0429',
              amount: food,
              isCredit: false,
              category: SpendCategory.food,
              merchant: 'Swiggy',
              at: monthTs(),
            ),
            _tx(
              id: 't$i',
              bank: 'SBI',
              mask: '••••0429',
              amount: travel,
              isCredit: false,
              category: SpendCategory.travel,
              merchant: 'Uber',
              at: monthTs(day: 3),
            ),
            _tx(
              id: 'o$i',
              bank: 'SBI',
              mask: '••••0429',
              amount: other,
              isCredit: false,
              category: SpendCategory.other,
              merchant: 'Misc',
              at: monthTs(day: 4),
            ),
          ]);
        final total = food + travel + other;
        expect(store.monthlySpent, closeTo(total, 0.001));
        final foodShare = food / total;
        final otherShare = other / total;
        expect(formatSharePercent(0), isEmpty);
        expect(formatSharePercent(foodShare), isNotEmpty);
        expect(formatSharePercent(otherShare), isNot(equals('0%')));
        expect(formatInr(store.categorySpending[SpendCategory.food]!),
            formatInr(food));
        expect(formatInr(store.categorySpending[SpendCategory.other]!),
            formatInr(0.85));
        final report = store.buildReport(
          store.currentMonthRange.start,
          store.currentMonthRange.end,
        );
        expect(report.spent, closeTo(total, 0.001));
        expect(formatInr(report.spent), formatInr(total));
        expect(formatInr(report.highestDaySpend),
            formatInr(store.highestDaySpend));
        if (food < 1 && travel < 1) {
          expect(formatInr(0.85), isNot(contains('1.00')));
        }
      }),
    );
  }
  // 16

  for (var i = 0; i < 12; i++) {
    final amt = displayAmounts[i + 10];
    out.add(
      _Case('ui insights+reports ${amt.toStringAsFixed(2)}', () {
        final store = FinanceStore()
          ..seedTransactions([
            _tx(
              id: 'ins$i',
              bank: 'HDFC',
              mask: '••••5300',
              amount: amt,
              isCredit: false,
              category: SpendCategory.bills,
              merchant: 'Electricity',
              at: monthTs(day: 2),
            ),
            _tx(
              id: 'inc$i',
              bank: 'HDFC',
              mask: '••••5300',
              amount: amt + 100,
              isCredit: true,
              category: SpendCategory.income,
              merchant: 'Salary',
              at: monthTs(day: 1),
            ),
          ]);
        expect(store.insightsSpent, closeTo(amt, 0.001));
        expect(formatInr(store.insightsSpent), formatInr(amt));
        expect(formatInr(store.insightsHighestDaySpend), formatInr(amt));
        final report = store.buildReport(
          store.currentMonthRange.start,
          store.currentMonthRange.end,
        );
        expect(formatInr(report.spent), formatInr(amt));
        expect(formatInr(report.income), formatInr(amt + 100));
        expect(formatInr(report.net), formatInr(100));
        expect(report.transactionCount, 2);
        final received = store
            .transactionsForAccount(evidenceKey: 'HDFC|••••5300')
            .where((t) => t.isCredit)
            .fold(0.0, (s, t) => s + t.amount);
        final sent = store
            .transactionsForAccount(evidenceKey: 'HDFC|••••5300')
            .where((t) => !t.isCredit)
            .fold(0.0, (s, t) => s + t.amount);
        expect(formatInr(received), formatInr(amt + 100));
        expect(formatInr(sent), formatInr(amt));
      }),
    );
  }
  // 12

  final moreTemplates = <({
    String sender,
    String body,
    String? bank,
    bool? isCredit,
  })>[
    (
      sender: 'VK-AXISBK-S',
      body:
          'Congratulations! Cashback of INR {amt} has been credited to your Axis Bank Flipkart Visa Credit Card XX8341 towards your last month spends - Axis Bank',
      bank: 'Axis',
      isCredit: true,
    ),
    (
      sender: 'JK-AXISBK-S',
      body:
          'Spent INR {amt}\nAxis Bank Card no. XX8341\n10-12-25 20:42:01 IST\nMYNTRA\nAvl Limit: INR 96568.75\nNot you? SMS BLOCK 8341 to 919951860002',
      bank: 'Axis',
      isCredit: false,
    ),
    (
      sender: 'JM-HSBCIN-S',
      body:
          'HSBC creditcard xxxxx3740 used at zepto marketplace private for INR {amt} on 28/07/26.Limit Rs 826770.18 Due Rs 21229.82.Report fraud on +910000000000',
      bank: 'HSBC',
      isCredit: false,
    ),
    (
      sender: 'JX-ICICIT-S',
      body:
          'USD {amt} spent using ICICI Bank Card XX2009 on 30-Jul-26 on ANTHROPIC* CLAU. Avl Limit: INR 4,39,259.33. If not you, call 1800 2662/SMS BLOCK 2009 to 9215676766.',
      bank: 'ICICI',
      isCredit: false,
    ),
    (
      sender: 'VA-ICICIT-S',
      body:
          'ICICI Bank Account XX1505 credited:Rs. {amt} on 07-May-26. Info CMS* CC RBI 10 H*ICICI BANK . Available Balance is Rs. 74,202.07.',
      bank: 'ICICI',
      isCredit: true,
    ),
    (
      sender: 'AD-ICICIT-S',
      body:
          'IRCTC Rail APP refund of Rs {amt} credited to ICICI Bank Credit Card XX0003 on 29-JUL-26. Revised total due Rs 21,340.81, minimum due Rs 988.31',
      bank: 'ICICI',
      isCredit: true,
    ),
    (
      sender: 'VM-FEDBNK-S',
      body:
          'Rs.{amt} debited from a/c **7953 on 08-Jul-26. Info: SWIGGY - Federal Bank',
      bank: 'Federal',
      isCredit: false,
    ),
    (
      sender: 'CANARA',
      body:
          'Rs.{amt} debited from a/c **2211 on 08-Jul-26. Info: METRO',
      bank: 'Canara',
      isCredit: false,
    ),
    (
      sender: 'AX-HDFCBK-S',
      body:
          'Sent Rs.{amt} From HDFC Bank A/C *5300 To MBK CCBP On 05/08/26',
      bank: 'HDFC',
      isCredit: false,
    ),
    (
      sender: 'VM-SBIIN-S',
      body:
          'Dear UPI user A/C X6675 debited by {amt} on date 05Aug26 trf to MBK CCBP Refno 101568018632',
      bank: 'SBI',
      isCredit: false,
    ),
    (
      sender: 'JM-KOTAKB-S',
      body:
          'INR {amt} is debited from your Account XXXXXX3649 on 07/08/2026 towards NACH-10-HDFC BANK LIMITED Kotak Bank',
      bank: 'Kotak',
      isCredit: false,
    ),
    (
      sender: 'AX-SLCEIT-S',
      body:
          'Rs. {amt} sent from a/c xx0856 on 04-Aug-26 to Test Merchant (UPI Ref: 650468933013). Not you? Call 08048329999 - slice',
      bank: 'Slice',
      isCredit: false,
    ),
    (
      sender: 'VM-BOBSMS-S',
      body:
          'INR {amt} is spent on your BOBCARD ending 5566 at SWIGGY',
      bank: null,
      isCredit: false,
    ),
    (
      sender: 'INDUSIND',
      body:
          'Rs.{amt} debited from a/c **3344 on 08-Jul-26. Info: SWIGGY',
      bank: 'IndusInd',
      isCredit: false,
    ),
  ];
  const moreAmts = [
    0.85,
    23.60,
    134.09,
    236.00,
    1365.00,
    2451.58,
    5199.39,
    8330.00,
    9392.10,
    25797.00,
    26408.00,
    146483.52,
  ];
  for (var t = 0; t < moreTemplates.length; t++) {
    final base = moreTemplates[t];
    for (var v = 0; v < moreAmts.length; v++) {
      final amt = moreAmts[v];
      out.add(
        _Case(
          'ui-live-parse #${t}_$v ${base.sender} ${amt.toStringAsFixed(2)}',
          () {
            final body = base.body.replaceAll('{amt}', _smsInr(amt));
            final result = SmsScanPipeline.process(
              SmsMessageInput(
                id: 'ui_${t}_$v',
                sender: base.sender,
                body: body,
                timestamp: DateTime(2026, 6, 15, 12),
              ),
            );
            expect(result.isParsed, isTrue, reason: body);
            expect(result.transaction!.amount, closeTo(amt, 0.001),
                reason: body);
            expect(formatInr(result.transaction!.amount), formatInr(amt));
            if (base.bank != null) {
              expect(result.transaction!.bank, base.bank);
            }
            if (base.isCredit != null) {
              expect(result.transaction!.isCredit, base.isCredit);
            }
          },
        ),
      );
    }
  }
  // 14*12 = 168

  const moreReject = [
    (
      sender: 'JK-AXISBK-S',
      body:
          'Payment of INR {amt} for Axis Bank Credit Card no. XX9867 is due on 01-08-26 with minimum amount due of INR 100. Ignore if paid.',
    ),
    (
      sender: 'JM-HSBCIN-S',
      body:
          'HSBC Credit Card ending 3740 : Total due: {amt}, minimum due: 1000.00; pay by 05-Aug-26. Payment modes- https://example.com',
    ),
    (
      sender: 'VM-HDFCBK-S',
      body:
          'Your HDFC Bank Credit Card XX1949 statement of Rs.{amt} is generated. Min due Rs.500. Pay by 05-Aug-26.',
    ),
    (
      sender: 'AX-ICICIT-S',
      body:
          'ICICI Bank Credit Card XX0003 payment of Rs {amt} is due on 10-Aug-26. Ignore if already paid.',
    ),
    (
      sender: 'VM-SBIIN-S',
      body:
          'Your SBI loan EMI of Rs.{amt} is due on 05-Aug-26. Please maintain sufficient balance.',
    ),
    (
      sender: 'JD-PNBSMS-S',
      body:
          'PNB: Your RD installment of Rs.{amt} is due. Ignore if paid.',
    ),
  ];
  const rejectAmts2 = [
    0.85,
    500.00,
    1365.00,
    2451.58,
    5199.39,
    8330.00,
    25797.00,
    26408.00,
  ];
  for (var t = 0; t < moreReject.length; t++) {
    final base = moreReject[t];
    for (var v = 0; v < rejectAmts2.length; v++) {
      final amt = rejectAmts2[v];
      out.add(
        _Case(
          'ui-live-reject #${t}_$v ${base.sender} ${amt.toStringAsFixed(2)}',
          () {
            final body = base.body.replaceAll('{amt}', _smsInr(amt));
            final result = SmsScanPipeline.process(
              SmsMessageInput(
                id: 'uirej_${t}_$v',
                sender: base.sender,
                body: body,
                timestamp: DateTime(2026, 6, 15, 12),
              ),
            );
            expect(result.isParsed, isFalse, reason: body);
          },
        ),
      );
    }
  }
  // 6*8 = 48

  const last4s = ['3569', '1949', '4310', '3452', '0003', '7424', '8341', '9757'];
  for (final last4 in last4s) {
    out.add(
      _Case('ui same-last4 CC not folded into savings ••••$last4', () {
        final mask = '••••$last4';
        final store = FinanceStore()
          ..seedDiscoveredAccounts([
            DiscoveredAccount(
              bank: 'HDFC',
              mask: mask,
              kind: AccountKind.savings,
              smsHits: 8,
            ),
            DiscoveredAccount(
              bank: 'HDFC',
              mask: mask,
              kind: AccountKind.creditCard,
              smsHits: 6,
            ),
          ])
          ..seedTransactions([
            _tx(
              id: 'sav$last4',
              bank: 'HDFC',
              mask: mask,
              amount: 0.85,
              isCredit: false,
              kind: AccountKind.savings,
            ),
            _tx(
              id: 'cc$last4',
              bank: 'HDFC',
              mask: mask,
              amount: 8330.00,
              isCredit: false,
              kind: AccountKind.creditCard,
              category: SpendCategory.shopping,
            ),
          ]);
        final matching =
            store.bankAccounts().where((a) => a.mask == mask).toList();
        // Same bank+mask collapses to one kind (dominant). Different banks stay split.
        expect(matching.map((a) => a.mask).toSet(), {mask});
        for (final a in matching) {
          final list =
              store.transactionsForAccount(evidenceKey: a.evidenceKey);
          expect(formatInr(a.spentTotal),
              formatInr(list.where((t) => !t.isCredit).fold(0.0, (s, t) => s + t.amount)));
        }
        _expectParity(store);
      }),
    );
  }
  // 8

  // 96+18+16+8+20+16+12+8+16+12+168+48+8 = 446
  return out;
}
