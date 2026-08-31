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
**with zero manual entry** for bank SMS — plus an optional **manual mint** for
cash / off-SMS moves (`source: manual`, bank Cash; never creates a You account).

- **Domain:** Indian banks and payment providers (HDFC, SBI, ICICI, Axis, Kotak, IDFC, PNB,
  Federal + its neobanks Fi/Jupiter, Yes Bank, IndusInd, BOB, HSBC, plus major wallets/UPI apps).
- **Guiding goal:** **"record and classify every transaction."** Lists still show every money
  movement (including transfers). **Cashflow KPIs** (spend / income / savings rate) intentionally
  **exclude internal movement** (self-transfers, CCBP legs) — see ISSUE-4 in §5.2. Tracking in
  lists ≠ inflating the headline numbers. Manual mints are first-class rows sorted by chosen date.
- **Manual mint exception:** Moves FAB + Day Strip empty-day CTA → Date / Amount / Type → auto
  message → Save. Ids are `manual_<hex>` with `smsId: null`. Full SMS rescan **preserves**
  `source IN (manual, paste)`; logout / Clear local data still wipe them.
- **Status:** **private / personal project**, AI-built. Repo is private
  (`github.com/ak0982/paisa`). No SMS content, account masks, or personal data is committed.
- **No backend.** Everything (SMS scan, parse, classify, storage) runs locally on the device.
  Storage is on-device SQLite via `sqflite` (**plaintext** — biometric lock / SQLCipher are
  deliberately deferred; see ISSUE-15 in §6). OS-level export paths are shut off: cloud backup
  and device-to-device transfer are disabled in the manifest (SEC-1, §5.4).

---

## 2. How to work in this repo (for AI agents)

### Git root
- Local git root: `/Users/amarkumar/Downloads/app/Mobile Application/Paisa/paisa_app`
- Branch `main`, remote `origin` = `https://github.com/ak0982/paisa` (**PRIVATE**).

### Commands
```bash
flutter pub get                 # install dependencies
flutter test                    # full suite (~500 focused tests + ~3000 account-matrix cases)
flutter test test/foo_test.dart # run a single suite
flutter analyze                 # static analysis / lints (flutter_lints)
flutter run                     # run on a connected Android device / emulator
flutter build apk --release     # release APK
dart run flutter_launcher_icons # regenerate launcher icons from assets/icon/app_icon.png
```
Some diagnostic scripts under `tool/` are standalone Dart programs run with `dart run tool/<name>.dart`; most read the SMS dump from `~/Downloads/my_sms.txt` (see §6/§7).

### Device / development constraints (IMPORTANT — respect these)
The user develops against **physical Android devices**. When operating on them:
- **NEVER uninstall the app, clear app data/caches, run `pm trim-caches`, or delete/move files
  on the device.** Do not manipulate device storage in any way.
- `adb install -r` of the app's own APK **is fine** (reinstall/replace is allowed).
- If a device **storage / space** issue occurs (e.g. `INSTALL_FAILED_INSUFFICIENT_STORAGE`),
  **STOP and tell the user** so they can free space themselves. Do not free space automatically.
