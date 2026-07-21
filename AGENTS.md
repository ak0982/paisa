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
- **Guiding goal:** **"record and classify every transaction."** When a design choice is
  ambiguous, the philosophy is to *track everything* (see the LenDen/self-transfer history in
  §5) rather than silently exclude money movements.
- **Status:** **private / personal project**, AI-built. Repo is private
  (`github.com/ak0982/paisa`). No SMS content, account masks, or personal data is committed.
- **No backend.** Everything (SMS scan, parse, classify, storage) runs locally on the device.
  Storage is on-device SQLite via `sqflite`.

---

## 2. How to work in this repo (for AI agents)

### Git root
- Local git root: `/Users/amarkumar/Downloads/app/Mobile Application/Paisa/paisa_app`
- Branch `main`, remote `origin` = `https://github.com/ak0982/paisa` (**PRIVATE**).

### Commands
```bash
flutter pub get                 # install dependencies
flutter test                    # run the full test suite (~353 tests)
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
| `lib/main.dart` | App bootstrap, provider wiring, **schema-version gate** (`transactionSchemaVersion` / `categorizerVersion`) that triggers a full re-scan. |
| `lib/screens/` | UI screens: `dashboard_screen.dart` (Home), `transactions_screen.dart`, `insights_screen.dart`, `reports_screen.dart`, `profile_screen.dart`, `budgets_screen.dart`, drill-downs (`category_transactions_screen.dart`, `filtered_transactions_screen.dart`), onboarding (`screens/onboarding/`), settings (`screens/settings/`), `main_shell.dart` (bottom-nav shell). |
| `lib/widgets/` | Reusable UI: `transaction_row.dart`, `grouped_transaction_list.dart`, `transaction_sort_control.dart`, `paisa_bottom_nav.dart`, chips/buttons/progress bars. |
| `lib/providers/finance_store.dart` | The core store: holds transactions + discoveries, derives analytics, and does **account classification** (`bankAccounts()` + `_AccountKindEvidence`). |
| `lib/providers/app_settings.dart` | Preferences (profile, notification/privacy toggles). |
| `lib/services/sms/` | The SMS ingestion pipeline (see §4). |
| `lib/models/` | `transaction.dart`, `bank_account.dart`, `budget.dart`, `category_info.dart`, `range_report.dart`, `transaction_sort.dart`. |
| `lib/data/` | `transaction_database.dart` (sqflite), `sms_scan_state.dart` (checkpointing), `mock_data.dart`. |
| `lib/utils/formatters.dart` | Currency + date/time formatting helpers. |
| `lib/theme/` | Colors + theme. |
| `android/.../SmsNativeFilter.kt` | Native (Kotlin) side of the SMS platform channel. |
| `tool/` | Standalone diagnostic scripts (audits, simulations) run against the SMS dump. |
| `test/` | ~353 tests (see §7). |

### End-to-end SMS data flow
```
Android SMS inbox (platform channel: com.paisa.paisa_app/sms)
  → SmsReaderService            native batch fetch + inbox count
  → SmsScanPipeline             staged filters (cheap → expensive):
        1. financial sender?     (O(1) string contains)
        2. financial body hint?  (lightweight keywords)
        3. OTP-only?             (reject)
        4. promo / offer / scam? (reject)
        5. transaction signal?   (debited/credited/UPI/…)
        6. full regex parse      (SmsParser.parseTransaction)
  → TransactionEnrichment       resolve mask, account KIND, display bank/mask,
                                 CCBP bill-payment / NACH-EMI handling, merchant text
  → AccountDiscovery            regexes that identify savings/credit-card/loan accounts
  → AccountBankRegistry         learns bank-per-mask; corrects misleading senders
  → FinanceStore                stores txns + discoveries; classifies accounts (voting);
                                 derives Home/Insights/Reports analytics
  → UI                          screens render via provider
