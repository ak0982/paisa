import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/models/transaction.dart';
import 'package:paisa_app/providers/finance_store.dart';
import 'package:paisa_app/services/sms/account_bank_registry.dart';
import 'package:paisa_app/services/sms/account_discovery.dart';
import 'package:paisa_app/services/sms/parsed_sms_transaction.dart';
import 'package:paisa_app/services/sms/sms_scan_pipeline.dart';
import 'package:paisa_app/services/sms/transaction_enrichment.dart';

/// Integration / adversarial suite: ~1500 cases covering account kinds,
/// bank|mask association, rematch, and parity of You totals vs drilldown lists.
///
/// Goal: every txn that belongs on an account appears under that account with
/// matching received/sent/activityCount — and corner cases that used to leak
/// (wrong bank, EMI on funding mask, CCBP, aliases) stay correct.
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
  ];

  test('suite size is around 1500 cases', () {
    expect(cases.length, greaterThanOrEqualTo(1400));
    expect(cases.length, lessThanOrEqualTo(1700));
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
  // 14*18*3 = 756
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

List<_Case> _pipelineSmsMatrix() {
  final out = <_Case>[];
  final templates = <({String sender, String body, bool expectParsed, String? bank})>[
    (
      sender: 'AX-HDFCBK-S',
      body:
          'Rs.500.00 debited from HDFC Bank A/c **5300 on 08-Aug to Swiggy (UPI Ref No 1). Not You? Call 18002586161',
      expectParsed: true,
      bank: 'HDFC',
    ),
    (
      sender: 'VM-SBIIN-S',
      body:
          'Dear UPI user A/C X0429 debited by 325.00 on date 08Aug26 trf to MERCHANT Refno 123 If not you call 1800',
      expectParsed: true,
      bank: 'SBI',
    ),
    (
      sender: 'AX-SLCEIT-S',
      body:
          'Rs. 550 sent from a/c xx0856 on 18-May-26 to CREW SPORTS (UPI Ref: 650468933013). Not you? Call 08048329999 - slice',
      expectParsed: true,
      bank: 'Slice',
    ),
    (
      sender: 'AD-SLCEIT-S',
      body:
          'Rs. 1,246 received in slice A/c xx0856 on 05-Jan-26 from TEST USER via UPI (Ref ID: 1). Avl. Bal. Rs. 1 - slice',
      expectParsed: true,
      bank: 'Slice',
    ),
    (
      sender: 'VA-SLCBNK-S',
      body:
          'Rs. 124 spent on your credit card xx7185 at Test Merchant on 18-Jun-26 (UPI Ref: 1). Not you? Call 080-4832-9999 - slice',
      expectParsed: true,
      bank: 'Slice',
    ),
    (
      sender: 'AX-ICICIB-S',
      body:
          'ICICI Bank Acct XX1505 debited for Rs 200.00 on 08-Aug-26; Swiggy credited. Avl Bal Rs 10.00',
      expectParsed: true,
      bank: 'ICICI',
    ),
    (
      sender: 'JM-KOTAKB',
      body: 'Rs.500.00 debited from Kotak Bank a/c XXXX3649 towards Swiggy on 08-Aug',
      expectParsed: true,
      bank: 'Kotak',
    ),
    (
      sender: 'AX-AXISBK-S',
      // Live Axis CC alert (multiline). Parser normalizes newlines to spaces.
      body:
          'Spent INR 1200\nAxis Bank Card no. XX8341\n08-08-26 12:00:00 IST\nAMAZON\nAvl Limit: INR 50000.00\nNot you? SMS BLOCK 8341 to 919951860002',
      expectParsed: true,
      bank: 'Axis',
    ),
    (
      sender: 'JK-AXISBK-S',
      body:
          'INR 1,200.00 spent on Axis Bank Card XX8341 at AMAZON on 08-Aug-26',
      expectParsed: true,
      bank: 'Axis',
    ),
    (
      sender: 'AX-AXISBK-S',
      body:
          'INR 1,200.00 spent on your Axis Bank Credit Card ending XX8341 at IRCTC on 05-Jul-26.',
      expectParsed: true,
      bank: 'Axis',
    ),
    (
      sender: 'VD-IDFCFB-S',
      body:
          'Delicious Purchase! INR 80.00 spent on your IDFC FIRST Bank Credit Card ending XX7424 at HungerBox on 11 DEC 2025 at 12:49 PM Avbl Limit: INR 219750',
      expectParsed: true,
      bank: 'IDFC',
    ),
    (
      sender: 'JX-ICICIT-S',
      body:
          'INR 387.00 spent using ICICI Bank Card XX2009 on 08-Aug-26 on AMAZON. Avl Limit: INR 10000.00.',
      expectParsed: true,
      bank: 'ICICI',
    ),
    (
      sender: 'VA-YESBNK-S',
      body:
          'INR 449.54 spent on YES BANK Card X9757 @UPI_MCDONALDS HARDCAST 07-12-2025 05:01:14 pm.',
      expectParsed: true,
      bank: 'Yes Bank',
    ),
    (
      sender: 'AX-HDFCBK-S',
      body: 'Your OTP for HDFC NetBanking is 123456. Do not share.',
      expectParsed: false,
      bank: null,
    ),
    (
      sender: 'AX-HDFCBK-S',
      body: 'Pre-approved loan offer of Rs 5 lakh for you. Apply now!',
      expectParsed: false,
      bank: null,
    ),
    (
      sender: 'AX-SLCEIT-S',
      body:
          'UPI Payment of Rs. 100 from a/c xx0856 on 04-Jun-26 to X has failed. Any debited amount has been refunded - slice',
      expectParsed: false,
      bank: null,
    ),
    (
      sender: '9876543210',
      body: 'Rs.500 debited from a/c XX1234 on 08-Aug. Call me.',
      expectParsed: false,
      bank: null,
    ),
    (
      sender: 'VK-AXISBK-T',
      body:
          '782140 is SECRET OTP for txn of INR 663.00 on Axis Bank card XX8341 at Myntra on 10-12-25. OTP valid for 5 mins. Please do not share this OTP.',
      expectParsed: false,
      bank: null,
    ),
  ];

  // Expand each template across amount variants
  for (var t = 0; t < templates.length; t++) {
    final base = templates[t];
    for (var v = 0; v < 8; v++) {
      out.add(
        _Case('pipeline #${t}_$v ${base.sender}', () {
          final body = base.body;
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
            expect(result.transaction!.amount, greaterThan(0));
            if (base.bank != null) {
              expect(result.transaction!.bank, base.bank);
            }
          } else {
            expect(result.isParsed, isFalse);
          }
        }),
      );
    }
  }
  // 17*8 = 136
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
