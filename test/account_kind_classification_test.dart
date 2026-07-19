// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/models/transaction.dart';
import 'package:paisa_app/providers/finance_store.dart';
import 'package:paisa_app/services/sms/account_bank_registry.dart';
import 'package:paisa_app/services/sms/account_discovery.dart';
import 'package:paisa_app/services/sms/parsed_sms_transaction.dart';
import 'package:paisa_app/services/sms/sms_parser.dart';
import 'package:paisa_app/services/sms/sms_scan_pipeline.dart';
import 'package:paisa_app/services/sms/transaction_enrichment.dart';

import 'helpers/dummy_data.dart';
import '../tool/analyze_sms_export.dart' show parseAdbSmsExport;

void main() {
  group('bankAccounts() derives kind from transaction evidence', () {
    test('mask with credit-card transactions classifies as credit card', () {
      final store = FinanceStore()
        ..seedTransactions([
          // No discovered credit card for this mask — only transaction evidence.
          _txn(
            id: '1',
            bank: 'SBI',
            mask: '••••3452',
            kind: AccountKind.creditCard,
            amount: 1200,
          ),
          _txn(
            id: '2',
            bank: 'SBI',
            mask: '••••3452',
            kind: AccountKind.creditCard,
            amount: 800,
          ),
        ]);

      final account = store
          .bankAccounts()
          .firstWhere((a) => a.mask == '••••3452');
      expect(account.kind, AccountKind.creditCard);
      expect(account.name, contains('Credit Card'));
    });

    test('on-card spends dominate a stray savings row => credit card', () {
      final store = FinanceStore()
        ..seedTransactions([
          _txn(
            id: '1',
            bank: 'HDFC',
            mask: '••••7550',
            kind: AccountKind.creditCard,
            amount: 500,
          ),
          _txn(
            id: '2',
            bank: 'HDFC',
            mask: '••••7550',
            kind: AccountKind.creditCard,
            amount: 900,
          ),
          // A single stray savings-looking row does not outvote real card spends.
          _txn(
            id: '3',
            bank: 'HDFC',
            mask: '••••7550',
            kind: AccountKind.savings,
            amount: 300,
          ),
        ]);

      final account = store
          .bankAccounts()
          .firstWhere((a) => a.mask == '••••7550');
      expect(account.kind, AccountKind.creditCard);
    });

    test('savings account that pays a CC bill (CCBP debit) stays savings', () {
      final store = FinanceStore()
        ..seedTransactions([
          for (var i = 0; i < 8; i++)
            _txn(
              id: 'upi$i',
              bank: 'HDFC',
              mask: '••••5300',
              kind: AccountKind.savings,
              amount: 200.0 + i,
              isCredit: i.isEven,
            ),
          // CCBP bill payments are enriched to accountKind=creditCard but their
          // merchant marks them as funding-side "Credit card bill payment"
          // debits — they must not flip the savings account into a card.
          for (var i = 0; i < 3; i++)
            _ccbpTxn(id: 'ccbp$i', bank: 'HDFC', mask: '••••5300', amount: 5000),
        ]);

      final account = store
          .bankAccounts()
          .firstWhere((a) => a.mask == '••••5300');
      expect(account.kind, AccountKind.savings);
    });

    test('CCBP bill payments alone (no card routing) stay savings-side', () {
      // Even with only bill-payment debits on a mask, the money-movement is a
      // bank account being debited, so it is savings — not a credit card.
      final store = FinanceStore()
        ..seedTransactions([
          for (var i = 0; i < 4; i++)
            _ccbpTxn(id: 'ccbp$i', bank: 'SBI', mask: '••••0429', amount: 3000),
          _txn(
            id: 'sal',
            bank: 'SBI',
            mask: '••••0429',
            kind: AccountKind.savings,
            amount: 90000,
            isCredit: true,
          ),
        ]);

      final account = store
          .bankAccounts()
          .firstWhere((a) => a.mask == '••••0429');
      expect(account.kind, AccountKind.savings);
    });

    test('salary + UPI/NEFT credit and debit mask => savings', () {
      final store = FinanceStore()
        ..seedTransactions([
          _txn(
            id: 'sal',
            bank: 'Kotak',
            mask: '••••3649',
            kind: AccountKind.savings,
            amount: 120000,
            isCredit: true,
          ),
          _txn(
            id: 'upi1',
            bank: 'Kotak',
            mask: '••••3649',
            kind: AccountKind.savings,
            amount: 450,
          ),
          _txn(
            id: 'neft',
            bank: 'Kotak',
            mask: '••••3649',
            kind: AccountKind.savings,
            amount: 15000,
            isCredit: true,
          ),
        ]);

      final account = store
          .bankAccounts()
          .firstWhere((a) => a.mask == '••••3649');
      expect(account.kind, AccountKind.savings);
    });

    test('mask with loan/EMI transactions classifies as loan', () {
      final store = FinanceStore()
        ..seedTransactions([
          _txn(
            id: '1',
            bank: 'ICICI',
            mask: '••••2009',
            kind: AccountKind.loan,
            amount: 15000,
          ),
          _txn(
            id: '2',
            bank: 'ICICI',
            mask: '••••2009',
            kind: AccountKind.loan,
            amount: 15000,
          ),
        ]);

      final account = store
          .bankAccounts()
          .firstWhere((a) => a.mask == '••••2009');
      expect(account.kind, AccountKind.loan);
    });

    test('plain savings activity stays savings', () {
      final store = FinanceStore()
        ..seedTransactions([
          _txn(
            id: '1',
            bank: 'HDFC',
            mask: '••••4321',
            kind: AccountKind.savings,
            amount: 500,
          ),
          _txn(
            id: '2',
            bank: 'HDFC',
            mask: '••••4321',
            kind: AccountKind.savings,
            amount: 900,
            isCredit: true,
          ),
        ]);

      final account = store
          .bankAccounts()
          .firstWhere((a) => a.mask == '••••4321');
      expect(account.kind, AccountKind.savings);
    });

    test('one stray NACH loan EMI does not flip a savings account to loan', () {
      final store = FinanceStore()
        ..seedTransactions([
          for (var i = 0; i < 6; i++)
            _txn(
              id: 's$i',
              bank: 'HDFC',
              mask: '••••4321',
              kind: AccountKind.savings,
              amount: 100.0 + i,
            ),
          // A NACH loan EMI debited from the same savings mask (loan not
          // separately discovered) should not dominate the many savings rows.
          _txn(
            id: 'emi',
            bank: 'HDFC',
            mask: '••••4321',
            kind: AccountKind.loan,
            amount: 8500,
          ),
        ]);

      final account = store
          .bankAccounts()
          .firstWhere((a) => a.mask == '••••4321');
      expect(account.kind, AccountKind.savings);
    });

    test('end-to-end: realistic CC SMS bodies surface as a credit-card account',
        () {
      // Discovery never fires on these shapes, but resolveAccountKind does — the
      // account must still classify as a credit card.
      final bodies = [
        'Rs.2,499.00 spent on your SBI Credit Card XX3452 at AMAZON on '
            '05-Jul-26. Avl Lmt Rs.1,20,000.',
        'Rs.999.00 spent on your SBI Credit Card XX3452 at SWIGGY on 06-Jul-26.',
      ];
      final store = _storeFromBodies(
        bodies.map((b) => (sender: 'SBICRD', body: b)).toList(),
      );

      final cards = store
          .bankAccounts()
          .where((a) => a.kind == AccountKind.creditCard)
          .toList();
      expect(cards, isNotEmpty,
          reason: 'CC spends must produce a credit-card account');
    });

    test('S64 parity: dummy history still dedups masks & keeps kinds', () {
      final store = FinanceStore()..seedTransactions(dummyTransactionHistory());
      final accounts = store.bankAccounts();
      expect(accounts.length, greaterThan(1));
      final masks = accounts.map((a) => a.mask).toSet();
      expect(masks.length, accounts.length);
    });
  });

  group('real SMS dump diagnostic', () {
    // Known ground truth for this user's inbox (validation only — never
    // hardcoded in production classification).
    const knownSavingsMasks = [
      '••••5300', // HDFC
      '••••0429', // SBI
      '••••6675', // SBI
      '••••3649', // Kotak
    ];
    const knownCardMasks = [
      '••••3452', // SBI
      '••••2009', // ICICI
      '••••7424', // IDFC
      '••••8341', // Axis
      '••••8422', // Axis
      '••••9867', // Axis
      '••••7550', // HDFC
      '••••9757', // Yes
      '••••9516', // BOB
    ];

    final dumps = [
      '${Platform.environment['HOME']}/Downloads/my_sms.txt',
      '${Platform.environment['HOME']}/Downloads/my_sms_live.txt',
    ];

    for (final path in dumps) {
      test('balanced account-kind classification over ${path.split('/').last}',
          () {
        final file = File(path);
        if (!file.existsSync()) {
          print('SKIP: $path not found');
          return;
        }

        final state = _buildStoreState(file.readAsStringSync());
        final store = FinanceStore()
          ..seedDiscoveredAccounts(state.discovered)
          ..seedTransactions(state.transactions);
        final accounts = store.bankAccounts();

        // Per-mask kind vote tally (mirrors _AccountKindEvidence: a CC-kind
        // "Credit card bill payment" debit counts toward the funding account).
        final votes = <String, Map<AccountKind, int>>{};
        for (final t in state.transactions) {
          if (t.maskedAccount.isEmpty) continue;
          final effective = (t.accountKind == AccountKind.creditCard &&
                  !t.isCredit &&
                  t.merchant.toLowerCase().contains('credit card bill payment'))
              ? AccountKind.savings
              : t.accountKind;
          final tally =
              votes.putIfAbsent(t.maskedAccount, () => <AccountKind, int>{});
          tally[effective] = (tally[effective] ?? 0) + 1;
        }

        final savings =
            accounts.where((a) => a.kind == AccountKind.savings).toList();
        final cards =
            accounts.where((a) => a.kind == AccountKind.creditCard).toList();
        final loans =
            accounts.where((a) => a.kind == AccountKind.loan).toList();

        String votesFor(String mask) {
          final v = votes[mask] ?? const {};
          return 'cc=${v[AccountKind.creditCard] ?? 0} '
              'sav=${v[AccountKind.savings] ?? 0} '
              'loan=${v[AccountKind.loan] ?? 0}';
        }

        print('=== BALANCED ACCOUNT KINDS (${path.split('/').last}) ===');
        print('Total accounts : ${accounts.length}');
        print('Savings        : ${savings.length}');
        print('Credit card    : ${cards.length}');
        print('Loan           : ${loans.length}');
        print('\n-- Savings --');
        for (final a in savings) {
          print('  ${a.name.padRight(24)} ${a.mask}  '
              'activity=${a.activityCount}  [${votesFor(a.mask)}]');
        }
        print('\n-- Credit cards --');
        for (final a in cards) {
          print('  ${a.name.padRight(24)} ${a.mask}  '
              'activity=${a.activityCount}  [${votesFor(a.mask)}]');
        }
        print('\n-- Loans --');
        for (final a in loans) {
          print('  ${a.name.padRight(24)} ${a.mask}  '
              'activity=${a.activityCount}  [${votesFor(a.mask)}]');
        }

        final savingsMasks = savings.map((a) => a.mask).toSet();
        final cardMasks = cards.map((a) => a.mask).toSet();
        final loanMasks = loans.map((a) => a.mask).toSet();

        // Only assert on masks that actually appear in this dump.
        final presentMasks = accounts.map((a) => a.mask).toSet();

        final savingsMissed = knownSavingsMasks
            .where((m) => presentMasks.contains(m) && !savingsMasks.contains(m))
            .toList();
        final cardsAsSavings = knownCardMasks
            .where((m) => savingsMasks.contains(m))
            .toList();

        print('\nKnown savings present  : '
            '${knownSavingsMasks.where(savingsMasks.contains).toList()}');
        print('Known savings misclassified: $savingsMissed');
        print('Known cards present    : '
            '${knownCardMasks.where(cardMasks.contains).toList()}');
        print('Known cards as savings : $cardsAsSavings');
        print('Loan masks             : $loanMasks');

        expect(savingsMissed, isEmpty,
            reason: 'Known savings accounts must classify as savings');
        expect(cardsAsSavings, isEmpty,
            reason: 'Known credit cards must not appear as savings');
        // The four known savings accounts must be detected in the full dump.
        if (path.endsWith('my_sms.txt')) {
          for (final m in knownSavingsMasks) {
            expect(savingsMasks, contains(m),
                reason: '$m should be a savings account');
          }
          for (final m in ['••••3452', '••••2009', '••••7550', '••••9757']) {
            expect(cardMasks, contains(m),
                reason: '$m should be a credit card');
          }
          expect(cards.length, greaterThan(3),
              reason: 'The user has many credit cards');
          expect(savings.length, greaterThanOrEqualTo(4),
              reason: 'At least the four known savings accounts must show');

          // Coverage fix: savings accounts previously ABSENT (surfaced only via
          // balance / interest / informational SMS) must now appear.
          for (final m in ['••••4720', '••••7953', '••••3455']) {
            expect(savingsMasks, contains(m),
                reason: '$m (PNB/Federal savings) must surface as savings');
          }
          // The known credit cards must remain credit cards (classification
          // unaffected by the broadened savings coverage).
          expect(cardsAsSavings, isEmpty,
              reason: 'Broadened savings coverage must not flip cards');
        }
      });
    }
  });
}

