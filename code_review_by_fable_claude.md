# Code Review by Claude (Fable) — Paisa

**Repo:** `ak0982/paisa` @ `main` · **Date:** 21 Jul 2026
**Audience:** This document is written so an AI coding agent (Cursor) can pick up each issue and fix it. Every issue has an ID, verified evidence (file:line), impact, and a proposed fix. Line numbers refer to `main` at review time.

**Verification note:** All P0 findings were double-checked by re-reading the cited lines verbatim on 21 Jul 2026. In particular: `transaction_database.dart:144` really does `db.delete('discovered_accounts')` before inserting; `sms_reader_service.dart` contains **zero** references to `SmsScanPipeline`; `sms_parse_isolate.dart:65` calls `SmsParser.parseTransaction(message)` directly and contains **zero** references to `isRealTransactionSms` / `isPromoOrOfferSms`.

> ⚠️ Per `AGENTS.md` §8: whenever any fix below changes parsing, enrichment, discovery, or classification, **bump `transactionSchemaVersion` in `lib/main.dart`** with a changelog comment.

---

## What's genuinely good (keep these)

- Real layered architecture: UI → `FinanceStore` → services → sqflite. Screens never touch the parser.
- `_AccountKindEvidence` balanced per-mask voting with CCBP funding-side attribution (`finance_store.dart:1023–1125`) is a well-reasoned design; the inline comments explain *why*, not just *what*.
- Defensive native paging with three-tier OEM fallback (`MainActivity.kt:128–186`).
- `transactionSchemaVersion` wipe-and-rebuild gate with a written changelog (`main.dart:28–49`).
- Checkpoint/resume scan state, background isolate for parsing, re-entrancy-guarded sync (`finance_store.dart:108–110`).
- Privacy-first: zero network packages in `pubspec.yaml`, SMS dumps git-ignored, merchant-masking toggle actually wired (`transaction_row.dart:37–43`).
- Honest `AGENTS.md` (admits no CI, squashed history, dump-dependent tests) and a real ~353-test suite.

---

# P0 — Data correctness (fix first, in this order)

## ISSUE-1: Every incremental sync wipes previously discovered accounts

**Status: RE-VERIFIED ✅**

**Evidence**
- `lib/data/transaction_database.dart:142–145` — `saveDiscoveredAccounts` runs `await db.delete('discovered_accounts');` **before** inserting; if `items.isEmpty` it returns *after* the delete, leaving the table empty.
- `lib/providers/finance_store.dart:171–172` — `_runSync` unconditionally does `_discoveredAccounts = scan.discoveredAccounts; await _db.saveDiscoveredAccounts(_discoveredAccounts);` on **every** sync, including incremental.
- `lib/services/sms/sms_reader_service.dart:209–211, 352–360` — incremental scans only read messages since `lastScanAt − 1h`, so `scan.discoveredAccounts` is nearly always empty on a routine launch.

**Impact:** On the *second* app launch, all accounts discovered from the full-history scan (especially balance/interest-only savings accounts — the exact feature schema v14 was bumped for) are deleted from the DB and vanish from Profile. Silent, cumulative data loss.

**Fix**
1. In `TransactionDatabase`, replace delete-and-replace with a merge upsert:
```dart
Future<void> mergeDiscoveredAccounts(List<DiscoveredAccount> items) async {
  final db = await database;
  final batch = db.batch();
  for (final item in items) {
    batch.rawInsert('''
      INSERT INTO discovered_accounts
        (account_key, bank, mask, kind, account_label, sms_hits, spent_total, received_total)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(account_key) DO UPDATE SET
        sms_hits = sms_hits + excluded.sms_hits,
        spent_total = spent_total + excluded.spent_total,
        received_total = received_total + excluded.received_total,
        account_label = COALESCE(discovered_accounts.account_label, excluded.account_label)
    ''', [item.key, item.bank, item.mask, item.kind.name, item.accountLabel,
          item.smsHits, item.spentTotal, item.receivedTotal]);
  }
  await batch.commit(noResult: true);
}
```
2. In `_runSync`: merge instead of replace — `await _db.mergeDiscoveredAccounts(scan.discoveredAccounts); _discoveredAccounts = await _db.getDiscoveredAccounts();`
3. Keep the destructive path only inside `fullRescanFromSms()` (which already calls `clearAll()`).
4. **Test to add:** full scan discovers N accounts → incremental scan with 0 new messages → `getDiscoveredAccounts()` still returns N.