```
Scanning is **two-pass** and uses a **background isolate** (`sms_parse_isolate.dart`): pass 1
collects candidates, learns bank ownership, runs discovery; pass 2 parses in the isolate so the
UI stays responsive on large inboxes, with checkpointing (`sms_scan_state.dart`) for resume.

### `transactionSchemaVersion` (critical)
`lib/main.dart` defines `const transactionSchemaVersion` (currently **14**) and
`const categorizerVersion` (currently **4**). On launch, if either stored value is lower than the
code constant, `store.fullRescanFromSms()` runs — a full **wipe-and-rebuild** of all
transactions from the inbox.

**Whenever you change parsing, enrichment, discovery, or classification logic, BUMP
`transactionSchemaVersion`** (add a changelog comment like the existing ones). Otherwise existing
installs keep stale data and your change appears to "do nothing." This was the literal root cause
of a real bug (Home showing ₹0 — see §5).

---

## 4. Key subsystems & how they work

### 4.1 SMS parsing pipeline (`lib/services/sms/`)
- `sms_reader_service.dart` — talks to the native side over the `com.paisa.paisa_app/sms`
  platform channel; batch-fetches messages and inbox counts.
- `sms_scan_pipeline.dart` — `SmsScanPipeline.process()` runs the staged gate above and returns
  a `SmsPipelineOutcome` (`notFinancialSender`, `notFinancialBody`, `otpOnly`, `promo`,
  `noTransactionSignal`, `parseFailed`, `parsed`). Cheap checks first, full regex last.
- `bank_promo_filters.dart` — marketing/scam rejection ("pre-approved", "apply now",
  "SmartEMI", obfuscated "L0AN"/"Appr0ve", fake wallet credits). A completed-transaction signal
  overrides the promo filter so real alerts with offer-ish wording still parse.
- `sms_parser.dart` — the heavy regex extraction: amount, debit/credit direction, merchant/payee,
  bank, masked account. Also OTP/personal-sender detection and NACH/settlement special cases.
- `sms_keyword_lists.dart` — UPI handle allowlist, wallet providers + display names, card
  schemes, available-balance phrases, and light normalization helpers. Ideas were adapted from
  open-source Indian SMS parsers (see §5) but this is a Paisa-native copy.
- `transaction_enrichment.dart` — resolves the account **kind**, the correct display bank/mask
  for credit-card rows (incl. **CCBP bill payments**) and loan rows (NACH/EMI), and improves
  merchant text.
- `merchant_categorizer.dart` — maps merchant text → spend category.
- `sms_parse_isolate.dart` — background-isolate entry point for pass-2 parsing.

### 4.2 Account discovery + balanced per-mask classification
`account_discovery.dart` regexes fire only on a handful of narrow SMS shapes, so **account kind
is ultimately decided by balanced per-mask voting** in `finance_store.dart`
(`_AccountKindEvidence`). Each account is keyed by **(bank, masked last-4)**:

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
  `_isFundingSideBillPayment` (an outgoing debit labelled "credit card bill payment") counts as
  **savings** evidence for the funding mask, while the card-ness of the payment is attributed to
  the card itself.

**Why this design exists:** an earlier naive rule was *"any credit-card evidence wins"*, which
**over-flipped real savings accounts to credit cards** whenever they paid a card bill or received
a card-related SMS. Balanced voting fixed that regression while still detecting genuine cards.
`bankAccounts()` then groups every transaction by mask, routes it to the mask's winning kind, and
emits one `BankAccount` per `(kind, bank, mask)` with sensible thresholds.

`account_bank_registry.dart` (`AccountBankRegistry`) learns which bank owns each last-4 from
unambiguous SMS and corrects **misleading senders** — e.g. ICICI relaying a credit into an
SBI/HDFC beneficiary account, or LenDenClub settlement alerts.

### 4.3 Supported banks / issuers / neobanks / wallets (from code)
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

### 4.4 Sorting & date formatting
- `lib/models/transaction_sort.dart` — `TransactionSort { dateDesc, dateAsc, amountDesc,
  amountAsc }`; default is **`dateDesc` (newest first)**. `sortTransactions()` and
  `buildTransactionSections()` are shared by every list; date sorts group by day with headers,
  amount sorts produce a flat list. `dayGroupLabel()` renders headers like `TODAY · 12 JUL 2025`
  (**year always included**).
- `lib/utils/formatters.dart` — `formatInr`, `formatAmount` (signed), `formatTxnDate`
  (`d MMM yyyy`, **year included**), `formatTxnTime` (`HH:mm`).

---

## 5. What has been tried — history of changes (read before re-implementing)

> **Accuracy note on git history:** the remote currently has only **two commits** — `Initial
> commit: Paisa personal finance app` and `Add comprehensive README: architecture, supported
> banks, implementation details`. The granular work below was **squashed into the initial
> commit**, so it is **not** recoverable as separate commits via `git log`. The most reliable
> in-repo record of the iteration history is the **schema-version changelog in `main.dart`**
> (bumps **10 → 14**, `categorizerVersion` at 4), plus code comments and the test suites. The
> log below is reconstructed from those artifacts and the handoff notes; treat it as directional
> history, not commit-by-commit truth.

- **Credit-card transaction detection.** Added credit-card recognition (e.g.
  `looksLikeCreditCardTransaction` / enrichment card display) and corrected the
  top-of-transactions data — some **non-transaction SMS were wrongly counted** and are now
  filtered out. *Outcome: cleaner transaction list; cards recognized.*
- **Explored open-source SMS parsers for ideas.** Reviewed
  `github.com/MabudAlam/transaction_sms_parser` and
  `github.com/saurabhgupta050890/transaction-sms-parser`. **Selectively adapted parsing ideas**
  (VPA/merchant extraction, wallet recognition, card schemes, balance-suffix stripping — see the
  header of `sms_keyword_lists.dart`) but **did NOT take a hard dependency**; Paisa keeps its own
  parser/promo/enrichment pipeline. *Outcome: better extraction, no external coupling.*
- **Reports / Insights drill-downs.** Made "Spending by category", "Where money went", "Where
  money came from" and "Top merchants" **clickable** to open the filtered transactions, and the
  report **date-range filters** (This month / Last month / Last 3 months / This year / Last year
  / All time / custom) apply to the drill-downs. *Outcome: reports are explorable.*
- **Home screen: last-month → CURRENT month + today.** Changed Home to show the **current
  calendar month + today** instead of last month. **Debugged "spend showing ₹0"** — two root
  causes: (a) that month only had wallet-transfer debits, and (b) **stale data** because the
  schema version already matched so **no re-scan ran**. Fixed by **including all transactions**
  (removed LenDen / UPI-self-transfer exclusions per the "track everything" philosophy) **and
  bumping the schema version**. Home totals + lists were **unified behind a single predicate**
  (`countsTowardCashflowSummary`) so the hero number can never disagree with the listed rows.
- **LenDenClub wallet funding.** Originally treated as transfers and **excluded** from
  spend/income. Per "track every transaction", the **exclusions were removed** so these are
  recorded. *Outcome: all money movement counts.*
- **SMS scan window: → ALL messages.** Expanded from a ~24-month window to scanning the
  **entire** inbox (multi-year, 3–4+ years). UI copy updated to say full-history scanning.
  Corresponds to the `main.dart` bump **10 → 11**.
- **Profile "Your bank accounts" filter chips.** Added **All / Savings / Credit card / Loan**
  chips to the detected-accounts list.
- **Account classification — multiple iterations** (mirrored by `main.dart` bumps 12→13→14):
  1. **CC/loan under-detection** fixed by aggregating **transaction-level kinds** per mask, not
     just narrow discovery regexes (bump **11 → 12**).
  2. **Savings over-flipped to credit card** fixed by introducing **balanced voting** instead of
     "any CC evidence wins" (bump **12 → 13**).
  3. **Savings COVERAGE gaps** (missing accounts) fixed (bump **13 → 14**): added **Federal Bank
     (incl. Fi / Jupiter)** to the real-bank allowlist, recognized **balance / interest /
     informational** savings SMS ("in/on/to your A/c XX1234", "A/c 1234 credited/debited
     with …"), and **broadened mask extraction** for long / 4-digit masks — surfacing PNB + two
     Federal accounts that were previously absent.
- **Transaction list sorting.** Date/amount, asc/desc, added across Transactions, Insights, and
  Reports drill-downs via the shared `transaction_sort_control.dart`; default **newest-first**.
- **Full day/month/YEAR dates everywhere** via the shared formatters/`dayGroupLabel`.
- **App launcher icon.** Replaced the default Flutter icon with a Paisa rupee icon via
  `flutter_launcher_icons` (Android adaptive icon, **emerald `#0E9E6E` background**,
  `assets/icon/app_icon.png`).
