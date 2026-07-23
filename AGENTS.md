# AGENTS.md — AI project context & handoff for Paisa

> This file is the **AI-focused companion** to `README.md`. The README documents the app for
> humans; this document exists so that **any AI coding agent can understand the project
> end-to-end quickly** — what it does, how it is built, what has been tried, what worked, what
> did not, known issues, and what still needs work. It was written by exploring the actual
> codebase and git history, so prefer it over assumptions. When in doubt, read the code.
>
> **Everything in this project was built by AI.** Treat the code as the source of truth and keep
> this document honest and up to date as you change things.

---

## 1. Project overview

**Paisa** is a **Flutter** personal-finance app for **Android** that turns the phone's **SMS
inbox** into a complete, automatic picture of the user's money. It reads bank / UPI alert SMS
**on-device**, parses them into transactions, discovers bank accounts / credit cards / loans,
classifies each account, and surfaces spend/income summaries, budgets, insights and reports —
**with zero manual entry**.

- **Domain:** Indian banks and payment providers (HDFC, SBI, ICICI, Axis, Kotak, IDFC, PNB,
  Federal + its neobanks Fi/Jupiter, Yes Bank, IndusInd, BOB, plus major wallets/UPI apps).
- **Guiding goal:** **"record and classify every transaction."** Lists still show every money
  movement (including transfers). **Cashflow KPIs** (spend / income / savings rate) intentionally
  **exclude internal movement** (self-transfers, CCBP legs) — see ISSUE-4 in §5.2. Tracking in
  lists ≠ inflating the headline numbers.
- **Status:** **private / personal project**, AI-built. Repo is private
  (`github.com/ak0982/paisa`). No SMS content, account masks, or personal data is committed.
- **No backend.** Everything (SMS scan, parse, classify, storage) runs locally on the device.
  Storage is on-device SQLite via `sqflite` (**plaintext** — biometric lock / SQLCipher are
  deliberately deferred; see ISSUE-15 in §6).

---

## 2. How to work in this repo (for AI agents)

### Git root
- Local git root: `/Users/amarkumar/Downloads/app/Mobile Application/Paisa/paisa_app`
- Branch `main`, remote `origin` = `https://github.com/ak0982/paisa` (**PRIVATE**).

### Commands
```bash
flutter pub get                 # install dependencies
flutter test                    # run the full test suite (~378 tests)
flutter test test/foo_test.dart # run a single suite
flutter analyze                 # static analysis / lints (flutter_lints)
flutter run                     # run on a connected Android device / emulator
flutter build apk --release     # release APK
dart run flutter_launcher_icons # regenerate launcher icons from assets/icon/app_icon.png
```
Some diagnostic scripts under `tool/` are standalone Dart programs run with `dart run tool/<name>.dart`; most read the SMS dump from `~/Downloads/my_sms.txt` (see §6/§7).

### Device / development constraints (IMPORTANT — respect these)
The user develops against a **physical Android device**. When operating on it:
- **NEVER uninstall the app, clear app data/caches, run `pm trim-caches`, or delete/move files
  on the device.** Do not manipulate device storage in any way.
- `adb install -r` of the app's own APK **is fine** (reinstall/replace is allowed).
- If a device **storage / space** issue occurs (e.g. `INSTALL_FAILED_INSUFFICIENT_STORAGE`),
  **STOP and tell the user** so they can free space themselves. Do not free space automatically.

### Conventions
- State management: `provider` + `ChangeNotifier`. `FinanceStore` holds finance data + derived
  analytics; `AppSettings` holds preferences. UI reads via `Consumer` / `context.watch/read`.
- Shared helpers are used everywhere for consistency: sorting/grouping via
  `lib/models/transaction_sort.dart`, currency/date formatting via `lib/utils/formatters.dart`.
- Keep classification **generic** — key on `(bank, masked last-4)` and reuse the same signals
  the pipeline already computes. **No hardcoded user account numbers / masks.** (See §8.)

---

## 3. Architecture map