- Last known devices (optional context, do not hardcode into product logic): Redmi
  `4453302c`, Samsung SM_G781B `RZCT40Z5TSN`.

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
| `lib/main.dart` | App bootstrap, provider wiring, **schema-version gate** (`transactionSchemaVersion` **35** / `categorizerVersion` **5**). `store.init()` + launch scan run **after first frame** (ISSUE-7, fully done). |
| `lib/screens/` | Bottom-nav tabs: HOME (`dashboard_screen.dart` + **Day Strip teaser**), MOVES (`transactions_screen.dart`), BUDGET (`budgets_screen.dart`), STATS (`insights_screen.dart` **ledger coin** + `reports_screen.dart`), YOU (`profile_screen.dart`). Day browse: `day_strip_screen.dart` (**Paisa Coin** circular day/range ledger). Drill-downs: `category_transactions_screen.dart`, `filtered_transactions_screen.dart` (incl. You-account lists). Onboarding + settings (privacy / help only — no notification toggles). `main_shell.dart` uses **lazy keep-alive** tabs. |
| `lib/widgets/` | `transaction_row.dart`, `grouped_transaction_list.dart`, `transaction_sort_control.dart`, `paisa_bottom_nav.dart`, `category_spend_chip.dart` (Home chips + Stats/Reports sticker grid / rim arc / TOP·mid·LOW badges), `paisa_coin.dart` (shared struck-disc chrome for Day Strip + Stats), `day_strip_teaser.dart` (Home DAY entry), `pulse_calendar_sheet.dart` (**Pulse Calendar** day/range picker), `sms_coin_slab.dart` (**Coin Flip / Mint Slab** transaction detail — see §4.10), buttons/progress bars, `bank_logo.dart`. |
| `lib/providers/finance_store.dart` | Core store: txns + discoveries, analytics, `bankAccounts()` / `_ledgerAccountBuckets()` (**memoized**), `_AccountKindEvidence` keyed by `bank\|mask`, You rematch + loan association, user budget limits, launch-scan, **throttled** `scanProgressListenable`. |
| `lib/providers/app_settings.dart` | Preferences (profile, merchant-masking, hidden accounts). **No notification toggles** (removed ISSUE-6). |
| `lib/services/sms/` | SMS pipeline (see §4) plus `product_payment_linker.dart` (You drilldown product↔funding links, O(n) `ProductPairingIndex`) and `original_sms_lookup.dart` (Coin Flip on-demand body statuses). |
| `lib/models/` | `transaction.dart`, `bank_account.dart`, `budget.dart`, `category_info.dart`, `range_report.dart`, `transaction_sort.dart`. |
| `lib/data/` | `transaction_database.dart` (sqflite; `mergeDiscoveredAccounts`, `category_budgets` table), `sms_scan_state.dart` (checkpointing), `mock_data.dart`. |
| `lib/utils/formatters.dart` | INR (`decimalDigits: 2`, no whole-rupee roundoff), `formatSharePercent` (tiny Stats shares), date/time. |
| `lib/theme/` | Colors + theme. |
| `android/.../SmsNativeFilter.kt` | Native coarse thinner only (sender / length / OTP) — **not** the promo/scam gate. |
| `android/.../MainActivity.kt` | Platform channels (`/sms` + `/security`); SMS batch reads run on a **background executor** (ISSUE-10); sets **`FLAG_SECURE`** in `onCreate` (SEC-2). |
| `android/app/src/main/res/xml/` | `data_extraction_rules.xml` (API 31+ cloud + D2D) and `backup_rules.xml` (API ≤30) — both exclude **every** domain (SEC-1). |
| `lib/services/screen_security.dart` | Applies the screenshot/recents protection preference to the Android window (SEC-2). |
| `.github/workflows/flutter_ci.yml` | CI: `flutter analyze` + `flutter test` on push/PR to `main` (ISSUE-16). |
| `test/fixtures/synthetic_sms_corpus.txt` | Synthetic SMS fixtures (no personal data) so gate coverage runs without the private dump. |
| `docs/india_bank_sms_research.md` | RBI bank inventory, SMS taxonomy, public template notes, and parser expansion roadmap (research only). |
| `tool/` | Standalone diagnostic scripts (audits, simulations) run against the SMS dump. **SMS analysis loop:** `import_sms_dump.dart` → `reparse_sms_analysis.dart` → `report_sms_gaps.dart` writes `~/Downloads/paisa_sms_analysis.db` + redacted `paisa_sms_gap_report.md` (both gitignored). |
| `test/` | ~500 focused tests + ~3000-case account matrix (see §7). |
| `code_review_by_fable_claude.md` | Fable/Claude round-1 review that drove ISSUES 1–16 (historical evidence + proposed fixes). |
| `code_review_round2_by_fable_claude.md` | Fable/Claude round-2 review (R2-1…R2-10). P0/P1 items are fixed in code; P2 nits documented in §5.3. |
| `code_review_round3_security_by_fable_claude.md` | Fable/Claude round-3 **security** review (SEC-1…SEC-7). Verdicts + what shipped in §5.4. |

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

- `const transactionSchemaVersion = **35**`
- `const categorizerVersion = **5**`

On launch, if either stored value is lower than the code constant **and** onboarding is complete,
`FinanceStore` schedules `fullRescanFromSms()` **after the first frame** (with progress UI) —
not before `runApp`. **`store.init()` is also deferred** (`prepareForDeferredInit()` +
`addPostFrameCallback`); it must not block the splash (ISSUE-7, fully done). Fresh installs
flow through onboarding's own scan. Version stamps are written only after the rescan completes
so a killed rescan retries.

