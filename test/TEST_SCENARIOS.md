# Paisa App — Deep Test Scenarios (223 tests)

**Run date:** July 8, 2026  
**Test command:** `flutter test`  
**Result:** ✅ **223 / 223 passed**

---

## Summary

| Area | Scenarios | Passed | Failed | Bugs found |
|------|-----------|--------|--------|------------|
| SMS parsing (valid) | 15 | 15 | 0 | 1 limitation |
| SMS rejection (promo/OTP) | 15 | 15 | 0 | 0 |
| Parser edge cases | 12 | 12 | 0 | 2 limitations |
| Merchant categorization | 10 | 10 | 0 | 0 |
| Analytics & reports | 13 | 13 | 0 | 0 |
| Break attempts | 5 | 5 | 0 | 0 |
| Diverse suite T71–T135 | 65 | 65 | 0 | 0 |
| **Settings & profile U01–U43** | **43** | **43** | **0** | **0** |
| **Local profile setup U44–U53** | **10** | **10** | **0** | **0** |
| Existing suite (parser/pipeline/isolate/widget) | 33 | 33 | 0 | 0 |
| **Total** | **223** | **223** | **0** | **0 fixed** |

---

## Bugs fixed (July 7, 2026)

| ID | Issue | Fix |
|----|-------|-----|
| **BUG-01** | Indian lakh format `Rs.1,25,000` not parsed | Amount regex now supports any comma grouping; `_parseAmount` strips commas |
| **BUG-02** | Unicode `₹` not parsed | Added `₹` to `_currency` pattern (`Rs` / `INR` / `₹`) |
| **BUG-03** | Short `"Hi"` from bank sender passed financial gate | Gate now requires body ≥20 chars AND (body hints OR sender+txn signal) |

---

## Scenario catalog

### S01–S15: Valid bank SMS parsing

| ID | Scenario | Input | Expected | Result |
|----|----------|-------|----------|--------|
| S01 | HDFC UPI Sent Rs | `Sent Rs.486.00 from a/c **4321 to Swiggy` | amount=486, merchant=Swiggy | ✅ PASS |
| S02 | SBI debited Info | `Rs.2,499.00 debited... Info: AMAZON.IN` | amount=2499 | ✅ PASS |
| S03 | ICICI debited for Rs | `Acct XX4321 debited for Rs 8500... EMI credited` | amount=8500 | ✅ PASS |
| S04 | Axis INR debited | `INR 312.00 debited... Info: Ola` | merchant=Ola | ✅ PASS |
| S05 | Kotak towards | `Rs.645 debited... towards Zomato` | merchant=Zomato | ✅ PASS |
| S06 | Paytm paid to | `Rs.299 paid to Jio Recharge via Paytm` | merchant contains Jio | ✅ PASS |
| S07 | Credit to account | `Rs.68000 credited to your a/c **2015` | isCredit=true, amount=68000 | ✅ PASS |
| S08 | Indian lakh format | `Rs.1,25,000.00 debited` | amount=125000 | ✅ PASS |
| S09 | Minimum amount Rs.1 | `Rs.1.00 debited` | amount=1 | ✅ PASS |
| S10 | Spent at format | `Rs.500 spent at AMAZON PAY` | amount=500 | ✅ PASS |
| S11 | PhonePe debit | `Rs.150 paid to Merchant via PhonePe` | amount=150 | ✅ PASS |
| S12 | GPay sender detection | sender=`GPAY-AXIS` | isFinancialSender=true | ✅ PASS |
| S13 | Yes Bank sender | sender=`YESBNK` | isFinancialSender=true | ✅ PASS |
| S14 | PNB generic debit | `Rs.750 has been debited` | amount=750 | ✅ PASS |
| S15 | credited with Rs | `credited with Rs.5000` | isCredit=true | ✅ PASS |

---

### S16–S30: Reject non-transaction SMS