### Directory pointers
| Area | What lives there |
| --- | --- |
| `lib/main.dart` | App bootstrap, provider wiring, **schema-version gate** (`transactionSchemaVersion` / `categorizerVersion`) that schedules a full re-scan **after** first frame (ISSUE-7). |
| `lib/screens/` | UI screens: `dashboard_screen.dart` (Home), `transactions_screen.dart`, `insights_screen.dart`, `reports_screen.dart`, `profile_screen.dart`, `budgets_screen.dart`, drill-downs (`category_transactions_screen.dart`, `filtered_transactions_screen.dart`), onboarding (`screens/onboarding/`), settings (`screens/settings/`), `main_shell.dart` (bottom-nav shell). |
| `lib/widgets/` | Reusable UI: `transaction_row.dart`, `grouped_transaction_list.dart`, `transaction_sort_control.dart`, `paisa_bottom_nav.dart`, chips/buttons/progress bars. |
| `lib/providers/finance_store.dart` | The core store: holds transactions + discoveries, derives analytics, account classification (`bankAccounts()` + `_AccountKindEvidence` keyed by `bank\|mask`), user budget limits, launch-scan orchestration. |
| `lib/providers/app_settings.dart` | Preferences (profile, merchant-masking, hidden accounts). **No notification toggles** (removed ISSUE-6). |
| `lib/services/sms/` | The SMS ingestion pipeline (see §4). |
| `lib/models/` | `transaction.dart`, `bank_account.dart`, `budget.dart`, `category_info.dart`, `range_report.dart`, `transaction_sort.dart`. |
| `lib/data/` | `transaction_database.dart` (sqflite; `mergeDiscoveredAccounts`, `category_budgets` table), `sms_scan_state.dart` (checkpointing), `mock_data.dart`. |
| `lib/utils/formatters.dart` | Currency + date/time formatting helpers. |
| `lib/theme/` | Colors + theme. |
| `android/.../SmsNativeFilter.kt` | Native coarse thinner only (sender / length / OTP) — **not** the promo/scam gate. |
| `android/.../MainActivity.kt` | Platform channel; SMS batch reads run on a **background executor** (ISSUE-10). |
| `.github/workflows/flutter_ci.yml` | CI: `flutter analyze` + `flutter test` on push/PR to `main` (ISSUE-16). |
| `test/fixtures/synthetic_sms_corpus.txt` | Synthetic SMS fixtures (no personal data) so gate coverage runs without the private dump. |
| `tool/` | Standalone diagnostic scripts (audits, simulations) run against the SMS dump. |
| `test/` | ~378 tests (see §7). |
| `code_review_by_fable_claude.md` | Fable/Claude code review that drove ISSUES 1–16 (historical evidence + proposed fixes). |

### End-to-end SMS data flow
```
Android SMS inbox (platform channel: com.paisa.paisa_app/sms)
  → SmsReaderService            native batch fetch (background executor) + inbox count
  → SmsScanPipeline             staged filters (cheap → expensive) — runs in production isolate:
        1. financial sender?     (O(1) string contains)
        2. financial body hint?  (lightweight keywords)
        3. OTP-only?             (reject)
        4. promo / offer / scam? (reject)
        5. transaction signal?   (debited/credited/UPI/…)
        6. full regex parse      (SmsParser.parseTransaction)
  → TransactionEnrichment       resolve mask, account KIND, display bank/mask,
                                 CCBP bill-payment / NACH-EMI handling, merchant text
  → AccountDiscovery            regexes that identify savings/credit-card/loan accounts
                                 (runs in the parse isolate, ISSUE-10)
  → AccountBankRegistry         learns bank-per-mask; seeded from stored txns (ISSUE-12);
                                 corrects misleading senders
  → FinanceStore                stores txns + discoveries (merge upsert on incremental sync);
                                 classifies accounts by bank|mask voting; derives analytics
                                 with KPI exclusions + cross-source dedupe
  → UI                          screens render via provider
```
Scanning is **two-pass** and uses a **background isolate** (`sms_parse_isolate.dart`): pass 1
collects candidates, learns bank ownership, runs discovery; pass 2 runs the **full staged Dart
gate** (`SmsScanPipeline.process`) and parses in the isolate so the UI stays responsive on large
inboxes, with checkpointing (`sms_scan_state.dart`) for resume.

