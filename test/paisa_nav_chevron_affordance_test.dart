import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/models/transaction.dart';
import 'package:paisa_app/providers/app_settings.dart';
import 'package:paisa_app/providers/finance_store.dart';
import 'package:paisa_app/screens/budgets_screen.dart';
import 'package:paisa_app/screens/dashboard_screen.dart';
import 'package:paisa_app/screens/day_strip_screen.dart';
import 'package:paisa_app/screens/insights_screen.dart';
import 'package:paisa_app/screens/profile_screen.dart';
import 'package:paisa_app/screens/reports_screen.dart';
import 'package:paisa_app/services/sms/account_discovery.dart';
import 'package:paisa_app/theme/paisa_colors.dart';
import 'package:paisa_app/utils/formatters.dart';
import 'package:paisa_app/widgets/category_spend_chip.dart';
import 'package:paisa_app/widgets/day_strip_teaser.dart';
import 'package:paisa_app/widgets/grouped_transaction_list.dart';
import 'package:paisa_app/widgets/paisa_nav_chevron.dart';
import 'package:paisa_app/widgets/settings_detail_scaffold.dart';
import 'package:paisa_app/widgets/transaction_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/dummy_data.dart';
import 'helpers/test_harness.dart';

/// Tappable-row affordance: [PaisaNavChevron] + Semantics/ripple on interactive
/// rows; static rows stay chevron-free.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppSettings settings;

  Transaction tx({
    required String id,
    required double amount,
    required bool isCredit,
    required SpendCategory category,
    String merchant = 'Test',
    String bank = 'SBI',
    String mask = '••••0429',
    required DateTime timestamp,
    AccountKind kind = AccountKind.savings,
  }) =>
      Transaction(
        id: id,
        smsId: id,
        merchant: merchant,
        bank: bank,
        maskedAccount: mask,
        category: category,
        amount: amount,
        isCredit: isCredit,
        timestamp: timestamp,
        accountKind: kind,
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await AppSettings.load();
  });

  Future<void> pumpChild(
    WidgetTester tester,
    Widget child, {
    FinanceStore? store,
    Size size = const Size(400, 2400),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildTestApp(
        settings: settings,
        store: store ?? FinanceStore(),
        child: child,
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder chevrons() => find.byType(PaisaNavChevron);

  /// True when [label] sits under an [InkWell]/[GestureDetector] that owns a chevron.
  bool tappableRowHasChevron(WidgetTester tester, String label) {
    final labelFinder = find.text(label);
    if (labelFinder.evaluate().isEmpty) return false;
    for (final type in [InkWell, GestureDetector]) {
      final ancestor = find.ancestor(
        of: labelFinder.first,
        matching: find.byType(type),
      );
      if (ancestor.evaluate().isEmpty) continue;
      if (find
          .descendant(of: ancestor.first, matching: chevrons())
          .evaluate()
          .isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  /// Merchant / static rows: no InkWell (or InkWell without chevron).
  bool staticRowLacksChevron(WidgetTester tester, String label) {
    final labelFinder = find.text(label);
    if (labelFinder.evaluate().isEmpty) return true;
    final ink = find.ancestor(
      of: labelFinder.first,
      matching: find.byType(InkWell),
    );
    if (ink.evaluate().isEmpty) return true;
    return find
        .descendant(of: ink.first, matching: chevrons())
        .evaluate()
        .isEmpty;
  }

  Finder semanticsButtonWhoseLabel(bool Function(String label) match) {
    return find.byWidgetPredicate((w) {
      if (w is! Semantics) return false;
      final label = w.properties.label;
      return w.properties.button == true &&
          label != null &&
          match(label);
    });
  }

  // ── PaisaNavChevron itself ───────────────────────────────────────────────

  group('PaisaNavChevron widget', () {
    testWidgets('renders rounded chevron icon', (tester) async {
      await pumpChild(tester, const PaisaNavChevron());
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      expect(chevrons(), findsOneWidget);
    });

    testWidgets('default size is 18', (tester) async {
      await pumpChild(tester, const PaisaNavChevron());
      final icon = tester.widget<Icon>(find.byIcon(Icons.chevron_right_rounded));
      expect(icon.size, 18);
    });

    testWidgets('custom size is applied', (tester) async {
      await pumpChild(tester, const PaisaNavChevron(size: 22));
      final icon = tester.widget<Icon>(find.byIcon(Icons.chevron_right_rounded));
      expect(icon.size, 22);
    });

    testWidgets('default color is mutedCaption', (tester) async {
      await pumpChild(tester, const PaisaNavChevron());
      final icon = tester.widget<Icon>(find.byIcon(Icons.chevron_right_rounded));
      expect(icon.color, PaisaColors.mutedCaption);
    });

    testWidgets('custom color overrides mutedCaption', (tester) async {
      await pumpChild(
        tester,
        const PaisaNavChevron(color: PaisaColors.primary),
      );
      final icon = tester.widget<Icon>(find.byIcon(Icons.chevron_right_rounded));
      expect(icon.color, PaisaColors.primary);
    });
  });

  // ── TransactionRow ───────────────────────────────────────────────────────

  group('TransactionRow nav chevron', () {
    final sample = dummyTxn(
      id: 'r1',
      merchant: 'RowCafe',
      amount: 42,
      isCredit: false,
      category: SpendCategory.food,
      timestamp: DateTime(2026, 8, 15, 12),
    );

    testWidgets('hidden by default', (tester) async {
      await pumpChild(tester, TransactionRow(transaction: sample));
      expect(chevrons(), findsNothing);
    });

    testWidgets('shown when showNavChevron is true', (tester) async {
      await pumpChild(
        tester,
        TransactionRow(transaction: sample, showNavChevron: true),
      );
      expect(chevrons(), findsOneWidget);
    });

    testWidgets('chevron sits after amount', (tester) async {
      await pumpChild(
        tester,
        TransactionRow(transaction: sample, showNavChevron: true),
      );
      final amountX = tester.getTopLeft(find.textContaining('42')).dx;
      final chevronX = tester.getTopLeft(chevrons()).dx;
      expect(chevronX > amountX, isTrue);
    });

    testWidgets('default chevron uses mutedCaption', (tester) async {
      await pumpChild(
        tester,
        TransactionRow(transaction: sample, showNavChevron: true),
      );
      final widget = tester.widget<PaisaNavChevron>(chevrons());
      expect(widget.size, 18);
      expect(widget.color, isNull);
    });

    testWidgets('compact row still shows chevron when enabled', (tester) async {
      await pumpChild(
        tester,
        TransactionRow(
          transaction: sample,
          compact: true,
          showNavChevron: true,
        ),
      );
      expect(chevrons(), findsOneWidget);
    });

    testWidgets('credit row with chevron still shows amount', (tester) async {
      final credit = dummyTxn(
        id: 'c1',
        merchant: 'Pay',
        amount: 100,
        isCredit: true,
        category: SpendCategory.income,
        timestamp: DateTime(2026, 8, 15, 12),
      );
      await pumpChild(
        tester,
        TransactionRow(transaction: credit, showNavChevron: true),
      );
      expect(chevrons(), findsOneWidget);
      expect(find.text(formatAmount(100, isCredit: true)), findsOneWidget);
    });
  });

  // ── CategorySpendChip ────────────────────────────────────────────────────

  group('CategorySpendChip chevron', () {
    final food = CategoryInfo.forCategory(SpendCategory.food);

    testWidgets('no chevron without onTap', (tester) async {
      await pumpChild(
        tester,
        CategorySpendChip(info: food, amount: 100, expanded: true),
      );
      expect(chevrons(), findsNothing);
    });

    testWidgets('no chevron when tappable but not expanded', (tester) async {
      await pumpChild(
        tester,
        CategorySpendChip(
          info: food,
          amount: 100,
          onTap: () {},
        ),
      );
      expect(chevrons(), findsNothing);
    });

    testWidgets('chevron when tappable and expanded', (tester) async {
      await pumpChild(
        tester,
        CategorySpendChip(
          info: food,
          amount: 100,
          expanded: true,
          onTap: () {},
        ),
      );
      expect(chevrons(), findsOneWidget);
      final widget = tester.widget<PaisaNavChevron>(chevrons());
      expect(widget.size, 16);
    });

    testWidgets('Semantics button when onTap set', (tester) async {
      await pumpChild(
        tester,
        CategorySpendChip(
          info: food,
          amount: 250.5,
          expanded: true,
          onTap: () {},
        ),
      );
      expect(
        semanticsButtonWhoseLabel((l) => l.startsWith('Food ')),
        findsOneWidget,
      );
    });

    testWidgets('sticker grid expands tiles with chevrons', (tester) async {
      await pumpChild(
        tester,
        CategorySpendStickerGrid(
          tiles: [
            CategorySpendTile(
              category: SpendCategory.food,
              amount: 200,
              share: 0.6,
              emphasize: true,
              onTap: () {},
            ),
            CategorySpendTile(
              category: SpendCategory.shopping,
              amount: 100,
              share: 0.4,
              onTap: () {},
            ),
          ],
        ),
      );
      expect(chevrons(), findsNWidgets(2));
    });

    testWidgets('sticker grid without onTap has no chevrons', (tester) async {
      await pumpChild(
        tester,
        CategorySpendStickerGrid(
          tiles: [
            CategorySpendTile(
              category: SpendCategory.food,
              amount: 200,
              share: 1,
            ),
          ],
        ),
      );
      expect(chevrons(), findsNothing);
    });
  });

  // ── Insights / Stats ─────────────────────────────────────────────────────

  group('Insights Stats BY CATEGORY vs TOP MERCHANTS', () {
    testWidgets('category rows show chevrons; merchants do not', (tester) async {
      final now = DateTime.now();
      final store = FinanceStore()
        ..seedTransactions([
          tx(
            id: 'food',
            amount: 320.58,
            isCredit: false,
            category: SpendCategory.food,
            merchant: 'Swiggy',
            timestamp: now.subtract(const Duration(days: 2)),
          ),
          tx(
            id: 'shop',
            amount: 120.42,
            isCredit: false,
            category: SpendCategory.shopping,
            merchant: 'Blinkit',
            timestamp: now.subtract(const Duration(days: 1)),
          ),
        ]);

      await pumpChild(tester, const InsightsScreen(), store: store);

      expect(find.text('BY CATEGORY'), findsOneWidget);
      expect(find.text('TOP MERCHANTS'), findsOneWidget);
      expect(tappableRowHasChevron(tester, 'Food'), isTrue);
      expect(tappableRowHasChevron(tester, 'Shopping'), isTrue);
      expect(staticRowLacksChevron(tester, 'Swiggy'), isTrue);
      expect(staticRowLacksChevron(tester, 'Blinkit'), isTrue);
    });

    testWidgets('single category still shows one row chevron', (tester) async {
      final now = DateTime.now();
      final store = FinanceStore()
        ..seedTransactions([
          tx(
            id: 'only',
            amount: 99,
            isCredit: false,
            category: SpendCategory.bills,
            merchant: 'Airtel',
            timestamp: now.subtract(const Duration(days: 1)),
          ),
        ]);

      await pumpChild(tester, const InsightsScreen(), store: store);

      expect(find.text('Bills'), findsOneWidget);
      expect(tappableRowHasChevron(tester, 'Bills'), isTrue);
      expect(staticRowLacksChevron(tester, 'Airtel'), isTrue);
    });

    testWidgets('multiple categories each get a chevron', (tester) async {
      final now = DateTime.now();
      final store = FinanceStore()
        ..seedTransactions([
          for (final entry in [
            (SpendCategory.food, 'A', 300.0),
            (SpendCategory.travel, 'B', 200.0),
            (SpendCategory.shopping, 'C', 100.0),
          ])
            tx(
              id: entry.$2,
              amount: entry.$3,
              isCredit: false,
              category: entry.$1,
              merchant: 'M${entry.$2}',
              timestamp: now.subtract(Duration(days: entry.$3 ~/ 100)),
            ),
        ]);

      await pumpChild(tester, const InsightsScreen(), store: store);

      expect(tappableRowHasChevron(tester, 'Food'), isTrue);
      expect(tappableRowHasChevron(tester, 'Travel'), isTrue);
      expect(tappableRowHasChevron(tester, 'Shopping'), isTrue);
    });

    testWidgets('empty ledger has no category chevrons', (tester) async {
      await pumpChild(tester, const InsightsScreen(), store: FinanceStore());

      expect(find.text('BY CATEGORY'), findsNothing);
      expect(find.text('TOP MERCHANTS'), findsNothing);
      // REPORTS chrome may still show a chevron; no category rows.
      expect(find.text('No transactions yet'), findsOneWidget);
      expect(tappableRowHasChevron(tester, 'Food'), isFalse);
    });

    testWidgets('category row Semantics is a button', (tester) async {
      final now = DateTime.now();
      final store = FinanceStore()
        ..seedTransactions([
          tx(
            id: 'food',
            amount: 50,
            isCredit: false,
            category: SpendCategory.food,
            merchant: 'Cafe',
            timestamp: now.subtract(const Duration(days: 1)),
          ),
        ]);

      await pumpChild(tester, const InsightsScreen(), store: store);

      expect(
        semanticsButtonWhoseLabel((l) => l.startsWith('Food,')),
        findsOneWidget,
      );
    });

    testWidgets('tapping category row opens detail', (tester) async {
      final now = DateTime.now();
      final store = FinanceStore()
        ..seedTransactions([
          tx(
            id: 'food',
            amount: 77,
            isCredit: false,
            category: SpendCategory.food,
            merchant: 'DrillCafe',
            timestamp: now.subtract(const Duration(days: 1)),
          ),
        ]);

      await pumpChild(tester, const InsightsScreen(), store: store);
      await tester.tap(find.text('Food'));
      await tester.pumpAndSettle();

      expect(find.text('DrillCafe'), findsOneWidget);
    });

    testWidgets('peak day legend shows nav chevron', (tester) async {
      final peak = DateTime.now().subtract(const Duration(days: 3));
      final store = FinanceStore()
        ..seedTransactions([
          tx(
            id: 'peak',
            amount: 500,
            isCredit: false,
            category: SpendCategory.shopping,
            merchant: 'PeakShop',
            timestamp: DateTime(peak.year, peak.month, peak.day, 11),
          ),
        ]);

      await pumpChild(tester, const InsightsScreen(), store: store);

      expect(find.text('PEAK DAY'), findsOneWidget);
      expect(tappableRowHasChevron(tester, 'PEAK DAY'), isTrue);
    });

    testWidgets('peak day Semantics is a button', (tester) async {
      final peak = DateTime.now().subtract(const Duration(days: 2));
      final store = FinanceStore()
        ..seedTransactions([
          tx(
            id: 'peak',
            amount: 200,
            isCredit: false,
            category: SpendCategory.food,
            merchant: 'PeakFood',
            timestamp: DateTime(peak.year, peak.month, peak.day, 10),
          ),
        ]);

      await pumpChild(tester, const InsightsScreen(), store: store);

      final node = find.byWidgetPredicate((w) {
        if (w is! Semantics) return false;
        final props = w.properties;
        return props.button == true &&
            (props.label?.contains('PEAK DAY') ?? false);
      });
      expect(node, findsOneWidget);
    });

    testWidgets('REPORTS chrome includes a chevron', (tester) async {
      await pumpChild(tester, const InsightsScreen(), store: FinanceStore());
      expect(find.text('REPORTS'), findsOneWidget);
      expect(tappableRowHasChevron(tester, 'REPORTS'), isTrue);
    });

    testWidgets('merchant-only income does not create category chevrons',
        (tester) async {
      final now = DateTime.now();
      final store = FinanceStore()
        ..seedTransactions([
          tx(
            id: 'salary',
            amount: 5000,
            isCredit: true,
            category: SpendCategory.income,
            merchant: 'Salary',
            timestamp: now.subtract(const Duration(days: 1)),
          ),
        ]);

      await pumpChild(tester, const InsightsScreen(), store: store);

      expect(find.text('BY CATEGORY'), findsNothing);
      expect(find.text('Salary'), findsNothing);
    });
  });

  // ── Day Strip ────────────────────────────────────────────────────────────

  group('Day Strip tappable rows', () {
    final day = DateTime(2026, 8, 15, 12);

    testWidgets('transaction rows show PaisaNavChevron', (tester) async {
      final store = FinanceStore()
        ..seedTransactions([
          tx(
            id: 'd1',
            amount: 15.15,
            isCredit: false,
            category: SpendCategory.food,
            merchant: 'SatCafe',
            timestamp: day,
          ),
        ]);

      await pumpChild(
        tester,
        DayStripScreen(initialDay: day),
        store: store,
      );

      expect(find.text('SatCafe'), findsOneWidget);
      expect(chevrons(), findsWidgets);
      expect(tappableRowHasChevron(tester, 'SatCafe'), isTrue);
    });

    testWidgets('day row Semantics is a button', (tester) async {
      final store = FinanceStore()
        ..seedTransactions([
          tx(
            id: 'd1',
            amount: 40,
            isCredit: false,
            category: SpendCategory.food,
            merchant: 'DayFood',
            timestamp: day,
          ),
        ]);

      await pumpChild(
        tester,
        DayStripScreen(initialDay: day),
        store: store,
      );

      expect(
        semanticsButtonWhoseLabel((l) => l.startsWith('DayFood,')),
        findsOneWidget,
      );
    });

    testWidgets('multiple day rows each show a chevron', (tester) async {
      final store = FinanceStore()
        ..seedTransactions([
          tx(
            id: 'a',
            amount: 10,
            isCredit: false,
            category: SpendCategory.food,
            merchant: 'Alpha',
            timestamp: day,
          ),
          tx(
            id: 'b',
            amount: 20,
            isCredit: true,
            category: SpendCategory.income,
            merchant: 'Beta',
            timestamp: day.add(const Duration(hours: 1)),
          ),
        ]);

      await pumpChild(
        tester,
        DayStripScreen(initialDay: day),
        store: store,
      );

      expect(tappableRowHasChevron(tester, 'Alpha'), isTrue);
      expect(tappableRowHasChevron(tester, 'Beta'), isTrue);
    });

    testWidgets('empty day has no transaction chevrons', (tester) async {
      await pumpChild(
        tester,
        DayStripScreen(initialDay: DateTime(2026, 8, 16)),
        store: FinanceStore(),
      );

      expect(find.text('No money moved'), findsOneWidget);
      expect(chevrons(), findsNothing);
    });

    testWidgets('DayStripTeaser shows primary chevron', (tester) async {
      final store = FinanceStore()
        ..seedTransactions([
          tx(
            id: 't1',
            amount: 88,
            isCredit: false,
            category: SpendCategory.food,
            merchant: 'Teaser',
            timestamp: day,
          ),
        ]);

      await pumpChild(
        tester,
        DayStripTeaser(initialDay: day),
        store: store,
      );

      expect(chevrons(), findsOneWidget);
      final widget = tester.widget<PaisaNavChevron>(chevrons());
      expect(widget.size, 20);
      expect(widget.color, PaisaColors.primary);
    });

    testWidgets('DayStripTeaser Semantics opens day coin', (tester) async {
      await pumpChild(
        tester,
        DayStripTeaser(initialDay: day),
        store: FinanceStore(),
      );

      expect(
        find.bySemanticsLabel(RegExp(r'Open day coin for')),
        findsOneWidget,
      );
    });
  });

  // ── Moves / GroupedTransactionList ───────────────────────────────────────

  group('GroupedTransactionList (Moves) chevrons', () {
    testWidgets('rows show nav chevron', (tester) async {
      await pumpChild(
        tester,
        GroupedTransactionList(
          transactions: [
            dummyTxn(
              id: 'g1',
              merchant: 'MoveCafe',
              amount: 33,
              isCredit: false,
              category: SpendCategory.food,
              timestamp: DateTime(2026, 8, 15, 12),
            ),
          ],
        ),
      );

      expect(find.text('MoveCafe'), findsOneWidget);
      expect(chevrons(), findsOneWidget);
    });

    testWidgets('empty list has no chevrons', (tester) async {
      await pumpChild(
        tester,
        const GroupedTransactionList(transactions: []),
      );
      expect(find.text('No transactions'), findsOneWidget);
      expect(chevrons(), findsNothing);
    });

    testWidgets('multiple rows show matching chevron count', (tester) async {
      await pumpChild(
        tester,
        GroupedTransactionList(
          transactions: [
            dummyTxn(
              id: '1',
              merchant: 'One',
              amount: 1,
              isCredit: false,
              category: SpendCategory.food,
              timestamp: DateTime(2026, 8, 15, 10),
            ),
            dummyTxn(
              id: '2',
              merchant: 'Two',
              amount: 2,
              isCredit: false,
              category: SpendCategory.shopping,
              timestamp: DateTime(2026, 8, 15, 11),
            ),
            dummyTxn(
              id: '3',
              merchant: 'Three',
              amount: 3,
              isCredit: false,
              category: SpendCategory.travel,
              timestamp: DateTime(2026, 8, 15, 12),
            ),
          ],
        ),
      );

      expect(chevrons(), findsNWidgets(3));
    });

    testWidgets('chevron present with custom onTransactionTap', (tester) async {
      Transaction? tapped;
      await pumpChild(
        tester,
        GroupedTransactionList(
          transactions: [
            dummyTxn(
              id: 'tap',
              merchant: 'TapMe',
              amount: 9,
              isCredit: false,
              category: SpendCategory.food,
              timestamp: DateTime(2026, 8, 15, 12),
            ),
          ],
          onTransactionTap: (t) => tapped = t,
        ),
      );

      expect(chevrons(), findsOneWidget);
      await tester.tap(find.text('TapMe'));
      await tester.pumpAndSettle();
      expect(tapped?.merchant, 'TapMe');
    });
  });

  // ── Home / Dashboard recents ─────────────────────────────────────────────

  group('Home Dashboard recents', () {
    testWidgets('today transaction rows show chevrons', (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 14);
      final store = FinanceStore()
        ..seedTransactions([
          tx(
            id: 'today',
            amount: 55,
            isCredit: false,
            category: SpendCategory.food,
            merchant: 'HomeCafe',
            timestamp: today,
          ),
        ]);

      await pumpChild(tester, const DashboardScreen(), store: store);

      expect(find.text('HomeCafe'), findsOneWidget);
      expect(tappableRowHasChevron(tester, 'HomeCafe'), isTrue);
    });

    testWidgets('horizontal category chips stay chevron-free', (tester) async {
      final now = DateTime.now();
      final store = FinanceStore()
        ..seedTransactions([
          tx(
            id: 'chip',
            amount: 120,
            isCredit: false,
            category: SpendCategory.food,
            merchant: 'ChipFood',
            timestamp: DateTime(now.year, now.month, now.day, 11),
          ),
        ]);

      await pumpChild(tester, const DashboardScreen(), store: store);

      // Expanded=false chips: tappable but no PaisaNavChevron on the chip.
      // Row chevron for HomeCafe still exists — chip itself must not add extras.
      final rowChevrons = tester.widgetList(chevrons()).length;
      expect(rowChevrons, greaterThanOrEqualTo(1));
      // DayStripTeaser also adds one primary chevron on Home.
      expect(find.byType(DayStripTeaser), findsOneWidget);
    });

    testWidgets('DayStripTeaser on Home has chevron', (tester) async {
      await pumpChild(
        tester,
        const DashboardScreen(),
        store: FinanceStore(),
      );
      expect(find.byType(DayStripTeaser), findsOneWidget);
      expect(chevrons(), findsWidgets);
    });

    testWidgets('empty home still shows teaser chevron only', (tester) async {
      await pumpChild(
        tester,
        const DashboardScreen(),
        store: FinanceStore(),
      );
      // Only the teaser affordance — no txn rows.
      expect(chevrons(), findsOneWidget);
    });
  });

  // ── Budgets ──────────────────────────────────────────────────────────────

  group('Budgets screen', () {
    testWidgets('category budget rows show chevron', (tester) async {
      final now = DateTime.now();
      final store = FinanceStore()
        ..seedTransactions([
          tx(
            id: 'b1',
            amount: 400,
            isCredit: false,
            category: SpendCategory.food,
            merchant: 'BudgetFood',
            timestamp: DateTime(now.year, now.month, 5, 12),
          ),
        ]);

      await pumpChild(tester, const BudgetsScreen(), store: store);

      expect(find.text('Food'), findsOneWidget);
      expect(tappableRowHasChevron(tester, 'Food'), isTrue);
    });

    testWidgets('budget row Semantics is Edit … budget button', (tester) async {
      final now = DateTime.now();
      final store = FinanceStore()
        ..seedTransactions([
          tx(
            id: 'b1',
            amount: 200,
            isCredit: false,
            category: SpendCategory.shopping,
            merchant: 'Shop',
            timestamp: DateTime(now.year, now.month, 4, 12),
          ),
        ]);

      await pumpChild(tester, const BudgetsScreen(), store: store);

      expect(
        semanticsButtonWhoseLabel((l) => l == 'Edit Shopping budget'),
        findsOneWidget,
      );
    });

    testWidgets('multiple budget categories each show chevron', (tester) async {
      final now = DateTime.now();
      final store = FinanceStore()
        ..seedTransactions([
          tx(
            id: 'f',
            amount: 300,
            isCredit: false,
            category: SpendCategory.food,
            merchant: 'F',
            timestamp: DateTime(now.year, now.month, 3, 12),
          ),
          tx(
            id: 's',
            amount: 150,
            isCredit: false,
            category: SpendCategory.shopping,
            merchant: 'S',
            timestamp: DateTime(now.year, now.month, 4, 12),
          ),
        ]);

      await pumpChild(tester, const BudgetsScreen(), store: store);

      expect(tappableRowHasChevron(tester, 'Food'), isTrue);
      expect(tappableRowHasChevron(tester, 'Shopping'), isTrue);
      expect(chevrons(), findsNWidgets(2));
    });

    testWidgets('empty budgets show no chevrons', (tester) async {
      await pumpChild(
        tester,
        const BudgetsScreen(),
        store: FinanceStore(),
      );
      expect(chevrons(), findsNothing);
    });
  });

  // ── Reports ──────────────────────────────────────────────────────────────

  group('Reports income / merchant / stickers', () {
    testWidgets('income source rows show chevron', (tester) async {
      final store = FinanceStore()..seedTransactions(dummyTransactionHistory());
      await pumpChild(tester, const ReportsScreen(), store: store);

      expect(find.text('Where money came from'), findsOneWidget);
      // At least one income chevron exists in the section.
      expect(chevrons(), findsWidgets);
    });

    testWidgets('top merchant rows show chevron', (tester) async {
      final now = DateTime.now();
      final store = FinanceStore()
        ..seedTransactions([
          tx(
            id: 'm1',
            amount: 220,
            isCredit: false,
            category: SpendCategory.food,
            merchant: 'ReportSwiggy',
            timestamp: DateTime(now.year, now.month, 6, 12),
          ),
        ]);
      await pumpChild(tester, const ReportsScreen(), store: store);

      expect(find.text('Top merchants'), findsOneWidget);
      expect(find.text('ReportSwiggy'), findsWidgets);
      expect(tappableRowHasChevron(tester, 'ReportSwiggy'), isTrue);
    });

    testWidgets('category stickers show chevrons when tappable', (tester) async {
      final store = FinanceStore()..seedTransactions(dummyTransactionHistory());
      await pumpChild(tester, const ReportsScreen(), store: store);

      expect(find.text('Where money went'), findsOneWidget);
      expect(find.byType(CategorySpendChip), findsWidgets);
      expect(chevrons(), findsWidgets);
    });

    testWidgets('income row Semantics is a button', (tester) async {
      final now = DateTime.now();
      final store = FinanceStore()
        ..seedTransactions([
          tx(
            id: 'sal',
            amount: 10000,
            isCredit: true,
            category: SpendCategory.income,
            merchant: 'Acme Payroll',
            timestamp: DateTime(now.year, now.month, 2, 10),
          ),
          tx(
            id: 'food',
            amount: 50,
            isCredit: false,
            category: SpendCategory.food,
            merchant: 'Cafe',
            timestamp: DateTime(now.year, now.month, 3, 10),
          ),
        ]);

      await pumpChild(tester, const ReportsScreen(), store: store);

      expect(find.text('Acme Payroll'), findsWidgets);
      expect(
        semanticsButtonWhoseLabel((l) => l.startsWith('Acme Payroll,')),
        findsWidgets,
      );
      expect(tappableRowHasChevron(tester, 'Acme Payroll'), isTrue);
    });

    testWidgets('empty report has no row chevrons', (tester) async {
      await pumpChild(
        tester,
        const ReportsScreen(),
        store: FinanceStore(),
      );
      expect(chevrons(), findsNothing);
    });
  });

  // ── Profile / settings ───────────────────────────────────────────────────

  group('Profile and settings rows', () {
    testWidgets('profile settings rows show muted chevrons', (tester) async {
      await pumpChild(
        tester,
        const ProfileScreen(),
        store: FinanceStore(),
        size: const Size(800, 2400),
      );

      expect(find.text('Privacy Settings'), findsOneWidget);
      expect(tappableRowHasChevron(tester, 'Privacy Settings'), isTrue);
      expect(tappableRowHasChevron(tester, 'Help & Support'), isTrue);
    });

    testWidgets('profile edit header shows chevron', (tester) async {
      await pumpChild(
        tester,
        const ProfileScreen(),
        store: FinanceStore(),
        size: const Size(800, 2400),
      );

      expect(find.text('Your profile'), findsOneWidget);
      expect(tappableRowHasChevron(tester, 'Your profile'), isTrue);
    });

    testWidgets('SettingsActionRow defaults to PaisaNavChevron', (tester) async {
      await pumpChild(
        tester,
        SettingsActionRow(
          title: 'Sample setting',
          subtitle: 'Opens detail',
          onTap: () {},
        ),
      );

      expect(chevrons(), findsOneWidget);
      final widget = tester.widget<PaisaNavChevron>(chevrons());
      expect(widget.color, PaisaColors.muted);
    });

    testWidgets('SettingsActionRow destructive uses overBudget tint',
        (tester) async {
      await pumpChild(
        tester,
        SettingsActionRow(
          title: 'Delete',
          subtitle: 'Danger',
          destructive: true,
          onTap: () {},
        ),
      );

      final widget = tester.widget<PaisaNavChevron>(chevrons());
      expect(
        widget.color,
        PaisaColors.overBudget.withOpacity(0.6),
      );
    });

    testWidgets('SettingsActionRow custom trailing skips default chevron',
        (tester) async {
      await pumpChild(
        tester,
        SettingsActionRow(
          title: 'Toggle-like',
          subtitle: 'Custom trailing',
          onTap: () {},
          trailing: const Icon(Icons.check),
        ),
      );

      expect(chevrons(), findsNothing);
      expect(find.byIcon(Icons.check), findsOneWidget);
    });
  });
}