---

## ISSUE-2: Production bypasses the tested filter pipeline (promo/scam filters never run on device)

**Status: RE-VERIFIED ✅**

**Evidence**
- `lib/services/sms/sms_reader_service.dart:1–10` — imports contain **no** `sms_scan_pipeline.dart`; the string `SmsScanPipeline` does not appear anywhere in the file.
- `lib/services/sms/sms_parse_isolate.dart:65` — pass 2 calls `SmsParser.parseTransaction(message)` directly. The file has zero references to `isRealTransactionSms`, `isPromoOrOfferSms`, or `SmsScanPipeline`.
- `lib/services/sms/sms_parser.dart:375–376` — `parseTransaction`'s own doc: "caller must have already passed pipeline gates". In production, nobody has.
- The actual production gate is Kotlin: `SmsNativeFilter.passesPreFilter` (`android/.../SmsNativeFilter.kt:95–105`). Its promo list is ~18 phrases (`:29–35`) vs the Dart `_promoOfferPattern`'s dozens of patterns plus scam-obfuscation detection (`L0AN`, `Appr0ve`, fake wallet credits — `sms_parser.dart:57–80`), which the native side lacks entirely.

**Impact:** The staged pipeline described in README/AGENTS.md, and validated by `sms_scan_pipeline_test.dart` etc., is effectively **test-only dead code**. Promo/scam SMS that the test suite proves are rejected can be ingested as transactions on a real device. Docs, tests, and production disagree — the worst kind of drift for future agents.

**Fix (recommended shape)**
1. In `_parseCandidates` (`sms_parse_isolate.dart`), run the full Dart gate before parsing:
```dart
final result = SmsScanPipeline.process(message);
if (!result.isParsed) continue;
final parsed = result.transaction!;
```
   This is cheap: candidates are already pre-thinned natively, and this runs in the isolate.
2. Demote `SmsNativeFilter` to a coarse pre-filter only (sender/length/OTP); delete its promo mirror (`BankPromoNative`) so there is exactly **one** source of truth for promo/scam logic (Dart). Over-returning candidates is fine — the isolate now re-gates.
3. Update the data-flow section of README/AGENTS.md to match.
4. **Test to add:** an end-to-end test that feeds a known scam SMS ("Your L0AN is appr0ved… Rs 50,000 credited…") through `parseCandidatesInIsolate`'s `_parseCandidates` and asserts it produces no hit.
5. Bump `transactionSchemaVersion`.

---

## ISSUE-3: Scam / personal-number SMS can become transactions

**Status: RE-VERIFIED ✅ (two independent holes)**

**Evidence**
- **Hole 1 (production/native):** `SmsNativeFilter.passesFinancialGate` (`SmsNativeFilter.kt:57–62`) passes **any** body ≥ 20 chars containing a `bodyTxnHints` substring — the list includes `"rs."`, `"rs "`, `"account"`, `"paid"`, `"balance"` (`:22–27`) — with **no sender check**. `isPromo` returns false early whenever the body contains a completed hint like `"debited"` (`:73–78`). Combined with ISSUE-2 (no Dart gate), an SMS from any 10-digit number saying *"Rs.4,999 debited from your a/c XX1234"* reaches `parseTransaction`, matches the generic debit pattern (`sms_parser.dart:984–991`), and is stored with `bank == 'Bank'` (`_resolveBank` fallback, `sms_parser.dart:311`). Nothing in `_runSync` filters it out of the ledger or analytics.
- **Hole 2 (Dart, affects `parse()`/tests too):** `isRealTransactionSms` (`sms_parser.dart:160–178`) checks `hasCompletedTransactionSignal` at line 167 and returns `true` **before** the `isPersonalPhoneSender` rejection at line 169 — so even the strict path accepts personal-number SMS with completed-transaction phrasing.

**Impact:** In a finance app whose entire pitch is trustworthy numbers, common Indian scam texts (typically sent from personal 10-digit numbers) inflate spend/income silently.

