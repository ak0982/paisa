import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/providers/app_settings.dart';
import 'package:paisa_app/providers/finance_store.dart';
import 'package:paisa_app/screens/edit_profile_screen.dart';
import 'package:paisa_app/screens/profile_screen.dart';
import 'package:paisa_app/screens/settings/help_support_screen.dart';
import 'package:paisa_app/screens/settings/privacy_settings_screen.dart';
import 'package:paisa_app/widgets/transaction_row.dart';

import 'helpers/dummy_data.dart';
import 'helpers/test_harness.dart';

void main() {
  late AppSettings settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await AppSettings.load();
  });

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    FinanceStore? store,
    AppSettings? appSettings,
  }) async {
    await tester.pumpWidget(
      buildTestApp(
        child: child,
        settings: appSettings ?? settings,
        store: store,
      ),
    );
    await tester.pumpAndSettle();
  }

  group('U15-U34 Settings & profile widgets', () {
    testWidgets('U15 Profile shows settings rows', (tester) async {
      await pump(
        tester,
        const ProfileScreen(),
        store: FinanceStore()..seedTransactions(dummyTransactionHistory()),
      );

      expect(find.text('Notifications'), findsNothing);
      expect(find.text('Rescan SMS'), findsOneWidget);
      expect(find.text('Privacy Settings'), findsOneWidget);
      expect(find.text('Help & Support'), findsOneWidget);
      expect(find.text('Logout'), findsOneWidget);
    });

    testWidgets('U17 Profile navigates to Privacy Settings', (tester) async {
      await pump(tester, const ProfileScreen(), store: FinanceStore());

      await tester.tap(find.text('Privacy Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Your privacy is guaranteed'), findsOneWidget);
      expect(find.byType(PrivacySettingsScreen), findsOneWidget);
    });

    testWidgets('U18 Profile navigates to Help & Support', (tester) async {
      await pump(tester, const ProfileScreen(), store: FinanceStore());

      await tester.tap(find.text('Help & Support'));
      await tester.pumpAndSettle();

      expect(find.text('How does Paisa detect transactions?'), findsOneWidget);
      expect(find.byType(HelpSupportScreen), findsOneWidget);
    });

    testWidgets('U19 Logout shows confirmation dialog', (tester) async {
      await pump(
        tester,
        const ProfileScreen(),
        store: FinanceStore()..seedTransactions(dummyTransactionHistory()),
      );

      await tester.scrollUntilVisible(
        find.text('Logout'),
        120,
        scrollable: find.byType(Scrollable),
      );
      await tester.tap(find.text('Logout'));
      await tester.pumpAndSettle();

      expect(find.text('Log out?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('U20 Logout cancel dismisses dialog', (tester) async {
      await pump(tester, const ProfileScreen(), store: FinanceStore());

      await tester.scrollUntilVisible(
        find.text('Logout'),
        120,
        scrollable: find.byType(Scrollable),
      );
      await tester.tap(find.text('Logout'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Log out?'), findsNothing);
      expect(find.text('Profile'), findsOneWidget);
    });

    testWidgets('U25 Privacy screen shows mask merchant toggle', (tester) async {
      await pump(
        tester,
        const PrivacySettingsScreen(),
        store: FinanceStore(),
      );

      expect(find.text('Mask merchant names'), findsOneWidget);
      expect(find.text('Clear local data'), findsOneWidget);
    });

    testWidgets('U26 Privacy mask toggle updates settings', (tester) async {
      await pump(
        tester,
        const PrivacySettingsScreen(),
        store: FinanceStore(),
      );

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      expect(settings.maskMerchantNames, isTrue);
    });

    testWidgets('U27 Privacy shows SMS permission row', (tester) async {
      await pump(
        tester,
        const PrivacySettingsScreen(),
        store: FinanceStore(),
      );

      expect(find.text('SMS permission'), findsOneWidget);
      expect(find.text('Manage SMS permission'), findsOneWidget);
    });

    testWidgets('U28 Help screen shows four FAQs', (tester) async {
      await pump(tester, const HelpSupportScreen());

      expect(find.text('Why is SMS permission required?'), findsOneWidget);
      expect(find.text('How do I refresh my data?'), findsOneWidget);
      expect(find.text('Are personal chats read?'), findsOneWidget);
      expect(find.text('support@paisa.app'), findsOneWidget);
    });

    testWidgets('U29 Help screen shows version footer', (tester) async {
      await pump(tester, const HelpSupportScreen());

      await tester.scrollUntilVisible(
        find.text('Paisa · version 1.0.0'),
        120,
        scrollable: find.byType(Scrollable),
      );

      expect(find.text('Paisa · version 1.0.0'), findsOneWidget);
    });

    testWidgets('U30 TransactionRow shows full merchant by default',
        (tester) async {
      await pump(
        tester,
        TransactionRow(
          transaction: dummyTxn(
            id: 'w1',
            merchant: 'Swiggy',
            amount: 486,
            isCredit: false,
            timestamp: DateTime(2026, 7, 7),
            category: SpendCategory.food,
          ),
        ),
      );

      expect(find.text('Swiggy'), findsOneWidget);
    });

    testWidgets('U31 TransactionRow masks merchant when enabled',
        (tester) async {
      await settings.setMaskMerchantNames(true);

      await pump(
        tester,
        TransactionRow(
          transaction: dummyTxn(
            id: 'w2',
            merchant: 'Swiggy',
            amount: 486,
            isCredit: false,
            timestamp: DateTime(2026, 7, 7),
          ),
        ),
      );

      expect(find.text('Sw••••gy'), findsOneWidget);
      expect(find.text('Swiggy'), findsNothing);
    });

    testWidgets('U32 TransactionRow masks short merchant names', (tester) async {
      await settings.setMaskMerchantNames(true);

      await pump(
        tester,
        TransactionRow(
          transaction: dummyTxn(
            id: 'w3',
            merchant: 'Ola',
            amount: 100,
            isCredit: false,
            timestamp: DateTime(2026, 7, 7),
          ),
        ),
      );

      expect(find.text('O••a'), findsOneWidget);
    });

    testWidgets('U33 TransactionRow shows credit amount in green', (tester) async {
      await pump(
        tester,
        TransactionRow(
          transaction: dummyTxn(
            id: 'w4',
            merchant: 'Salary',
            amount: 50000,
            isCredit: true,
            timestamp: DateTime(2026, 7, 1),
            category: SpendCategory.income,
          ),
        ),
      );

      expect(find.textContaining('+₹'), findsOneWidget);
    });

    testWidgets('U34 TransactionRow hides SMS label when disabled',
        (tester) async {
      await pump(
        tester,
        TransactionRow(
          transaction: dummyTxn(
            id: 'w5',
            merchant: 'Amazon',
            amount: 100,
            isCredit: false,
            timestamp: DateTime(2026, 7, 7),
          ),
          showSmsLabel: false,
        ),
      );

      expect(find.text('⚡ From SMS'), findsNothing);
    });

    testWidgets('U35 Privacy clear data shows confirmation', (tester) async {
      await pump(
        tester,
        const PrivacySettingsScreen(),
        store: FinanceStore()..seedTransactions(dummyTransactionHistory()),
      );

      await tester.scrollUntilVisible(
        find.text('Clear local data'),
        120,
        scrollable: find.byType(Scrollable),
      );
      await tester.tap(find.text('Clear local data'));
      await tester.pumpAndSettle();

      expect(find.text('Clear local data?'), findsOneWidget);
    });

    testWidgets('U54 Edit profile prefills saved name and email',
        (tester) async {
      await settings.setProfile(name: 'Rahul Kumar', email: 'rahul@paisa.app');
      await pump(tester, const EditProfileScreen());

      expect(find.text('Rahul Kumar'), findsOneWidget);
      expect(find.text('rahul@paisa.app'), findsOneWidget);
      expect(find.text('SAVE CHANGES'), findsOneWidget);
    });

    testWidgets('U55 Edit profile saves updated name', (tester) async {
      await settings.setProfile(name: 'Old Name');
      await pump(tester, const EditProfileScreen());

      await tester.enterText(find.byType(TextFormField).first, 'New Name');
      await tester.tap(find.text('SAVE CHANGES'));
      await tester.pumpAndSettle();

      expect(settings.userName, 'New Name');
    });

    testWidgets('U56 Edit profile rejects empty name', (tester) async {
      await settings.setProfile(name: 'Someone');
      await pump(tester, const EditProfileScreen());

      await tester.enterText(find.byType(TextFormField).first, '');
      await tester.tap(find.text('SAVE CHANGES'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter your name'), findsOneWidget);
      expect(settings.userName, 'Someone');
    });

    testWidgets('U57 Edit profile rejects invalid email', (tester) async {
      await settings.setProfile(name: 'Someone');
      await pump(tester, const EditProfileScreen());

      await tester.enterText(find.byType(TextFormField).at(1), 'not-an-email');
      await tester.tap(find.text('SAVE CHANGES'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid email or leave it blank'), findsOneWidget);
    });
  });
}