**Perf-only changes (lazy tabs, memoized `bankAccounts` / `_ledgerAccountBuckets`, O(n)
pairing index, throttled scan-progress listenable) must NOT bump the schema.** They do not
change stored parse/classify results.

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
| 22 → 23 | **HSBC India:** sender/body mapping (`HSBCIN` / `HSBC*`), savings + debit-card + CC parse/discovery, `_realBanks` + logo. |
| 23 → 24 | **Evidence from offline SMS analysis DB** (fresh dump → `~/Downloads/paisa_sms_analysis.db`): live HSBC `creditcard … used at … for INR` signal+parse; ICICI USD spends + CC refunds; Axis cashback; bill/EMI due reminders demoted from txn noise. |
| 24 → 25 | **Slice Small Finance Bank** (SLCEIT / SLCBNK): UPI send/receive, IMPS, AutoPay, CC spend; failed-refunded UPI ignored; discovery + logo. |
| 25 → 26 | You **account drilldown**: canonicalize bank aliases (BOB→Bank of Baroda); keep CCBP on the **funding** account (no remap to card); attach unambiguous same-bank maskless orphans. |
| 26 → 27 | Account-owning bank vs SMS sender: registry learns Slice, does not learn from ICICI settlements; seeds votes from discoveries + pre-rescan ownership; You buckets **rematch** `Bank`/wrong-bank same last-4 into the unique real owner. |
| 27 → 28 | **Loan product association**: discover loan masks before linked savings; NACH/EMI remaps onto loan mask only when known (never issuer bank + funding mask); opening a loan lists associated EMI debits. |
| 28 → 29 | **Multi-loan EMI**: never remap ambiguous MBK/generic EMI via funding bank; NACH mandate bank requires a **unique** loan at that bank; **Kotak NACH** accepts `debited from\|to`. |
| 29 → 30 | **Product↔funding payment links** for You drilldown (amount+time pairing; **UPI dest last-4** → unique loan). If a product-side SMS already covers the same amount in-window, the funding debit stays on savings only — **no double-count**. |
| 30 → 31 | **R2 review:** NACH kind/remap only from the beneficiary clause (not the funding bank); loan-linker word boundaries; same-last4 ownership fold skips card/loan donors; incremental discovery merge does not re-add counters. |
| 31 → 32 | SBI UPI/CCBP amounts accept thousands commas; PNB loan-deposit SMS accepts optional `of`. |
| 32 → 33 | Live-inbox parse gaps: HDFC Spent Rs On/From Bank Card (CC vs debit-card BBPS), ICICI cashback + "your" CC refunds, SBI CC reversal/cashback + e-mandate + UPI/IMPS/CBS credits, Kotak CC spend, PNB bank charges, IDFC savings interest + CC thank-you payment, ICICI CMS `Account XX credited:Rs.`. Debit-card `BLOCK DC` discoveries stay savings. |
| 33 → 34 | Leftover live inbox: ICICI CC refund **successfully transferred** onto savings last-4 (4-digit only; 3-digit `XX505` CMS left unparsed); HDFC `spent via Debit Card` / `BLOCK DC` / `CCBBPSNO` store as **savings**, not creditCard. |
| 34 → 35 | Same-source debit-card / CCBP / BBPS **alert twins** collapse (keep `Spent … Bal … BLOCK DC`; drop `ALERT: spent via Debit Card`). SmartPay `Bill Paid:` stays unparsed. |

`categorizerVersion` is **5** (R2-1: brand keywords beat generic SBI-style `trf to`, while
BBPS/CCBP stay Transfer ahead of bills). ISSUE-13's categorizer precision rode the schema bump
19 → 20 rather than a separate categorizer bump.

---

## 4. Key subsystems & how they work

### 4.1 SMS parsing pipeline (`lib/services/sms/`)
- `sms_reader_service.dart` — talks to the native side over the `com.paisa.paisa_app/sms`
  platform channel; batch-fetches messages and inbox counts; seeds `AccountBankRegistry` from
  stored transaction votes before a scan (ISSUE-12). Also serves single-message
  reads (`getSmsById` / `loadOriginalSms`) for the transaction detail (§4.10).
- `original_sms_lookup.dart` — on-demand original-SMS result type + empty-state
  copy for the coin reverse (§4.10). No bodies are persisted.
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
  merchant text. No personal NACH→product-name hardcoding (ISSUE-13). Multi-loan: never guess
  the product from the **funding bank**; UPI/NEFT dest last-4 remaps only when that mask is a
  **unique** discovered loan; Kotak NACH parse accepts `debited from|to`.
- `product_payment_linker.dart` — You-section **product↔funding** links without rewriting
  identity via the funding bank. Amount (±0.015) + 48h window; if a product ack already covers
  the funding debit, **do not** also list the funding row on the loan/card (one economic EMI →
  one drilldown row). Ambiguous same amount/time across two products → link neither. Lookups
  go through O(n) `ProductPairingIndex`.
- `merchant_categorizer.dart` — maps merchant text → spend category. Short keywords use **word
  boundaries**; BBPS/CCBP debits classify as **transfer** before bills keywords (ISSUE-13);
  brand keywords beat generic `trf to` so SBI "trf to SWIGGY" stays food (R2-1).
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
(upsert new keys; **do not re-add** `sms_hits`/totals on conflict — the 1h overlap would inflate
counters, R2-6). Full rescan uses `clearSmsDerivedData()` (SMS rows + discoveries only) so
**manual / paste mints survive**; logout / `clearAll` still wipe everything. Do **not**
reintroduce delete-all-then-insert on the incremental path (ISSUE-1).

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
  Canara (sender detection), Bank of Baroda (sender detection), **HSBC** (savings + CC), **Slice** SFB (savings UPI/IMPS + CC).