**Fix**
1. Fix the ordering in `isRealTransactionSms`: reject personal senders **before** the completed-signal shortcut, or require a stricter signal (known bank name + mask marker in body) when the sender is a personal number:
```dart
if (isPersonalPhoneSender(sender)) {
  // Personal numbers never send legitimate bank alerts.
  return false;
}
if (hasCompletedTransactionSignal(trimmed)) return true;
```
2. Apply ISSUE-2's fix so this gate actually runs in production.
3. Consider dropping transactions whose resolved bank is the `'Bank'` placeholder AND whose sender is not a recognized financial sender.
4. **Tests to add:** personal-number sender + "debited" body → rejected; DLT-style sender (e.g. `VM-HDFCBK`) + same body → accepted.

---

## ISSUE-4: Spend/income are structurally inflated — transfers, CC-bill legs, and duplicate SMS all count

**Status: RE-VERIFIED ✅**

**Evidence**
- `lib/models/transaction.dart:43` — `bool get countsTowardCashflowSummary => true;` (everything counts). `:46` — `countsTowardIncome => isCredit` (every credit is "income", including self-transfer credits and CC "payment received" legs).
- `lib/providers/finance_store.dart:632–646` — `monthlySpent` = all debits; `monthlyIncome` = all credits; `savingsRate` derives from both. Same base feeds budgets (`:712–724`), insights, reports (`buildReport:316–396`), top merchants.
- Dedupe is **by SMS id only** (`transactions.sms_id UNIQUE`, `transaction_database.dart:53`). One UPI payment commonly yields two SMS — the bank's *"debited from a/c"* (patterns at `sms_parser.dart:842–901`) and the wallet's *"Rs.X paid to Y via Paytm"* (`:902–910`) — different SMS ids → **two stored transactions**.
- A credit-card bill payment produces: card spends (debits) + funding-account bill-payment debit + card-side "payment received" credit → spend counted twice-ish, plus fake "income".

**Impact:** Moving ₹50k between your own accounts adds ₹50k to *both* monthly spend and monthly income. `savingsRate` is meaningless for anyone with a credit card. Every analytic downstream inherits the distortion. (AGENTS.md documents "track everything" as a philosophy — tracking in *lists* is fine; the *KPIs* must exclude internal movement.)

**Fix**
1. Keep transfers visible in lists, but exclude them from KPIs. The data already exists (`SpendCategory.transfer`, `isCreditCardBillPayment`):
```dart
// transaction.dart
bool get isInternalMovement =>
    category == SpendCategory.transfer || isCreditCardBillPayment;
bool get countsTowardSpend => !isCredit && !isInternalMovement;
bool get countsTowardIncome => isCredit && !isInternalMovement
    && accountKind != AccountKind.creditCard; // CC "payment received" is not income
```
2. Use `countsTowardSpend/Income` in `monthlySpent`, `monthlyIncome`, `savingsRate`, `categorySpending`, `budgets`, `buildReport`, insights getters. Home lists can keep showing transfers with their existing `flowLabel` badges.
3. Add cross-source dedupe at insert time: before saving, skip a new txn if an existing txn has same direction, same amount, timestamp within ±3 min, and (same mask OR one side is a wallet-bank) — prefer the bank-sourced row over the wallet-sourced one.
4. **Tests to add:** SBI→Axis self-transfer pair → spend 0, income 0; card spend ₹1000 + CCBP ₹1000 + card credit ₹1000 → spend ₹1000, income 0; bank SMS + Paytm SMS for the same payment → one stored transaction.
5. Bump `transactionSchemaVersion`.

---

# P1 — Product honesty & UX

## ISSUE-5: Budgets are circular — can never be exceeded

**Evidence:** `finance_store.dart:716–723` — `limit = ceil(spent × 1.3 / 100) × 100` (floor ₹1,000), recomputed from the current month's own spending. Progress is mathematically capped at `1/1.3 ≈ 77%` and the "limit" grows as you spend.

**Impact:** Budgets cannot warn, cannot be exceeded, and don't reflect user intent. The feature looks real but is cosmetic.

**Fix:** Store per-category user limits (new `budgets` table or shared_preferences map), seeded once from e.g. median of the last 3 months' spend ×1.1. Keep the auto value only as the initial suggestion. Render >100% states (`PaisaProgressBar` already has an `overBudget` color). Optional: tie alerts to ISSUE-6.

## ISSUE-6: Notification settings are placebo; RECEIVE_SMS permission is held but unused