- **Published to private GitHub repo `ak0982/paisa`** and added a comprehensive `README.md`.

---

## 6. Known issues / limitations / things to work on

- **Android-only SMS features.** iOS does not allow inbox access, so account/transaction
  discovery is unavailable there. The Flutter app builds for other platforms but the core
  feature only works on Android.
- **Heuristic / regex-based classification.** Parsing, enrichment, and account-kind voting are
  heuristic and **can still misclassify edge cases** (unusual SMS wording, new templates,
  ambiguous senders).
- **Uneven bank coverage.** Majors (HDFC/SBI/ICICI/Axis/Kotak/IDFC) have rich patterns; some
  banks are **thin** — e.g. **Canara** and **Bank of Baroda** are mostly sender-detection only.
- **Account discovery depends on masks.** If a bank's SMS never includes a masked last-4 (or
  uses an unrecognized masking style), the account may not surface.
- **Testing uses static SMS dumps.** Classification is validated against a dump at
  `~/Downloads/my_sms.txt` (and `~/Downloads/my_sms_live.txt`) that is **NOT in the repo**, so
  **real-device variance** can differ from test results. There is also a git-ignored
  `my_sms_live.txt` at repo root used locally — **never commit it**.
- **No CI configured.** Tests must be run locally (`flutter test`).
- **In-code TODO-ish markers.** No literal `TODO/FIXME` tags exist in `lib/`; the only matches
  are `XX`/`XXXX` mask literals inside regex comments (`sms_parser.dart`, `account_discovery.dart`).
  Grep before assuming: `rg -n "TODO|FIXME|HACK" lib/`.