- **Credit-card issuers:** SBI, ICICI, Axis, HDFC, Kotak, IDFC (FIRST), Yes Bank, IndusInd, BOB
  (BOBCARD), **HSBC**. Card schemes detected in text: Visa, Mastercard, RuPay, Amex, Maestro, Diners.
- **Neobanks:** Fi (`FEDFIB`) and Jupiter (`MYJPTR`) — both ride on **Federal Bank** savings
  accounts and resolve to `Federal`.
- **Wallets / UPI providers:** Paytm, PhonePe, Google Pay (GPay), Amazon Pay, MobiKwik,
  Freecharge, Airtel Money, Ola Money, Jio Money, PayZapp (plus generic UPI/NEFT/IMPS/RTGS/BHIM
  rails, and a large UPI-handle allowlist in `sms_keyword_lists.dart`).
- **Lending / other:** LenDenClub (P2P).

### 4.6 Sorting, INR, and share percents
- `lib/models/transaction_sort.dart` — `TransactionSort { dateDesc, dateAsc, amountDesc,
  amountAsc }`; default is **`dateDesc` (newest first)**. `sortTransactions()` and
  `buildTransactionSections()` are shared by every list; date sorts group by day with headers,
  amount sorts produce a flat list. `dayGroupLabel()` renders headers like `TODAY · 12 JUL 2025`
  (**year always included**).
- `lib/utils/formatters.dart` — `NumberFormat.currency(locale: 'en_IN', symbol: '₹',
  **decimalDigits: 2**)` so `formatInr` / `formatAmount` always show paise (₹0.85 stays 0.85,
  not a whole-rupee roundoff). `formatTxnDate` (`d MMM yyyy`), `formatTxnTime` (`HH:mm`).
  `formatSharePercent` formats 0–1 shares for Stats/Reports badges: `32%` / `0.4%` / `0.03%` /
  `<0.01%`.

### 4.7 You-section accounts (drilldown, rematch, loans)
YOU (`profile_screen.dart`) lists `bankAccounts()` with All / Savings / Credit card / Loan
filters. Tapping an account opens `FilteredTransactionsScreen` via
`FinanceStore.transactionsForAccount` (same bucket as the You totals).

`_ledgerAccountBuckets()` (memoized; see §4.9):
- Exact `bank|mask` assignment; banks **canonicalized** (e.g. BOB → Bank of Baroda).
- **Ownership rematch:** `Bank` / wrong-bank / maskless rows with a last-4 that has a **unique**
  real owner are absorbed into that owner (Slice•0856 absorbing ICICI-relay credits).
- **CCBP** stays on the **funding savings** account (not remapped onto the card).
- **Loans:** EMI/NACH on a funding mask is attributed to the loan only when there is exactly
  one discovered loan, or ingest already remapped via body last-4 / unique NACH beneficiary /
  UPI dest last-4. **Never guess via funding bank** when multiple loans exist (schema 29).
- `ProductPaymentLinker` then attaches orphan funding payments to the unique product, skipping
  any amount already covered by a product-side SMS (schema 30, no double-count).

### 4.8 Home chips + Stats/Reports stickers
- **Home** category chips (`CategorySpendChip`, no share/badge) are **tappable** →
  `CategoryTransactionsScreen` for the **current month**.
- **STATS** (`insights_screen.dart`) and **Reports** (`reports_screen.dart`) use
  `CategorySpendStickerGrid`: same Home-style stickers in a 2-col wrap, **rim arc** = share of
  perimeter, **TOP · N%** / mid `N%` / **LOW · N%** badges via `formatSharePercent` (tiny
  shares must not vanish as `0%`). Highest-share tile is emphasized. Tiles drill into the
  category list (Insights window or report range).

### 4.8a Day Strip (Paisa Coin) + Pulse Calendar + Stats ledger coin
UI-only day/range browsing and struck-coin chrome. **No schema bump.**

- **Home DAY teaser** (`day_strip_teaser.dart`) sits under the month hero: selected/today
  OUT · IN plus optional intensity ticks. Tap opens `DayStripScreen`; calendar icon opens
  **Pulse Calendar**.
- **Day Strip** (`day_strip_screen.dart`) — single day or inclusive range minted as a
  circular **Paisa Coin** ledger (`paisa_coin.dart`): milled rim, OUT/IN gauge ring, recessed
  OUT amount, embossed day numeral + PAISA wordmark. Rows below are stamped with miniature
  coin tokens (share of day); internal moves get a dashed token + MOVE badge and stay out of
  OUT/IN KPIs (same cashflow rules as Home). Filter overflow + sort; row tap → Coin Flip
  (§4.10).
- **Pulse Calendar** (`pulse_calendar_sheet.dart`) — Neo-Vault month grid with spend-intensity
  fills (`FinanceStore` day OUT helpers). Modes: **day** (Day Strip / teaser) and **range**.
  **Reports → Custom** uses this sheet (not the Material date-range picker) and opens the
  picked range on Day Strip / report flow accordingly.