**Evidence:** `app_settings.dart:18–20` persists `budgetAlerts` / `weeklySummary` / `syncCompleteAlerts` and the settings screen edits them — but `pubspec.yaml` contains **no notification package** and there is no scheduler/receiver anywhere. `AndroidManifest.xml:3` declares `RECEIVE_SMS`, but the manifest has no `<receiver>` and `MainActivity.kt` registers none — so there is no real-time capture either; data refreshes only when the app opens.

**Fix (pick one, do it fully):**
- *Implement:* add `flutter_local_notifications`; add an `SMS_RECEIVED` BroadcastReceiver that runs the (post-ISSUE-2) pipeline on the incoming message and inserts it → live "today" data + real sync/budget alerts.
- *Or remove:* delete the three toggles + `RECEIVE_SMS` from the manifest. Holding an unused dangerous SMS permission is a Play-policy rejection and erodes the privacy story.

## ISSUE-7: Version-bump rescan blocks startup; fresh installs get the permission dialog before any UI

**Evidence:** `main.dart:54–58` — `await store.fullRescanFromSms()` runs **before** `runApp` (line 60). On a fresh install prefs are unset → `needsRescan == true` → `_runSync` calls `requestSmsPermission()` (`finance_store.dart:131–134`) → the system SMS dialog appears over a dead splash, bypassing the onboarding permission screen entirely. On upgrades, users stare at a frozen splash for the entire multi-year re-scan.

**Fix:** Run `runApp` first; trigger the rescan from `MainShell`'s init (it already drives `syncFromSms()` with progress UI). Gate on onboarding: `if (needsRescan && onboardingComplete) …` so first-run flows through onboarding, and persist the version stamps after the rescan *completes* (keep the current write-after-await semantics so a killed rescan retries).

## ISSUE-8: Raw exceptions shown to users

**Evidence:** `finance_store.dart:287` — `_error = 'Failed to scan SMS: $e'` renders `PlatformException(…)` internals in the UI.
**Fix:** map to a friendly message; log the exception via `debugPrint`/logger.

---

# P2 — Performance, precision, maintenance

## ISSUE-9: ~50 RegExp objects rebuilt per message

**Evidence:** `sms_parser.dart:381` — `final patterns = _buildPatterns();` inside `parseTransaction`, which runs per candidate. A 20k-candidate scan compiles ~1M regexes.
**Fix:** `static final List<_SmsPattern> _patterns = _buildPatterns();` and reference that.

## ISSUE-10: Scan work on the wrong threads

**Evidence:**
- `MainActivity.kt:28–52` — the MethodChannel handler runs `scanInboxBatch` (500-row content-provider read + filtering) synchronously on the Android **main** thread.
- `sms_reader_service.dart:249–255, 275–278` — pass 1 runs `AccountDiscovery.discover` (~30 regexes) over **every** SMS and `registry.learn` over all candidates on the **UI isolate**; only pass-2 parsing is isolated.

**Fix:** native — wrap handler bodies in a background executor (`Executors.newSingleThreadExecutor`) and post results to the main looper. Dart — move discovery + registry learning into the same `compute` call as parsing (return discoveries alongside hits).

## ISSUE-11: Kind-evidence keyed by mask only, not `(bank, mask)` — docs contradict code

**Evidence:** `finance_store.dart:1024–1028` (`_cc/_loan/_savings` maps keyed by mask string) and `:841–847` (`statsByMask`). README + AGENTS.md §4.2 both claim keying by "(bank, masked last-4)". Two accounts at different banks sharing a last-4 merge into one account with pooled totals and a majority-voted bank.
**Fix:** key evidence and stats by `'$bank|$mask'` (fall back to mask-only lookup when the bank is unknown), or update the docs if mask-only is intentional. Prefer fixing the code — the docs describe the safer design. Bump `transactionSchemaVersion`.

## ISSUE-12: Bank-per-mask registry forgets everything between scans

**Evidence:** `sms_reader_service.dart:275–278` — a fresh `AccountBankRegistry()` is built per scan from that scan's candidates only. After the first full scan, incremental syncs run relay corrections (ICICI→SBI settlements, LenDenClub) with an almost-empty registry.
**Fix:** persist registry votes (small table `mask_bank_votes(last4, bank, votes)`) or rebuild the registry from stored transactions + discoveries at scan start.

## ISSUE-13: Categorizer substring misfires & personal hardcoding