> **Single source of truth for filtering (ISSUE-2 fix):** the native Kotlin filter
> (`SmsNativeFilter`) is only a **coarse thinner** (financial-sender / length / OTP) that
> keeps obviously-irrelevant SMS off the platform channel. The authoritative promo / scam /
> personal-sender / transaction-signal gate lives in **Dart** (`SmsScanPipeline` + `SmsParser`)
> and re-runs on **every** candidate inside the parse isolate. Over-returning candidates from
> native is safe — Dart re-gates. Do **not** re-add promo/scam logic to Kotlin; it would drift.
> Do **not** call `SmsParser.parseTransaction` from the isolate without going through
> `SmsScanPipeline.process` first.

### `transactionSchemaVersion` / `categorizerVersion` (critical)

`lib/main.dart` defines:

- `const transactionSchemaVersion = **22**`
- `const categorizerVersion = **4**`

On launch, if either stored value is lower than the code constant **and** onboarding is complete,
`FinanceStore` schedules `fullRescanFromSms()` **after the first frame** (with progress UI) —
not before `runApp` (ISSUE-7). Fresh installs flow through onboarding's own scan. Version stamps
are written only after the rescan completes so a killed rescan retries.

**Whenever you change parsing, enrichment, discovery, or classification logic, BUMP
`transactionSchemaVersion`** (add a changelog comment like the existing ones). Otherwise existing
installs keep stale data and your change appears to "do nothing."

#### Schema changelog (from `lib/main.dart` comments)

| Bump | What changed |
| --- | --- |
| 10 → 11 | Full inbox scan (no 24-month cap). |
| 11 → 12 | Account kind from strongest signal across all txns for a bank+mask. |
| 12 → 13 | Balanced voting per mask (not "any CC evidence wins"). |
| 13 → 14 | Savings coverage: balance/interest SMS, Federal/Fi/Jupiter, PNB long masks. |
| 14 → 15 | **ISSUE-1:** incremental sync uses merge upsert for discovered accounts (no wipe). |
| 15 → 16 | **ISSUE-2:** isolate runs full `SmsScanPipeline`; native demoted to coarse thinner. |
| 16 → 17 | **ISSUE-3:** reject personal 10-digit senders before completed-signal shortcut. |
| 17 → 18 | **ISSUE-4:** KPI exclusions for internal movement + cross-source dedupe at insert. |
| 18 → 19 | **ISSUE-14:** amount regex accepts single decimal digit (`Rs 500.5` → 500.5). |
| 19 → 20 | **ISSUE-13:** categorizer word boundaries; BBPS/CCBP → transfer; no NACH product hardcoding. |
| 20 → 21 | **ISSUE-11:** kind evidence + spend stats keyed by `(bank, mask)`, not mask alone. |
| 21 → 22 | Adversarial QA: bare 10-digit personal senders rejected; self-transfer KPI pairing needs distinct real `bank\|mask` legs; CCBP merchant wording excludes spend even if kind stays savings. |

`categorizerVersion` remains **4** (rebuilds when categorizer rules change enough independently of
schema). ISSUE-13's categorizer precision rode the schema bump 19 → 20 rather than a separate
categorizer bump.

---

## 4. Key subsystems & how they work

### 4.1 SMS parsing pipeline (`lib/services/sms/`)
- `sms_reader_service.dart` — talks to the native side over the `com.paisa.paisa_app/sms`
  platform channel; batch-fetches messages and inbox counts; seeds `AccountBankRegistry` from
  stored transaction votes before a scan (ISSUE-12).
- `sms_scan_pipeline.dart` — `SmsScanPipeline.process()` runs the staged gate above and returns
  a `SmsPipelineOutcome` (`notFinancialSender`, `notFinancialBody`, `otpOnly`, `promo`,
  `noTransactionSignal`, `parseFailed`, `parsed`). Cheap checks first, full regex last.
  **This runs in production** inside the parse isolate — not test-only.
