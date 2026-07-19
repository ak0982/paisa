import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/app_settings.dart';
import 'providers/finance_store.dart';
import 'screens/main_shell.dart';
import 'screens/onboarding/welcome_screen.dart';
import 'theme/paisa_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  final prefs = await SharedPreferences.getInstance();
  final onboardingComplete = prefs.getBool('onboarding_complete') ?? false;
  final appSettings = AppSettings(prefs);

  final store = FinanceStore();
  await store.init();

  const categorizerVersion = 4;
  // Bumped 10 -> 11: the full scan now reads the ENTIRE SMS inbox (no 24-month
  // cap). This forces a one-time full re-scan on the next launch so existing
  // installs pick up older messages (3-4+ years) that the previous 24-month
  // window skipped.
  // Bumped 11 -> 12: discovered accounts now derive their kind (savings / credit
  // card / loan) from the strongest signal across all transactions for a
  // bank+mask, not just narrow discovery regexes. Forces a rebuild so existing
  // installs re-classify accounts (credit cards no longer show up as savings).
  // Bumped 12 -> 13: account-kind classification is now BALANCED voting per mask
  // instead of "any credit-card evidence wins". A savings account that pays a
  // credit-card bill (CCBP/BBPS debit) or receives a card-related SMS is no
  // longer flipped to "credit card" — the dominant kind for the mask wins, so
  // real savings accounts are detected again. Forces a rebuild to re-classify.
  // Bumped 13 -> 14: savings-account COVERAGE fix. Discovery now recognises
  // savings accounts known only from balance / interest / informational SMS
  // ("in/on/to your A/c XX1234", "A/c 1234 credited/debited with …") and
  // resolves Federal Bank (incl. Fi / Jupiter neobanks) and PNB long masks, so
  // genuine savings accounts that never produced a parsed transaction (e.g.
  // Federal ••••7953, Federal ••••3455, PNB ••••4720) surface instead of being
  // dropped. Forces a rebuild so existing installs pick up the missing accounts.
  const transactionSchemaVersion = 14;
  final needsRescan =
      (prefs.getInt('categorizer_version') ?? 0) < categorizerVersion ||
      (prefs.getInt('transaction_schema_version') ?? 0) <
          transactionSchemaVersion;
  if (needsRescan) {
    await store.fullRescanFromSms();
    await prefs.setInt('categorizer_version', categorizerVersion);
    await prefs.setInt('transaction_schema_version', transactionSchemaVersion);
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: store),
        ChangeNotifierProvider.value(value: appSettings),
      ],
      child: PaisaApp(showMain: onboardingComplete),
    ),
  );
}

class PaisaApp extends StatelessWidget {
  const PaisaApp({super.key, required this.showMain});

  final bool showMain;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Paisa',
      debugShowCheckedModeBanner: false,
      theme: PaisaTheme.light(),
      home: showMain ? const MainShell() : const WelcomeScreen(),
    );
  }
}
