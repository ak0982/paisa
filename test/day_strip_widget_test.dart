import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/models/transaction.dart';
import 'package:paisa_app/providers/app_settings.dart';
import 'package:paisa_app/providers/finance_store.dart';
import 'package:paisa_app/screens/day_strip_screen.dart';
import 'package:paisa_app/services/sms/account_discovery.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppSettings settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await AppSettings.load();
  });

  testWidgets('Day Strip empty day shows No money moved', (tester) async {
    final store = FinanceStore();

    await tester.pumpWidget(
      buildTestApp(
        settings: settings,
        store: store,
        child: DayStripScreen(initialDay: DateTime(2026, 8, 16)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No money moved'), findsOneWidget);
    expect(find.textContaining('net'), findsOneWidget);
  });

  testWidgets('Day Strip shows MOVE badge for CC bill payment', (tester) async {
    final day = DateTime(2026, 8, 15, 12);
    final store = FinanceStore()
      ..seedTransactions([
        Transaction(
          id: 'food',
          smsId: 'food',
          merchant: 'Swiggy',
          bank: 'SBI',
          maskedAccount: '••••0429',
          category: SpendCategory.food,
          amount: 100,
          isCredit: false,
          timestamp: day,
        ),
        Transaction(
          id: 'ccbp',
          smsId: 'ccbp',
          merchant: 'Credit card bill payment',
          bank: 'HDFC',
          maskedAccount: '••••1111',
          category: SpendCategory.transfer,
          amount: 500,
          isCredit: false,
          timestamp: day.add(const Duration(hours: 1)),
          accountKind: AccountKind.creditCard,
        ),
      ]);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<FinanceStore>.value(value: store),
          ChangeNotifierProvider<AppSettings>.value(value: settings),
        ],
        child: MaterialApp(
          home: DayStripScreen(initialDay: day),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('MOVE'), findsOneWidget);
    expect(find.text('Swiggy · Food'), findsOneWidget);
    expect(find.textContaining('₹100.00'), findsWidgets);
  });

  testWidgets('Day Strip range header and calendar control', (tester) async {
    final store = FinanceStore()
      ..seedTransactions([
        Transaction(
          id: 'a',
          smsId: 'a',
          merchant: 'Cafe',
          bank: 'SBI',
          maskedAccount: '••••0429',
          category: SpendCategory.food,
          amount: 80,
          isCredit: false,
          timestamp: DateTime(2026, 8, 12, 10),
        ),
        Transaction(
          id: 'b',
          smsId: 'b',
          merchant: 'Pay',
          bank: 'SBI',
          maskedAccount: '••••0429',
          category: SpendCategory.income,
          amount: 200,
          isCredit: true,
          timestamp: DateTime(2026, 8, 15, 11),
        ),
      ]);

    await tester.pumpWidget(
      buildTestApp(
        settings: settings,
        store: store,
        child: DayStripScreen(
          initialDay: DateTime(2026, 8, 12),
          initialEnd: DateTime(2026, 8, 15),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('12–15 AUG'), findsOneWidget);
    expect(find.byTooltip('Pulse Calendar'), findsOneWidget);
    expect(find.text('ALL'), findsOneWidget);
    expect(find.text('OUT'), findsWidgets);
    expect(find.text('IN'), findsWidgets);
    expect(find.textContaining('Cafe'), findsOneWidget);
    expect(find.textContaining('Pay'), findsOneWidget);
  });
}