- `bank_promo_filters.dart` — marketing/scam rejection ("pre-approved", "apply now",
  "SmartEMI", obfuscated "L0AN"/"Appr0ve", fake wallet credits). A completed-transaction signal
  overrides the promo filter so real alerts with offer-ish wording still parse — **but** personal
  phone senders are rejected first (ISSUE-3).
- `sms_parser.dart` — the heavy regex extraction: amount, debit/credit direction, merchant/payee,
  bank, masked account. Patterns are compiled **once** as `static final _patterns` (ISSUE-9).
  OTP/personal-sender detection and NACH/settlement special cases live here.
- `sms_keyword_lists.dart` — UPI handle allowlist, wallet providers + display names, card
  schemes, available-balance phrases, and light normalization helpers.
- `transaction_enrichment.dart` — resolves the account **kind**, the correct display bank/mask
  for credit-card rows (incl. **CCBP bill payments**) and loan rows (NACH/EMI), and improves
  merchant text. No personal NACH→product-name hardcoding (ISSUE-13).
- `merchant_categorizer.dart` — maps merchant text → spend category. Short keywords use **word
  boundaries**; BBPS/CCBP debits classify as **transfer** before bills keywords (ISSUE-13).
- `sms_parse_isolate.dart` — background-isolate entry: discovery + registry learning +
  `SmsScanPipeline.process` + parse (ISSUE-2 + ISSUE-10).

### 4.2 Account discovery + balanced `(bank, mask)` classification
`account_discovery.dart` regexes fire only on a handful of narrow SMS shapes, so **account kind
is ultimately decided by balanced voting** in `finance_store.dart` (`_AccountKindEvidence`).
Each account is keyed by **`bank|mask`** (ISSUE-11) — two banks sharing a last-4 do **not** merge:

- **Each transaction** casts **one vote** for its own resolved `AccountKind`.
- **Each SMS discovery** casts **weighted** votes (by `smsHits`).
- The mask is classified by its **dominant** kind:
  - **Credit card** wins only when on-card votes **strictly exceed** savings votes (and are at
    least as strong as loan votes).
  - **Loan** wins only when loan votes **strictly exceed both** savings and credit-card votes
    (so a single NACH/ECS EMI debited from a savings account does **not** flip it to a loan).
  - Ties and savings-dominant masks fall through to **savings**.