- **Stats ledger coin** (`insights_screen.dart`) — whole insights window struck as one coin
  via the same `paisa_coin.dart` chrome (`PaisaCoinFace` / tokens / wordmark `STATS`). Peak-day
  legend opens Day Strip for that day.

Shared chrome lives in `paisa_coin.dart` so Day Strip and Stats stay visually consistent.
Tests: `day_strip_test.dart`, `day_strip_widget_test.dart`, `insights_coin_widget_test.dart`,
`reports_custom_range_test.dart` (Custom → Pulse Calendar).

### 4.9 Performance (no schema bump)
These keep large inboxes responsive. **Do not bump `transactionSchemaVersion` for them.**
- **Lazy keep-alive tabs** (`_LazyKeepAliveTabs` in `main_shell.dart`): each of HOME / MOVES /
  BUDGET / STATS / YOU is built on first visit and kept offstage (`Offstage` + `TickerMode`).
  Index-only `setState` must not rebuild other tabs.
- **Memoized** `bankAccounts()` and `_ledgerAccountBuckets()`; invalidate on txn/discovery/
  hidden-mask changes (`_invalidateLedgerCache`).
- **O(n) `ProductPairingIndex`** (bank|mask|cents) instead of nested `all.any` scans for
  product↔funding pairing. Tested for parity with the scan path.
- **Non-blocking `init()`** after first frame (`prepareForDeferredInit` + post-frame
  `store.init()` then `runLaunchScan()`). ISSUE-7 is complete — do not re-await init/rescan
  before `runApp`.
- **Throttled scan progress** (`scanProgressListenable`, 200ms, force on done): progress UI
  must not rebuild You/Moves/Stats data.

### 4.10 Transaction detail: Coin Flip / Mint Slab (`sms_coin_slab.dart`)

Tapping a transaction anywhere (Paisa Coin day list, MOVES, Reports, You /
category drilldowns, Home recents) opens `showTransactionCoinSlab` — a struck
coin that **flips** inside a mint slab instead of a Material field sheet.

- **Face:** `PaisaCoinFace` with the gauge struck fully OUT (white) or IN (lime),
  `formatInr` amount, merchant (respects `AppSettings.maskMerchantNames`),
  `bank · mask`, and the flow label on the rim. Internal movement (`isMove`)
  leaves the gauge idle and stamps a MOVE chip.
- **Reverse:** the mint slab — milled rim, hard shadow, `ORIGINAL SMS` legend,
  sender stamp, and the **full unredacted SMS body** in a recessed scrollable
  field with Copy. Merchant masking is display-only and never redacts the body;
  the SMS is the source of truth.

**SMS bodies are still not persisted.** The body is fetched on demand from the
inbox by `Transaction.smsId` via `SmsReaderService.loadOriginalSms` →
`getSmsById` on the `com.paisa.paisa_app/sms` channel →
`MainActivity.getSmsById` (queries `Telephony.Sms._ID`, background executor).
A session-only 32-entry memory cache avoids re-reading the provider; nothing
goes to the database. Every failure mode is an explicit `OriginalSmsStatus`
(`noSmsId` / `notFound` / `noPermission` / `unsupportedPlatform` / `emptyBody` /
`lookupFailed`) with struck empty-state copy in `original_sms_lookup.dart` —
never a raw platform error, never a blank field and never a reading bar that
does not stop:

- A `loaded` row whose body is blank must render through
  `OriginalSmsLookup.displayStatus`, which reports it as `emptyBody`. Reading
  copy off `status` directly gives the customer an empty title *and* an empty
  body.
- Anything thrown on the way to the inbox (channel error, unexpected payload
  type) resolves to `lookupFailed` — both `loadOriginalSms` and the widget's
  `_load` swallow throws, because an unresolved future leaves the reverse stuck
  on `READING THE INBOX` forever.
- The `RECEIVED …` stamp is suppressed for a zero/absent date column so a bank
  alert is never labelled `RECEIVED 1 JAN 1970`.

Dragging horizontally across the disc flips it, **except** over the SMS body
itself, where the selection gesture wins — customers highlight reference
numbers there, so the message must not flip away mid-drag.

`TransactionCoinSlab` takes an injectable `OriginalSmsLoader` so widget tests
cover every state without a device: `test/sms_coin_slab_test.dart` (core) and
`test/sms_coin_slab_corners_test.dart` (money/paise matrix, verbatim body,
Unicode, every miss status, flip mechanics, list journeys, service contract).

This is **UI + a new native read** only — no parse/classify change, so it does
**not** bump `transactionSchemaVersion`.

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
| **ISSUE-7** | `11912ba` | Schema-bump rescan blocked `runApp` / broke onboarding permission UX. **Fully done:** `init()` + rescan run after first frame (`prepareForDeferredInit`); gated on `onboardingComplete`; progress is a throttled listenable. Do not treat splash-block as an open issue. |
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