**Evidence:**
- Substrings without word boundaries (`merchant_categorizer.dart:5–104`): `'ola'` ⊂ "Cola" → Travel; `'jio'` ⊂ "Jiomart" → Bills; `'food'`, `'metro'` similar.
- Personal life circumstances hardcoded (`transaction_enrichment.dart:352–364`): `'nach-10-hdfc'` / `'hdfc bank limited'` → **"HDFC Home Loan EMI"**, `'tp ach icici'` → **"ICICI Personal Loan EMI"**. Any HDFC NACH (mutual-fund SIP, insurance premium) becomes a home-loan EMI; also `'nach '` / `'hdfc bank limited'` are EMI-category keywords (`merchant_categorizer.dart:74–89`). This violates AGENTS.md §8's "keep classification generic" in spirit.
- Inconsistent CCBP categorization: card-bill **credits** → `transfer` (`merchant_categorizer.dart:195–197`) but a BBPS card-bill **debit** hits the `'bbps'` **bills** keyword first (rules loop `:216–223` runs before `_looksLikeTransfer` `:225`).

**Fix:** (a) match keywords with `RegExp('\\b$kw\\b')` (precompiled); (b) derive loan labels from discovered loan accounts / `_loanLabel` instead of NACH-string→product-name guesses — label unknown NACH debits "NACH debit" and category `bills` unless loan evidence exists; (c) check `_looksLikeTransfer` before the keyword rules for debits, or remove `'bbps'` from bills. Bump `transactionSchemaVersion`.

## ISSUE-14: Amount regex drops single-decimal paise

**Evidence:** `sms_parser.dart:11` — `(?:\.\d{2})?` only; "Rs 500.5" parses as 500.
**Fix:** `(?:\.\d{1,2})?`.

## ISSUE-15: Privacy copy overpromises; DB unprotected

**Evidence:** `privacy_settings_screen.dart:174` — "We read bank alerts only. Personal messages are ignored." In fact every SMS body is read, shipped over the channel (`MainActivity.kt:113`, `allRows`), and scanned by discovery regexes — necessarily so. The sqflite DB is plaintext; there is no app lock.
**Fix:** reword to "All messages are processed on-device; only bank alerts are stored." Add a biometric app-lock (`local_auth`) and/or SQLCipher (`sqflite_sqlcipher`) — table stakes for a finance app.

## ISSUE-16: Process gaps

**Evidence:** No CI (admitted, AGENTS.md §6); highest-value suites skip silently without the private `~/Downloads/my_sms.txt` dump; the Kotlin production filter has zero tests; filter logic is duplicated across Kotlin and Dart and has already drifted (see ISSUE-2).
**Fix:** GitHub Action running `flutter analyze` + `flutter test` on push; commit a small **synthetic** SMS corpus (fixtures modeled on real templates, no personal data) so coverage-critical suites always run; after ISSUE-2, the Kotlin filter shrinks enough that a shared fixture file asserted from Dart covers the whole gate.

---

## Suggested execution order for Cursor

1. **ISSUE-1** (merge upsert) — isolated, high value, easy test.
2. **ISSUE-2 + ISSUE-3** together (single-source-of-truth gate in the isolate + sender-order fix) — bump schema version.
3. **ISSUE-4** (KPI exclusions + cross-source dedupe) — bump schema version; largest analytics change, do behind thorough tests (`home_consistency_test.dart` will need intentional updates).
4. **ISSUE-7** (non-blocking rescan), **ISSUE-8** (error copy).
5. **ISSUE-5**, **ISSUE-6** (real budgets, real/removed notifications).
6. P2 batch: ISSUE-9/10 (perf), ISSUE-11/12 (keying + registry persistence, schema bump), ISSUE-13/14 (categorizer precision, schema bump), ISSUE-15 (privacy copy + app lock), ISSUE-16 (CI + fixtures).

## Verdict

Architecture, classification design, and engineering-hygiene ideas are well above typical personal-project quality. But four load-bearing defects currently undermine the app's core promise of trustworthy numbers: the tested filter isn't the shipped filter (ISSUE-2/3), analytics double-count internal movement (ISSUE-4), incremental sync destroys discovered accounts (ISSUE-1), and budgets/notifications are decorative (ISSUE-5/6). None require architectural change — the P0 list is plumbing, not redesign.