---

## 7. Testing notes

- **~353 tests** (`flutter test`): counted as 317 `test(...)` + 36 `testWidgets(...)` across
  `test/`.
- **Key suites:**
  - `account_kind_classification_test.dart` — the balanced per-mask voting classification.
  - `savings_coverage_diagnostic_test.dart` — savings-account coverage against the SMS dump.
  - `transaction_sort_test.dart` — sorting/grouping behavior.
  - Others: `sms_parser_test.dart`, `sms_scan_pipeline_test.dart`, `account_discovery_test.dart`,
    `account_bank_registry_test.dart`, `transaction_enrichment_test.dart`,
    `merchant_categorizer_test.dart`, `home_consistency_test.dart`, `insights_window_test.dart`,
    `reports_category_drilldown_test.dart`, plus `audit_*` / `*_scenarios` suites and
    `widget_test.dart`. See `test/TEST_SCENARIOS.md`.
- **Validation against the SMS dump:** several tests and `tool/` scripts read
  `${HOME}/Downloads/my_sms.txt` (and `my_sms_live.txt`). These files **live outside the repo,
  are git-ignored, and must NEVER be committed.** Suites that need the dump **skip gracefully**
  when it is absent, so `flutter test` still passes on a clean checkout.

---

## 8. Conventions & gotchas for future AI work

1. **Always bump `transactionSchemaVersion`** (in `lib/main.dart`, with a changelog comment)
   when you change parsing, enrichment, discovery, or classification — otherwise existing
   installs keep **stale data** and your change looks like a no-op.
2. **Keep classification generic. NO hardcoded user masks / account numbers.** Key on
   `(bank, masked last-4)` and reuse existing signals. (The balanced-voting design is generic by
   construction — keep it that way.)
3. **Never commit SMS data or secrets.** `.gitignore` already excludes `my_sms.txt`,
   `my_sms_live.txt`, `*_sms_live.txt`, `sms_analysis_report.txt`, and Android signing files
   (`*.jks`, `*.keystore`, `key.properties`, `local.properties`). Do not add real SMS content,
   real account masks, or personal data to code, tests, or docs — use synthetic fixtures.
4. **Respect the device-storage constraint** (see §2): never uninstall / clear data / touch
   device storage; `adb install -r` is fine; escalate storage issues to the user.
5. **Prefer the shared helpers** (`transaction_sort.dart`, `formatters.dart`) so every screen
   stays consistent; don't re-implement sorting or date formatting locally.
6. **When adding bank/wallet support**, extend the keyword/handle lists and discovery regexes,
   add a test case, and validate against the dump with `flutter test` + relevant `tool/` scripts.