| ID | Scenario | Input | Expected | Result |
|----|----------|-------|----------|--------|
| S16 | Personal chat | sender=FRIEND, lunch message | null | ✅ PASS |
| S17 | OTP-only | `Your OTP for login is 482910` | null | ✅ PASS |
| S18 | HDFC pre-approved loan | `pre-approved Personal Loan... Apply now` | null | ✅ PASS |
| S19 | ICICI loan eligibility | `eligible for instant loan... Click here` | null | ✅ PASS |
| S20 | SBI credit card offer | `Exclusive offer! Credit Card limit` | null | ✅ PASS |
| S21 | HDFC SmartEMI promo | `convert spends to SmartEMI` | null | ✅ PASS |
| S22 | SBI YONO offer | `SBI YONO offer! SimplyCLICK` | null | ✅ PASS |
| S23 | Paytm scratch card | `Scratch card... Refer and earn` | null | ✅ PASS |
| S24 | PhonePe refer & earn | `Refer and earn... Win upto` | null | ✅ PASS |
| S25 | Short SMS + bank sender | sender=HDFCBK, body=`Hi` | gate fails, parse null | ✅ PASS |
| S26 | Empty sender and body | `""` / `""` | gate fails | ✅ PASS |
| S27 | Amazon delivery (not bank) | order delivered notification | null | ✅ PASS |
| S28 | Axis Grab Deals promo filter | bank promo keywords | matchesBankPromo=true | ✅ PASS |
| S29 | Kotak 811 offer | `Kotak 811 offer! Dream Different` | matchesBankPromo=true | ✅ PASS |
| S30 | Pipeline OTP stage | OTP body without txn signal | outcome=otpOnly | ✅ PASS |

---

### S31–S42: Parser edge cases & break attempts

| ID | Scenario | Attack / edge case | Expected | Result |
|----|----------|-------------------|----------|--------|
| S31 | EMI with loan keyword | Real debit labeled Home Loan EMI | parses as debit | ✅ PASS |
| S32 | Promo with amount | Pre-approved Rs.5L, no debit verb | isPromo=true | ✅ PASS |
| S33 | Completed txn overrides promo | `debited` + loan keyword | isPromo=false | ✅ PASS |
| S34 | Newline-heavy body | `\n` between fields | parses correctly | ✅ PASS |
| S35 | Extra whitespace | multiple spaces in body | parses correctly | ✅ PASS |
| S36 | Lowercase sender | `vm-hdfcbk` | isFinancialSender=true | ✅ PASS |
| S37 | Generic VM sender + body hint | debited in body, no bank sender | hasFinancialBodyHint=true | ✅ PASS |
| S38 | Zero amount | `Rs.0.00 debited` | null (invalid) | ✅ PASS |
| S39 | Unicode rupee ₹ | `₹500.00 debited` | amount=500 | ✅ PASS |
| S40 | Multiple amounts in SMS | debit + Avl Bal | picks debit amount (500) | ✅ PASS |
| S41 | Very long merchant name | 40+ char merchant | trimmed to ≤40 chars | ✅ PASS |
| S42 | Credit without account | `received Rs.500 in your account` | isCredit=true | ✅ PASS |

---

### S43–S52: Merchant categorization

| ID | Merchant / body | Expected category | Result |
|----|-----------------|-------------------|--------|
| S43 | Swiggy | food | ✅ PASS |
| S44 | Amazon.in | shopping | ✅ PASS |
| S45 | Jio Recharge | bills | ✅ PASS |
| S46 | Netflix | entertainment | ✅ PASS |
| S47 | HDFC Home Loan EMI | emi | ✅ PASS |
| S48 | salary credited (credit) | income | ✅ PASS |
| S49 | cash withdrawal | atm | ✅ PASS |
| S50 | Random Shop XYZ | other | ✅ PASS |
| S51 | Ola | travel | ✅ PASS |
| S52 | Apollo Pharmacy | health | ✅ PASS |

---

### S53–S65: Analytics & range reports (dummy data)

**Dummy dataset:** 12 transactions across Apr–Jul 2026 (food, shopping, EMI, salary, travel, bills, etc.)

