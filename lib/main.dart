import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/app_settings.dart';
import 'providers/finance_store.dart';
import 'screens/main_shell.dart';
import 'screens/onboarding/welcome_screen.dart';
import 'theme/paisa_theme.dart';

/// Bumped when the categorizer's rules change enough to need a rebuild.
const int categorizerVersion = 4;

// transactionSchemaVersion — bump (with a changelog line) whenever a change
// affects parsing, enrichment, discovery or classification, so existing installs
// trigger a one-time full rescan. See AGENTS.md §"schema versioning".
//
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
// Bumped 14 -> 15: incremental sync no longer wipes previously discovered
// accounts. Persistence switched from a destructive delete-and-replace to a
// non-destructive merge upsert (ISSUE-1). Forces a one-time full rescan so
// existing installs that had already lost balance/interest-only savings
// accounts on a prior incremental sync repopulate them.
// Bumped 15 -> 16: the background parse isolate now runs the full staged Dart
// gate (SmsScanPipeline: OTP / promo / scam-obfuscation / transaction-signal)
// before parsing, instead of calling SmsParser.parseTransaction directly. The
// native Kotlin filter is demoted to a coarse thinner (promo/scam logic
// removed) so Dart is the single source of truth (ISSUE-2). Forces a rescan
// so promo/scam SMS that slipped past the weaker native-only gate on existing
// installs are re-filtered out.
// Bumped 16 -> 17: isRealTransactionSms now rejects personal 10-digit senders
// BEFORE the completed-transaction-signal shortcut, so scam SMS from personal
// numbers that mimic bank alerts ("Rs.X debited from a/c XX1234") are no
// longer accepted (ISSUE-3). Forces a rescan so any such rows already stored
// are removed.
// Bumped 17 -> 18: spend/income KPIs now EXCLUDE internal movement so the
// headline numbers reflect real money in/out (ISSUE-4): credit-card bill
// payments and CC "payment received" legs are dropped via per-transaction
// flags, and self / account-to-account transfers are netted out by pairing a
// transfer-categorised debit with a same-amount credit within 3 minutes. Also
// adds cross-source de-duplication at insert time (bank + wallet SMS for the
// same UPI payment now store one row). Lists still show every row. Forces a
// rescan so the de-dupe applies to already-stored data.
// Bumped 18 -> 19: amount regex accepts a single decimal digit ("Rs 500.5"
// → 500.5) instead of only exactly two digits, which previously truncated to
// 500 (ISSUE-14). Forces a rescan so any truncated amounts are re-parsed.
// Bumped 19 -> 20: categorizer precision (ISSUE-13) — short keywords use word
// boundaries (ola⊄Cola, jio⊄Jiomart), BBPS/CCBP debits classify as transfer
// before bills keywords, and personal NACH→"Home Loan EMI" hardcoding is gone.
// Bumped 20 -> 21: account-kind evidence and spend stats are keyed by
// (bank, mask) instead of mask alone, so two banks sharing a last-4 no longer
// merge into one pooled account (ISSUE-11). Forces a rebuild to re-split.
// Bumped 21 -> 22: adversarial QA fixes — (1) personal-sender gate also matches
// bare 10-digit Indian mobiles (not only +91…), so scam "Rs.X debited" SMS are
// rejected by the production pipeline; (2) self-transfer KPI pairing requires
// two distinct real bank|mask legs (stops LenDenClub/P2P credits from zeroing
// merchant UPI spend); (3) CCBP/bill-payment merchant wording excludes spend
// even when enrichment left accountKind=savings.
// Bumped 22 -> 23: HSBC India first-class support — sender/body bank mapping
// (HSBCIN / HSBC*), savings "is paid from" / "is credited to|with" / debit-card
// and CC "creditcard … used at" / payment-received patterns, discovery + logo,
// _realBanks allowlist. Forces a rescan so HSBC SMS previously ignored as
// unknown bank are picked up.
const int transactionSchemaVersion = 23;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFF0A0A0B),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  final prefs = await SharedPreferences.getInstance();
  final onboardingComplete = prefs.getBool('onboarding_complete') ?? false;
  final appSettings = AppSettings(prefs);

  final store = FinanceStore();
  await store.init();

  final needsRescan =
      (prefs.getInt('categorizer_version') ?? 0) < categorizerVersion ||
      (prefs.getInt('transaction_schema_version') ?? 0) <
          transactionSchemaVersion;

  // ISSUE-7: do NOT block the splash on the rescan. Hand the decision to the
  // store so the app shell runs it after the first frame (with progress UI).
  // Gate on onboarding: fresh installs (onboarding not complete) flow through
  // the onboarding scan instead, so the OS permission dialog appears over the
  // onboarding screen rather than a dead splash. Stamps are written only after
  // the rescan completes (in runLaunchScan / onboarding), so a killed rescan
  // retries on the next launch.
  Future<void> persistScanVersions() async {
    await prefs.setInt('categorizer_version', categorizerVersion);
    await prefs.setInt('transaction_schema_version', transactionSchemaVersion);
  }

  store.configureLaunchScan(
    needsRescan: needsRescan && onboardingComplete,
    persistVersions: persistScanVersions,
  );

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
      theme: PaisaTheme.dark(),
      themeMode: ThemeMode.dark,
      home: showMain ? const MainShell() : const WelcomeScreen(),
    );
  }
}