Transaction _txn({
  required String id,
  required String bank,
  required String mask,
  required AccountKind kind,
  required double amount,
  bool isCredit = false,
}) {
  return Transaction(
    id: id,
    smsId: 'sms_$id',
    merchant: 'Test',
    bank: bank,
    maskedAccount: mask,
    category: SpendCategory.other,
    amount: amount,
    isCredit: isCredit,
    timestamp: DateTime(2026, 7, 7),
    accountKind: kind,
  );
}

/// A credit-card bill payment (CCBP) debited from a funding bank account. The
/// enrichment layer marks these accountKind=creditCard with a "Credit card bill
/// payment" merchant while keeping the funding account's own mask.
Transaction _ccbpTxn({
  required String id,
  required String bank,
  required String mask,
  required double amount,
}) {
  return Transaction(
    id: id,
    smsId: 'sms_$id',
    merchant: 'Credit card bill payment',
    bank: bank,
    maskedAccount: mask,
    category: SpendCategory.other,
    amount: amount,
    isCredit: false,
    timestamp: DateTime(2026, 7, 7),
    accountKind: AccountKind.creditCard,
  );
}

/// Replicates the store's discovery + enrichment for a list of raw SMS.
FinanceStore _storeFromBodies(List<({String sender, String body})> msgs) {
  final registry = AccountBankRegistry();
  final rawDiscoveries = <DiscoveredAccount>[];
  for (final m in msgs) {
    registry.learn(m.sender, m.body);
    final d = AccountDiscovery.discover(sender: m.sender, body: m.body);
    if (d != null) rawDiscoveries.add(d);
  }
  final discovered = mergeDiscoveries(rawDiscoveries).values.toList();

  final transactions = <Transaction>[];
  var i = 0;
  for (final m in msgs) {
    final input = SmsMessageInput(
      id: '${i++}',
      sender: m.sender,
      body: m.body,
      timestamp: DateTime(2026, 7, 7),
    );
    final t = _enrich(input, registry, discovered);
    if (t != null) transactions.add(t);
  }

  return FinanceStore()
    ..seedDiscoveredAccounts(discovered)
    ..seedTransactions(transactions);
}