### 5.3 Fable round 2 (R2-1…R2-10) — Aug 2026

Source: `code_review_round2_by_fable_claude.md` (on `main`). Do **not** re-introduce these.

| ID | Verdict | Notes |
| --- | --- | --- |
| **R2-1** | Fixed | Brand keywords before generic `trf to`; CCBP/BBPS still Transfer first. `categorizerVersion` **5**. |
| **R2-2** | Fixed | Bare NACH is not loan-kind; remap only when the bank token is in the **beneficiary** clause and that bank has a unique loan. |
| **R2-3** | Fixed | Linker uses word-bound `emi`/`nach`/`loan`; LIC Premium / Chemist / Panache are not EMI. |
| **R2-4** | Fixed | Same-last4 fold **skips card/loan donors**. Strong-bank *savings* relays (Slice+ICICI) still fold — that is the intended rematch. |
| **R2-5** | Fixed | Pass-1 discovery is chunked per SMS batch; learn isolate gets candidates + prior discoveries, not the whole inbox. |
| **R2-6** | Fixed | Incremental `mergeDiscoveredAccounts` does **not** re-add `sms_hits`/totals on conflict. |
| **R2-7** | Intentional | 48h pairing window and ±₹0.015 stay tight to avoid false EMI covers. `transactionCount` counts **listed** rows (incl. internal legs); KPIs exclude them (ISSUE-4). |
| **R2-8** | Intentional | Drop any `has failed` UPI alert (refunded **or** retry). Tightening to `refunded` only would ingest failed-retry SMS as spend. Tautology removed; behavior kept. |
| **R2-9** | Mixed | Trailing-3-month budget seed: **fixed**. User-edit floor ₹100 vs suggestion floor ₹1,000: **intentional**. `formatCompactInr` is an alias of `formatInr` after paise unification. Hidden-mask drilldown mismatch is cosmetic (You list already hides those accounts). |
| **R2-10** | Fixed | Order-sensitive R2-1 tests exist (`merchant_categorizer_test` + matrix). Schema bumps still land when parse/classify changes; batch when possible. |

### 5.4 Fable round 3 — security (SEC-1…SEC-8) — Aug 2026

Source: `code_review_round3_security_by_fable_claude.md`. Every finding was reproduced against
the code before being fixed; the ones that were **not** real (or were already deliberate) are
recorded here so nobody "fixes" them for optics. Regression cover:
`test/security_hardening_test.dart` + `test/sms_parser_redos_test.dart`. **No schema bump** — none
of this changes how a real SMS parses or classifies.

| ID | Verdict | Notes |
| --- | --- | --- |
| **SEC-1** | **Fixed** | Reproduced in the merged release manifest: no `allowBackup`, so Auto Backup swept the plaintext DB + prefs to Google Drive. Now `allowBackup="false"` **plus** `dataExtractionRules` / `fullBackupContent` — `allowBackup=false` alone does **not** stop device-to-device transfer on Android 12+. Do not drop either XML file. |
| **SEC-2** | **Fixed** | No `FLAG_SECURE` anywhere. `MainActivity.onCreate` now sets it **before** `super.onCreate` (protects the recents thumbnail from launch), and the `/security` channel (`setSecureScreen`) lets Dart relax it. `AppSettings.blockScreenshots` **defaults to on**; Privacy → "Block screenshots" turns it off for people who want screenshots. Secure-by-default is the invariant — do not flip the default. |
| **SEC-3** | Intentional | Restatement of ISSUE-15 (plaintext `sqflite`, no app lock). Still deliberately deferred — see §6. SEC-1 removes the backup-extraction path that made it worse. |
| **SEC-4** | **Fixed** | Real: `debugPrint`/`debugPrintStack` are not compiled out of release, so scan exceptions reached logcat. Now behind `kDebugMode`. A test scans `lib/` and fails on any ungated `print`/`debugPrint`. |
| **SEC-5** | Not a vuln | `getSmsById` verified in-process: registered on the engine's binary messenger, no exported `<service>`/`<provider>`/`<receiver>`, `_ID` passed as a `?` selection arg. SEC-2 covers the on-screen exposure. (Residual, accepted: the reverse's Copy button puts the body on the clipboard.) |
| **SEC-6** | Not a vuln | `minifyEnabled false` confirmed, but there are no secrets/keys/network in the app, so R8 buys no confidentiality — only size. Left off deliberately: shrinking the SMS channel + sqflite paths needs on-device QA that a lint-clean build cannot replace. Revisit with the SEC-3 work. |
| **SEC-7** | Intentional | `allRows` really does cross the channel, by design (ISSUE-2): native is a coarse thinner and Dart re-gates. Keeping the promo/scam gate in one place beats trimming the payload. Do not move filtering back into Kotlin. |
| **SEC-8** | **Fixed** (missed by the review) | The review's §3 cleared the parser of ReDoS after testing only `(?:\w+\s+)+bank card`, which really is linear. It missed the patterns pairing two `.*`/`.+` runs. Re-measured on a pre-fix checkout, full pipeline, with bodies that hit the prefix but never the tail: `payment of…received towards your` ×n = 0.6 s at 8 kB and **33 s at 34 kB**; `credited with rs…against reversa` ×n = 5.7 s at 30 kB and **93 s at 122 kB**; `cashback of…credited to you` ×n = 24 s at 118 kB. Worse than quadratic, and a concatenated multipart SMS reaches that size, so one message sent to the user stalls a whole scan. Fixed with `SmsParser.maxScanBodyLength` (2,000 chars — longest real message in the dump is 1,696) applied in `parseTransaction` / `isRealTransactionSms` / `isPromoOrOfferSms` **and** at the reader boundary, since discovery and enrichment regex the same rows. Post-fix all three are flat at tens of ms at any size. **The display path must stay uncapped** — the Coin Flip reverse shows the verbatim body. |

