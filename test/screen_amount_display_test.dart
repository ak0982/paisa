import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/models/transaction.dart';
import 'package:paisa_app/providers/finance_store.dart';
import 'package:paisa_app/services/sms/account_discovery.dart';
import 'package:paisa_app/utils/formatters.dart';
import 'package:paisa_app/widgets/category_spend_chip.dart';

/// Locks Home / Insights / Reports / You / category-chip display amounts
/// to stored INR (2 dp, Indian grouping, no ₹0.85→₹1).
void main() {
  Transaction tx({
    required String id,
    required double amount,
    required bool isCredit,
    required DateTime ts,
    SpendCategory category = SpendCategory.other,
    AccountKind kind = AccountKind.savings,
    String bank = 'SBI',
    String mask = '••••0429',
    String merchant = 'Test',
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
      timestamp: ts,
      accountKind: kind,
    );
  }

  DateTime monthDay(int day, {int hour = 12}) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, day, hour);
  }

  group('screen display formatInr', () {
    testWidgets('CategorySpendChip shows exact paise not rounded rupee',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CategorySpendChip(
              info: CategoryInfo(
                category: SpendCategory.other,
                label: 'Other',
                emoji: '📦',
                tintBg: Colors.grey,
                iconColor: Colors.black,
              ),
              amount: 0.85,
            ),
          ),
        ),
      );
      expect(find.text(formatInr(0.85)), findsOneWidget);
      expect(find.textContaining('0.85'), findsWidgets);
      expect(find.text(formatInr(1)), findsNothing);
    });

    testWidgets('chip share 0% is omitted; 0.01% and 0.1% render',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                CategorySpendChip(
                  info: CategoryInfo.forCategory(SpendCategory.food),
                  amount: 0.85,
                  share: 0,
                  badgeKind: ShareBadgeKind.low,
                ),
                CategorySpendChip(
                  info: CategoryInfo.forCategory(SpendCategory.travel),
                  amount: 1.50,
                  share: 0.0001,
                  badgeKind: ShareBadgeKind.mid,
                ),
                CategorySpendChip(
                  info: CategoryInfo.forCategory(SpendCategory.shopping),
                  amount: 10.00,
                  share: 0.001,
                  badgeKind: ShareBadgeKind.top,
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('0%'), findsNothing);
      expect(find.textContaining('0.01%'), findsOneWidget);
      expect(find.textContaining('0.1%'), findsOneWidget);
      expect(find.textContaining('TOP'), findsOneWidget);
    });
  });

  group('Home / Insights / Reports / You totals', () {
    test('Home stickers match store month KPIs and formatInr', () {
      final store = FinanceStore()
        ..seedTransactions([
          tx(
            id: 'swiggy',
            amount: 325.50,
            isCredit: false,
            ts: monthDay(8),
            category: SpendCategory.food,
            merchant: 'Swiggy',
          ),
          tx(
            id: 'salary',
            amount: 50000.00,
            isCredit: true,
            ts: monthDay(5),
            category: SpendCategory.income,
            merchant: 'Salary',
          ),
          tx(
            id: 'ccbp',
            amount: 8330.00,
            isCredit: false,
            ts: monthDay(6),
            category: SpendCategory.transfer,
            merchant: 'MBK CCBP',
          ),
          tx(
            id: 'lenden',
            amount: 0.85,
            isCredit: true,
            ts: monthDay(7),
            category: SpendCategory.income,
            merchant: 'LenDenClub',
            bank: 'Slice',
            mask: '••••0856',
          ),
        ]);

      expect(store.monthlySpent, closeTo(325.50, 0.001));
      expect(store.monthlyIncome, closeTo(50000.85, 0.001));
      expect(formatInr(store.monthlySpent), '₹325.50');
      expect(formatInr(store.monthlyIncome), '₹50,000.85');
      expect(formatInr(store.monthlySaved), formatInr(50000.85 - 325.50));
      expect(store.activeMonthTransactionCount, 4);
    });

    test('Insights all-time spent matches spend txns and chip shares', () {
      final store = FinanceStore()
        ..seedTransactions([
          tx(
            id: 'bills',
            amount: 52205.00,
            isCredit: false,
            ts: DateTime(2026, 7, 2),
            category: SpendCategory.bills,
            merchant: 'NACH',
          ),
          tx(
            id: 'other',
            amount: 51426.70,
            isCredit: false,
            ts: DateTime(2026, 7, 3),
            category: SpendCategory.other,
          ),
          tx(
            id: 'tiny',
            amount: 0.85,
            isCredit: false,
            ts: DateTime(2026, 7, 4),
            category: SpendCategory.health,
          ),
        ]);
      final spent = 52205.00 + 51426.70 + 0.85;
      expect(store.insightsSpent, closeTo(spent, 0.001));
      expect(formatInr(store.insightsSpent), formatInr(spent));
      final foodShare = 0.85 / spent;
      expect(formatSharePercent(foodShare), isNot(equals('0%')));
      expect(formatSharePercent(foodShare), isNotEmpty);
      expect(
        formatInr(store.insightsCategorySpending[SpendCategory.bills]!),
        '₹52,205.00',
      );
    });

    test('Reports this-month net/saved/daily use formatInr 2dp', () {
      final store = FinanceStore()
        ..seedTransactions([
          tx(
            id: 'spend',
            amount: 146483.52,
            isCredit: false,
            ts: monthDay(8),
            category: SpendCategory.bills,
          ),
          tx(
            id: 'inc',
            amount: 3172.94,
            isCredit: true,
            ts: monthDay(2),
            category: SpendCategory.income,
            merchant: 'LenDenClub',
          ),
        ]);
      final report = store.buildReport(
        store.currentMonthRange.start,
        store.currentMonthRange.end,
      );
      expect(formatInr(report.spent), '₹1,46,483.52');
      expect(formatInr(report.income), '₹3,172.94');
      expect(report.saved, 0);
      expect(formatInr(report.saved), '₹0.00');
      expect(formatInr(report.net.abs()), formatInr(146483.52 - 3172.94));
      expect(formatInr(report.dailyAverage), formatInr(report.spent / report.dayCount));
    });

    test('You savings vs CC same last-4 at different banks stay split', () {
      final store = FinanceStore()
        ..seedTransactions([
          tx(
            id: 'slice',
            amount: 0.86,
            isCredit: true,
            ts: DateTime(2026, 8, 12),
            category: SpendCategory.income,
            bank: 'Slice',
            mask: '••••0856',
            merchant: 'LenDenClub',
          ),
          tx(
            id: 'hdfc-cc',
            amount: 8330.00,
            isCredit: false,
            ts: DateTime(2026, 8, 10),
            category: SpendCategory.shopping,
            bank: 'HDFC',
            mask: '••••0856',
            kind: AccountKind.creditCard,
            merchant: 'Amazon',
          ),
        ]);
      final slice = store.bankAccounts().firstWhere((a) => a.bank == 'Slice');
      final hdfc = store.bankAccounts().firstWhere((a) => a.bank == 'HDFC');
      expect(slice.kind, AccountKind.savings);
      expect(hdfc.kind, AccountKind.creditCard);
      expect(formatInr(slice.receivedTotal), '₹0.86');
      expect(formatInr(hdfc.spentTotal), '₹8,330.00');
      expect(
        store
            .transactionsForAccount(evidenceKey: slice.evidenceKey)
            .map((t) => t.id),
        ['slice'],
      );
      expect(
        store
            .transactionsForAccount(evidenceKey: hdfc.evidenceKey)
            .map((t) => t.id),
        ['hdfc-cc'],
      );
    });

    test('You loan drilldown does not absorb paired savings funding', () {
      final store = FinanceStore()
        ..seedDiscoveredAccounts([
          const DiscoveredAccount(
            bank: 'PNB',
            mask: '••••0310',
            kind: AccountKind.loan,
            smsHits: 4,
          ),
          const DiscoveredAccount(
            bank: 'HDFC',
            mask: '••••0855',
            kind: AccountKind.loan,
            smsHits: 5,
          ),
        ])
        ..seedTransactions([
          tx(
            id: 'fund',
            amount: 5199.39,
            isCredit: false,
            ts: DateTime(2026, 8, 7),
            category: SpendCategory.emi,
            bank: 'HDFC',
            mask: '••••5300',
            merchant: 'MBK EMI',
          ),
          tx(
            id: 'pnb',
            amount: 5199.39,
            isCredit: false,
            ts: DateTime(2026, 8, 7, 1),
            category: SpendCategory.emi,
            bank: 'PNB',
            mask: '••••0310',
            kind: AccountKind.loan,
            merchant: 'Loan payment',
          ),
        ]);
      final pnb = store.bankAccounts().firstWhere((a) => a.mask == '••••0310');
      final sav = store.bankAccounts().firstWhere((a) => a.mask == '••••5300');
      expect(
        store
            .transactionsForAccount(evidenceKey: pnb.evidenceKey)
            .any((t) => t.id == 'fund'),
        isFalse,
      );
      expect(
        store
            .transactionsForAccount(evidenceKey: sav.evidenceKey)
            .any((t) => t.id == 'fund'),
        isTrue,
      );
      expect(formatInr(pnb.spentTotal), '₹5,199.39');
      expect(formatInr(sav.spentTotal), '₹5,199.39');
    });

    test('filtered account split totals equal received/sent folds', () {
      final store = FinanceStore()
        ..seedTransactions([
          tx(
            id: 'in1',
            amount: 2451.58,
            isCredit: true,
            ts: DateTime(2026, 6, 1),
            category: SpendCategory.income,
            bank: 'Kotak',
            mask: '••••3649',
          ),
          tx(
            id: 'out1',
            amount: 26408.00,
            isCredit: false,
            ts: DateTime(2026, 6, 7),
            category: SpendCategory.emi,
            bank: 'Kotak',
            mask: '••••3649',
            merchant: 'NACH HDFC',
          ),
          tx(
            id: 'out2',
            amount: 0.85,
            isCredit: false,
            ts: DateTime(2026, 6, 8),
            bank: 'Kotak',
            mask: '••••3649',
          ),
        ]);
      final acct = store.bankAccounts().single;
      final list = store.transactionsForAccount(evidenceKey: acct.evidenceKey);
      final received =
          list.where((t) => t.isCredit).fold(0.0, (s, t) => s + t.amount);
      final sent =
          list.where((t) => !t.isCredit).fold(0.0, (s, t) => s + t.amount);
      expect(formatInr(received), formatInr(acct.receivedTotal));
      expect(formatInr(sent), formatInr(acct.spentTotal));
      expect(formatInr(sent), '₹26,408.85');
      expect(formatInr(received), '₹2,451.58');
    });
  });

  group('spot-check known live amounts', () {
    const spots = <(String, double)>[
      ('LenDen 0.85', 0.85),
      ('LenDen 0.86', 0.86),
      ('Yes Bank 236', 236.00),
      ('Swiggy 325.50', 325.50),
      ('CCBP 8330', 8330.00),
      ('CCBP 1365', 1365.00),
      ('CCBP 2451.58', 2451.58),
      ('CCBP 9392.10', 9392.10),
      ('NACH 26408', 26408.00),
      ('EMI 5199.39', 5199.39),
      ('25797 incl 7 Aug', 25797.00),
      ('Home spent 146483.52', 146483.52),
      ('Home income 3172.94', 3172.94),
      ('Bills 52205', 52205.00),
      ('Other 51426.70', 51426.70),
      ('Transfer 42504.82', 42504.82),
    ];
    for (final s in spots) {
      test('${s.$1} formatInr keeps paise', () {
        final cents = ((s.$2 * 100).round() % 100).toString().padLeft(2, '0');
        final formatted = formatInr(s.$2);
        expect(formatted, startsWith('₹'));
        expect(formatted, contains('.$cents'));
        if (s.$2 < 1) {
          expect(formatted, isNot(contains('1.00')));
        }
      });
    }
  });
}