({List<Transaction> transactions, List<DiscoveredAccount> discovered})
    _buildStoreState(String rawExport) {
  final messages = parseAdbSmsExport(rawExport);
  final registry = AccountBankRegistry();
  final rawDiscoveries = <DiscoveredAccount>[];
  for (final m in messages) {
    registry.learn(m.sender, m.body);
    final d = AccountDiscovery.discover(sender: m.sender, body: m.body);
    if (d != null) rawDiscoveries.add(d);
  }
  final discovered = mergeDiscoveries(rawDiscoveries).values.toList();

  final transactions = <Transaction>[];
  for (final m in messages) {
    final input = SmsMessageInput(
      id: '${m.row}',
      sender: m.sender,
      body: m.body,
      timestamp: DateTime.fromMillisecondsSinceEpoch(m.dateMs),
    );
    final t = _enrich(input, registry, discovered);
    if (t != null) transactions.add(t);
  }
  return (transactions: transactions, discovered: discovered);
}

Transaction? _enrich(
  SmsMessageInput input,
  AccountBankRegistry registry,
  List<DiscoveredAccount> discovered,
) {
  if (!SmsScanPipeline.process(input).isParsed) return null;
  final parsed = SmsParser.parseTransaction(input, registry: registry);
  if (parsed == null) return null;

  final mask = TransactionEnrichment.resolveMaskedAccount(
    parsedMask: parsed.maskedAccount,
    sender: input.sender,
    body: input.body,
  );
  var bank = parsed.bank;
  var displayMask = mask;
  final accountKind = TransactionEnrichment.resolveAccountKind(
    bank: bank,
    mask: mask,
    body: input.body,
    discoveries: discovered,
  );
  if (accountKind == AccountKind.loan) {
    final loanDisplay = TransactionEnrichment.resolveLoanDisplay(
      body: input.body,
      parsedBank: bank,
      parsedMask: mask,
      discoveries: discovered,
    );
    bank = loanDisplay.bank;
    if (loanDisplay.mask.isNotEmpty) displayMask = loanDisplay.mask;
  } else if (accountKind == AccountKind.creditCard) {
    final ccDisplay = TransactionEnrichment.resolveCreditCardDisplay(
      body: input.body,
      parsedBank: bank,
      parsedMask: mask,
      discoveries: discovered,
    );
    bank = ccDisplay.bank;
    if (ccDisplay.mask.isNotEmpty) displayMask = ccDisplay.mask;
  }

  // Mirror production: the stored merchant is the ENRICHED merchant (e.g.
  // "Credit card bill payment" for CCBP debits), which the balanced classifier
  // uses to keep card bill payments attributed to the funding account.
  final merchant = TransactionEnrichment.improveMerchant(
    merchant: parsed.merchant,
    body: input.body,
    isCredit: parsed.isCredit,
    accountKind: accountKind,
  );

  return Transaction(
    id: 'sms_${input.id}',
    smsId: input.id,
    merchant: merchant,
    bank: bank,
    maskedAccount: displayMask,
    category: SpendCategory.other,
    amount: parsed.amount,
    isCredit: parsed.isCredit,
    timestamp: parsed.timestamp,
    accountKind: accountKind,
  );
}