- **CCBP funding-side attribution:** a credit-card *bill payment* (CCBP / BBPS / "trf to credit
  card") is a debit **from the funding savings account**, not spend **on** the card.
  `_isFundingSideBillPayment` counts as **savings** evidence for the funding mask, while the
  card-ness of the payment is attributed to the card itself.

**Why this design exists:** an earlier naive rule was *"any credit-card evidence wins"*, which
**over-flipped real savings accounts to credit cards**. Balanced voting fixed that. Keying by
mask alone then incorrectly **pooled** two banks that shared a last-4 — ISSUE-11 fixed the
keying to match what the docs always claimed.

`account_bank_registry.dart` (`AccountBankRegistry`) learns which bank owns each last-4 from
unambiguous SMS and corrects **misleading senders**. It is **seeded from stored transactions** at
scan start (ISSUE-12) so incremental syncs do not start with an empty registry.

**Discovered-account persistence:** incremental sync uses `TransactionDatabase.mergeDiscoveredAccounts`
(upsert / accumulate hits). Destructive replace is reserved for `fullRescanFromSms` /
`clearAll`. Do **not** reintroduce delete-all-then-insert on the incremental path (ISSUE-1).

### 4.3 Cashflow KPIs vs lists (ISSUE-4)
- Lists / Home rows still show **every** transaction (`countsTowardCashflowSummary => true`).
- Headline spend / income / savings rate / category totals use:
  - `countsTowardSpend` — debits that are **not** credit-card bill payments
  - `countsTowardIncome` — credits that are **not** CC "payment received" legs
  - plus **pairing** of transfer-categorised debit↔credit within ~3 minutes (self / A2A)
- **Cross-source dedupe** at insert: bank SMS + wallet SMS for the same UPI payment → one stored
  row (prefer bank-sourced). See `lib/models/transaction.dart` and `finance_store.dart`.

### 4.4 Budgets (ISSUE-5)
Budgets are **user-editable fixed limits** stored in the `category_budgets` table — **not**
`spent × 1.3` recomputed from the current month (that circular formula made overspend
impossible). Limits are seeded once from historical spend suggestion, then owned by the user.
`budgets_screen.dart` supports editing; progress can exceed 100%.

### 4.5 Supported banks / issuers / neobanks / wallets (from code)
- **Banks:** HDFC, SBI, ICICI, Axis, Kotak, IDFC (FIRST), Yes Bank, IndusInd, PNB, Federal,
  Canara (sender detection), Bank of Baroda (sender detection).
- **Credit-card issuers:** SBI, ICICI, Axis, HDFC, Kotak, IDFC (FIRST), Yes Bank, IndusInd, BOB
  (BOBCARD). Card schemes detected in text: Visa, Mastercard, RuPay, Amex, Maestro, Diners.
- **Neobanks:** Fi (`FEDFIB`) and Jupiter (`MYJPTR`) — both ride on **Federal Bank** savings
  accounts and resolve to `Federal`.
- **Wallets / UPI providers:** Paytm, PhonePe, Google Pay (GPay), Amazon Pay, MobiKwik,
  Freecharge, Airtel Money, Ola Money, Jio Money, PayZapp (plus generic UPI/NEFT/IMPS/RTGS/BHIM
  rails, and a large UPI-handle allowlist in `sms_keyword_lists.dart`).
- **Lending / other:** LenDenClub (P2P).

### 4.6 Sorting & date formatting
- `lib/models/transaction_sort.dart` — `TransactionSort { dateDesc, dateAsc, amountDesc,
  amountAsc }`; default is **`dateDesc` (newest first)**. `sortTransactions()` and
  `buildTransactionSections()` are shared by every list; date sorts group by day with headers,
  amount sorts produce a flat list. `dayGroupLabel()` renders headers like `TODAY · 12 JUL 2025`
  (**year always included**).
- `lib/utils/formatters.dart` — `formatInr`, `formatAmount` (signed), `formatTxnDate`
  (`d MMM yyyy`, **year included**), `formatTxnTime` (`HH:mm`).

---

## 5. What has been tried — history of changes (read before re-implementing)

### 5.1 Pre-review history (schema 10→14 era)

> Early work was largely squashed into the initial commit (`e9f7177`). Prefer the schema
> changelog in `main.dart` and the notes below over inventing commit-level detail for that era.

- **Credit-card transaction detection** and filtering of non-transaction SMS.
- **Explored open-source SMS parsers for ideas** (`transaction_sms_parser` repos) — selectively
  adapted ideas into Paisa-native lists; no hard dependency.
- **Reports / Insights drill-downs** with date-range filters.
- **Home: current month + today**; unified behind cashflow predicates; schema bumps for stale data.
- **LenDenClub / self-transfers kept in lists** ("track everything") — later refined so **KPIs**
  exclude internal movement (ISSUE-4) while lists still show them.
- **SMS scan window → entire inbox** (bump 10 → 11).
- **Profile account filter chips** (All / Savings / Credit card / Loan).
- **Account classification iterations** (bumps 12→13→14): transaction-level kinds → balanced
  voting → savings coverage (Federal/Fi/Jupiter, PNB, balance/interest SMS).
- **Shared sorting + full year dates**; Paisa launcher icon; private GitHub + README + this file.

### 5.2 Fable code-review remediation (ISSUES 1–16) — Jul 2026

Source report: `code_review_by_fable_claude.md`. Fixes landed as discrete commits on `main`.
**Do not re-introduce these bugs.**

| ID | Fix (commit) | What changed / what not to undo |
| --- | --- | --- |
| **ISSUE-1** | `585c184` | Incremental sync wiped `discovered_accounts` via delete-all. Now `mergeDiscoveredAccounts` upsert. Full rescan may still clear. Schema **14→15**. |
| **ISSUE-2** | `9a8102b` | Production called `parseTransaction` directly; Dart pipeline was test-only. Isolate now runs `SmsScanPipeline.process`. Native = coarse thinner only. Schema **15→16**. |
| **ISSUE-3** | `b0edc30` | Personal-number scam SMS accepted via completed-signal shortcut. Reject personal senders **before** that shortcut. Schema **16→17**. |
| **ISSUE-4** | `512a488` | KPIs inflated by transfers / CCBP / duplicate bank+wallet SMS. Added `countsTowardSpend`/`Income`, transfer pairing, cross-source dedupe. Lists still show all rows. Schema **17→18**. |
| **ISSUE-5** | `027661e` | Budgets were `spent×1.3` (never exceed-able). Now fixed editable limits in `category_budgets`. |
| **ISSUE-6** | `a61e79a` | Placebo notification toggles + unused `RECEIVE_SMS` **removed** (chose remove over implement). Only `READ_SMS` remains. |
| **ISSUE-7** | `11912ba` | Schema-bump rescan blocked `runApp` / broke onboarding permission UX. Now non-blocking after first frame, gated on `onboardingComplete`. |
| **ISSUE-8** | `99056dc` | Raw `PlatformException` strings in UI → friendly scan-error copy; log details via `debugPrint`. |
| **ISSUE-9** | `7691ce4` | ~50 RegExps rebuilt per message → `static final _patterns` compiled once. |
| **ISSUE-10** | `4402dd2` | Native SMS reads on Android main thread; discovery on UI isolate → background executor + discovery in parse isolate. |
| **ISSUE-11** | `d0c4048` | Kind evidence keyed by mask alone (docs lied). Now `bank\|mask`. Schema **20→21**. |
| **ISSUE-12** | `a52cee0` | Fresh empty `AccountBankRegistry` each scan → seed votes from stored transactions. |
| **ISSUE-13** | `720cac3` | Substring misfires (`ola`⊂Cola); BBPS as bills; NACH→"Home Loan EMI" hardcoding. Word boundaries; BBPS/CCBP→transfer; generic NACH labels. Schema **19→20**. |
| **ISSUE-14** | `983f867` | Amount regex required exactly 2 decimal digits → `(?:\.\d{1,2})?`. Schema **18→19**. |
| **ISSUE-15** | `c22e0ef` | Privacy copy fixed ("All messages are processed on-device; only bank alerts are stored."). **Biometric app lock + SQLCipher deliberately deferred** (see §6). |
| **ISSUE-16** | `95bc04d` | Added `.github/workflows/flutter_ci.yml` + `test/fixtures/synthetic_sms_corpus.txt`. |

Review report commit: `6c0741d`.

---

## 6. Known issues / limitations / remaining work

- **ISSUE-15 deferred — no biometric app lock, DB still plaintext `sqflite`.** Privacy *copy* is
  honest; at-rest encryption (`sqflite_sqlcipher`) and `local_auth` lock were **intentionally not
  shipped**. Do not pretend they exist. Revisit when productizing.
- **Android-only SMS features.** iOS does not allow inbox access. The Flutter app builds for
  other platforms but the core feature only works on Android.
- **No live SMS receiver.** Data refreshes when the app opens / user rescans. `RECEIVE_SMS` was
  removed (ISSUE-6); real-time capture would need a full implement path, not a placebo toggle.
- **Heuristic / regex-based classification.** Parsing, enrichment, and account-kind voting can
  still misclassify edge cases (unusual SMS wording, new templates, ambiguous senders).
- **Uneven bank coverage.** Majors have rich patterns; **Canara** and **Bank of Baroda** are
  mostly sender-detection only.
- **Account discovery depends on masks.** Unrecognized masking styles may hide accounts.
- **Testing uses a private SMS dump** at `~/Downloads/my_sms.txt` (and `my_sms_live.txt`) that
  is **NOT in the repo**. Dump-dependent suites **skip when absent**. Synthetic fixtures
  (`test/fixtures/synthetic_sms_corpus.txt`) keep gate coverage always-on.
- **In-code TODO-ish markers.** Few/no literal `TODO/FIXME` in `lib/`. Grep before assuming:
  `rg -n "TODO|FIXME|HACK" lib/`.

---

## 7. Testing / CI

- **~378 tests** (`flutter test`): counted as ~347 `test(...)` + ~31 `testWidgets(...)` across
  `test/`.
- **CI:** `.github/workflows/flutter_ci.yml` runs `flutter analyze` + `flutter test` on push and
  PR to `main`. Dump-dependent suites skip on CI; synthetic fixtures keep critical gates green.
- **Key suites:**
  - `account_kind_classification_test.dart` — balanced `bank|mask` voting.
  - `savings_coverage_diagnostic_test.dart` — savings coverage against the SMS dump (skips if absent).
  - `budget_limits_test.dart` — fixed editable budgets (ISSUE-5).
  - `home_consistency_test.dart` — Home KPIs vs listed rows / exclusions.
  - `sms_scan_pipeline_test.dart` / synthetic corpus — production gate coverage.
  - `transaction_sort_test.dart`, `sms_parser_test.dart`, `account_discovery_test.dart`,
    `account_bank_registry_test.dart`, `transaction_enrichment_test.dart`,
    `merchant_categorizer_test.dart`, `insights_window_test.dart`,
    `reports_category_drilldown_test.dart`, plus `audit_*` / `*_scenarios` and `widget_test.dart`.
    See `test/TEST_SCENARIOS.md`.
- **Never commit SMS dumps or real account masks.** Suites that need the dump skip gracefully.

---

## 8. Conventions & gotchas for future AI work

1. **Always bump `transactionSchemaVersion`** (in `lib/main.dart`, with a changelog comment)
   when you change parsing, enrichment, discovery, or classification — otherwise existing
   installs keep **stale data** and your change looks like a no-op.
2. **Keep classification generic. NO hardcoded user masks / account numbers.** Key on
   `(bank, masked last-4)` / `bank|mask` and reuse existing signals. Do not hardcode personal
   NACH merchant strings to product names (ISSUE-13).
3. **Never commit SMS data or secrets.** `.gitignore` already excludes `my_sms.txt`,
   `my_sms_live.txt`, `*_sms_live.txt`, `sms_analysis_report.txt`, and Android signing files
   (`*.jks`, `*.keystore`, `key.properties`, `local.properties`). Use synthetic fixtures only.
4. **Respect the device-storage constraint** (see §2): never uninstall / clear data / touch
   device storage; `adb install -r` is fine; escalate storage issues to the user.
5. **Prefer the shared helpers** (`transaction_sort.dart`, `formatters.dart`) so every screen
   stays consistent; don't re-implement sorting or date formatting locally.
6. **When adding bank/wallet support**, extend the keyword/handle lists and discovery regexes,
   add a test case, and validate against the dump with `flutter test` + relevant `tool/` scripts.
7. **Do not reintroduce Fable-review regressions:**
   - Incremental sync must **merge** discovered accounts — never delete-all then insert.
   - Production parse path must go through **`SmsScanPipeline`** in the isolate — never bypass
     to `parseTransaction` alone.
   - Kind evidence / spend stats must stay keyed by **`bank|mask`**, not mask alone.
   - Budgets must stay **user fixed limits** — never `spent × 1.3` circular auto-limits.
   - Do not add placebo notification toggles or unused `RECEIVE_SMS` without a real
     notification + receiver implementation.
   - Do not block `runApp` on a full SMS rescan; keep the ISSUE-7 launch-scan pattern.
   - Keep KPIs on `countsTowardSpend` / `countsTowardIncome` (+ transfer pairing); lists may
     still show internal movement.
   - Seed `AccountBankRegistry` from stored data; don't start incremental scans empty.