Also checked this round and clean, so don't re-audit them from scratch: the **sqflite** layer has
zero string interpolation — every `where:` uses `whereArgs`, the one `rawInsert` uses `?`
placeholders, and the `execute` calls are static DDL; there is **no in-app export/share path**
(no `share_plus`, no file writes outside the DB) so the DB only leaves via the OS paths SEC-1
closed; and the only exported component is the launcher activity with a MAIN/LAUNCHER filter —
no deep links, no `url_launcher`, no custom scheme. `INTERNET` stays debug/profile-only.

---

## 6. Known issues / limitations / remaining work

**Fixed — do not re-open as bugs:**
- Whole-rupee INR roundoff — `formatInr` uses `decimalDigits: 2` (see §4.6).
- Blocking splash on DB hydrate / schema rescan — ISSUE-7 is fully done (see §3 / §4.9).

**Still true:**
- **ISSUE-15 / SEC-3 deferred — no biometric app lock, DB still plaintext `sqflite`.** Privacy
  *copy* is honest; at-rest encryption (`sqflite_sqlcipher`) and `local_auth` lock were
  **intentionally not shipped**. Do not pretend they exist. Revisit when productizing. Round 3
  did close the platform-level export paths around it (SEC-1 backup, SEC-2 screen capture).
- **Release APK is unminified (SEC-6).** Deliberate: no secrets to hide, and R8 over the SMS
  channel / sqflite needs device QA. Not an open vulnerability.
- **Android-only SMS features.** iOS does not allow inbox access. The Flutter app builds for
  other platforms but the core feature only works on Android.
- **No live SMS receiver.** Data refreshes when the app opens / user rescans. `RECEIVE_SMS` was
  removed (ISSUE-6); real-time capture would need a full implement path, not a placebo toggle.
- **Heuristic / regex-based classification.** Parsing, enrichment, and account-kind voting can
  still misclassify edge cases (unusual SMS wording, new templates, ambiguous senders).
  Multi-loan users: ambiguous MBK/generic EMI stays on the **funding** account by design.
- **Uneven bank coverage.** Majors have rich patterns; **Canara** and **Bank of Baroda** are
  mostly sender-detection only (BOB cards via BOBCARD). Research inventory + expansion roadmap:
  `docs/india_bank_sms_research.md`.
- **Account discovery depends on masks.** Unrecognized masking styles may hide accounts.
- **Testing uses a private SMS dump** at `~/Downloads/my_sms.txt` (and `my_sms_live.txt`) that
  is **NOT in the repo**. Dump-dependent suites **skip when absent**. Synthetic fixtures
  (`test/fixtures/synthetic_sms_corpus.txt`) keep gate coverage always-on.
- **In-code TODO-ish markers.** Few/no literal `TODO/FIXME` in `lib/`. Grep before assuming:
  `rg -n "TODO|FIXME|HACK" lib/`.

---

## 7. Testing / CI

- **`flutter test`:** ~500 focused `test` / `testWidgets` plus
  `account_integration_matrix_test.dart` (~3000 generated cases, suite asserts 2700–3300).
  `test/TEST_SCENARIOS.md` is a **historical** July 2026 catalog (~223) — do not treat its
  totals as current.
- **CI:** `.github/workflows/flutter_ci.yml` runs `flutter analyze` + `flutter test` on push and
  PR to `main`. Dump-dependent suites skip on CI; synthetic fixtures keep critical gates green.