| ID | Scenario | Expected | Result |
|----|----------|----------|--------|
| S53 | July monthly spent | ₹12,447 (excludes credits) | ✅ PASS |
| S54 | July monthly income | ₹68,000 | ✅ PASS |
| S55 | Savings rate July | ~81.7% | ✅ PASS |
| S56 | transactionsInRange July | 6 transactions | ✅ PASS |
| S57 | Empty range (2020) | isEmpty=true, spent=0 | ✅ PASS |
| S58 | Full year 2026 report | 12 transactions | ✅ PASS |
| S59 | Top category July | EMI or food (non-null) | ✅ PASS |
| S60 | Top merchants cap | ≤5 entries | ✅ PASS |
| S61 | Income sources | Salary + Bonus listed | ✅ PASS |
| S62 | Net calculation | net = income − spent | ✅ PASS |
| S63 | Single-day boundary Jul 7 | 2 txns (Ola + Zomato) | ✅ PASS |
| S64 | Bank accounts deduped | unique masks only | ✅ PASS |
| S65 | Auto budgets | generated from spending | ✅ PASS |

---

### S66–S70: Break attempts on store

| ID | Attack | Expected behavior | Result |
|----|--------|-------------------|--------|
| S66 | Empty transaction list | all stats = 0, no crash | ✅ PASS |
| S67 | Inverted date range (end < start) | empty report | ✅ PASS |
| S68 | Duplicate Swiggy merchants | aggregated to ₹300 total | ✅ PASS |
| S69 | earliestTransactionDate | Apr 1, 2026 | ✅ PASS |
| S70 | foodDeltaVsLastMonth no prev data | no exception thrown | ✅ PASS |

---

## Existing test suite (30 tests)

| File | Tests | Coverage |
|------|-------|----------|
| `sms_parser_test.dart` | 20 | Bank parsers, promos, EMI |
| `sms_scan_pipeline_test.dart` | 6 | Staged pipeline |
| `sms_parse_isolate_test.dart` | 3 | Background parsing |
| `widget_test.dart` | 1 | Onboarding launch |

---

## Dummy data used

See `test/helpers/dummy_data.dart` — 12 transactions:

| Month | Transactions |
|-------|-------------|
| Jul 2026 | Swiggy, Amazon, Salary, EMI, Ola, Zomato |
| Jun 2026 | Jio, Netflix |
| May 2026 | Apollo, ATM withdrawal |
| Apr 2026 | Transfer, Bonus credit |

---

## Diverse suite T71–T135 (65 tests)

| Group | IDs | Coverage |
|-------|-----|----------|
| Multi-bank debits | T71–T85 | IDFC, Yes Bank, Canara, IndusInd, BHIM, BoB, Western/lakh amounts, ₹ symbol, decimals |
| Credits & income | T86–T95 | Salary, refund, lakh credit, net-positive reports |
| Promo & rejection | T96–T105 | ICICI Coral, Axis Flipkart, OTP, personal chat, marketing |
| Categorization | T106–T115 | Blinkit, Zepto, MakeMyTrip, BookMyShow, Practo, Nykaa, FASTag, NEFT |
| Reports & analytics | T116–T125 | Monthly, quarterly, savings rate, empty store |
| Isolate & scan state | T126–T135 | Batch parse, incremental/resume scan, masked account, parseFailed |

---

## Settings suite U01–U43 (43 tests)

| Group | IDs | Coverage |
|-------|-----|----------|
| AppSettings prefs | U01–U14 | Defaults, persistence, listeners, restore saved prefs |
| Profile & settings UI | U15–U35 | Navigation, toggles, logout dialog, privacy, help, merchant masking |
| FinanceStore integration | U36–U43 | Bank accounts, monthly stats, empty store, reports, top merchants |

---

## How to re-run

```bash
cd paisa_app

# Full suite (211 tests)
flutter test

# Settings tests only (43 tests)
flutter test test/app_settings_test.dart test/settings_widget_test.dart test/finance_store_settings_test.dart
```