- **Key suites:**
  - `account_integration_matrix_test.dart` — large You-account matrix (kinds, rematch, CCBP,
    loans, parity of totals vs drilldown).
  - `loan_account_association_test.dart`, `account_ownership_test.dart`,
    `account_transactions_test.dart` — loan association, rematch, drilldown lists.
  - `product_payment_linker_test.dart` — product↔funding links, no double-count, index parity.
  - `ledger_bucket_cache_test.dart` — memoized `bankAccounts` / `_ledgerAccountBuckets`.
  - `formatters_test.dart` — `decimalDigits: 2` INR + `formatSharePercent`.
  - `launch_scan_test.dart` — ISSUE-7 non-blocking init / rescan.
  - `account_kind_classification_test.dart` — balanced `bank|mask` voting.
  - `savings_coverage_diagnostic_test.dart` — savings coverage against the SMS dump (skips if absent).
  - `budget_limits_test.dart` — fixed editable budgets (ISSUE-5).
  - `home_consistency_test.dart` — Home KPIs vs listed rows / exclusions.
  - `sms_scan_pipeline_test.dart` / synthetic corpus — production gate coverage.
  - `same_source_alert_twins_test.dart` — schema 35 Spent vs ALERT debit-card twin collapse.
  - `day_strip_test.dart` / `day_strip_widget_test.dart` — Day Strip OUT/IN vs Home KPIs;
    Paisa Coin UI + Pulse Calendar entry (§4.8a).
  - `insights_coin_widget_test.dart` — Stats ledger coin totals / chrome.
  - `reports_custom_range_test.dart` — Reports Custom opens Pulse Calendar.
  - `sms_coin_slab_test.dart` — Coin Flip / Mint Slab detail: face summary, flip
    reveals the body, loading / deleted-SMS / no-permission / no-`smsId` states,
    copy, and masking that never redacts the SMS (§4.10).
  - `sms_coin_slab_corners_test.dart` — money/paise matrix, verbatim body, Unicode,
    every `OriginalSmsStatus`, flip mechanics, list journeys, `getSmsById` contract.
  - `security_hardening_test.dart` — SEC-1 manifest/backup rules, SEC-2 `FLAG_SECURE` +
    screenshot toggle, SEC-4 no ungated logging in `lib/` (§5.4).
  - `sms_parser_redos_test.dart` — SEC-8 scan-body cap: adversarial bodies stay bounded,
    real alerts still parse, cap keeps headroom over the live corpus.
  - Plus parser / discovery / registry / enrichment / categorizer / insights / reports /
    `audit_*` / `*_scenarios` / `widget_test.dart`.
- **Never commit SMS dumps, `paisa_sms_analysis.db`, real account masks, `.env`, secrets, or
  APKs.** Suites that need the dump skip gracefully.

---

## 8. Conventions & gotchas for future AI work

1. **Always bump `transactionSchemaVersion`** (in `lib/main.dart`, with a changelog comment)
   when you change parsing, enrichment, discovery, or classification — otherwise existing
   installs keep **stale data** and your change looks like a no-op. **Do not bump** for
   UI/perf-only work (lazy tabs, caches, pairing index, progress throttle).
2. **Keep classification generic. NO hardcoded user masks / account numbers.** Key on
   `(bank, masked last-4)` / `bank|mask` and reuse existing signals. Do not hardcode personal
   NACH merchant strings to product names (ISSUE-13). Multi-loan: never guess product from
   funding bank.
3. **Never commit SMS data or secrets.** `.gitignore` already excludes `my_sms.txt`,
   `my_sms_live.txt`, `*_sms_live.txt`, `sms_analysis_report.txt`, `paisa_sms_analysis.db`,
   `paisa_sms_gap_report.md`, and Android signing files (`*.jks`, `*.keystore`,
   `key.properties`, `local.properties`). No `.env`, APKs, or dumps. Use synthetic fixtures only.
4. **Respect the device-storage constraint** (see §2): never uninstall / clear data / touch
   device storage; `adb install -r` is fine; escalate storage issues to the user.
5. **Prefer the shared helpers** (`transaction_sort.dart`, `formatters.dart`) so every screen
   stays consistent; don't re-implement sorting, INR, or date formatting locally. Keep
   `decimalDigits: 2`.
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
   - Do not block `runApp` on DB `init()` or a full SMS rescan; keep the ISSUE-7 launch-scan
     pattern (`prepareForDeferredInit` + post-frame work).
   - Keep KPIs on `countsTowardSpend` / `countsTowardIncome` (+ transfer pairing); lists may
     still show internal movement.
   - Seed `AccountBankRegistry` from stored data; don't start incremental scans empty.
   - You drilldown must use `transactionsForAccount` / the same ledger buckets as
     `bankAccounts()`; product↔funding links must not double-count covered EMIs.
8. **Do not undo the round-3 security invariants** (§5.4): `allowBackup="false"` + both backup
   rule files stay; `FLAG_SECURE` stays set in `onCreate` and `blockScreenshots` stays
   default-on; release builds stay silent (`kDebugMode`-gated logging); regex stages stay behind
   `SmsParser.capScanBody` while the Coin Flip reverse keeps the **uncapped** body.
