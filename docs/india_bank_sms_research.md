# India bank SMS research — parser coverage guide for Paisa

> **Purpose:** Evidence-based inventory of RBI-regulated banks that commonly send debit/credit SMS in India, SMS taxonomy, public template shapes, and a gap analysis vs Paisa's current parser. Use this to prioritize expanding `sms_parser.dart` / `account_discovery.dart` / sender hints before Play Store release.
>
> **Research dates:** 2026-07-23 (initial inventory); **2026-09-05** (Play Store expansion pass — thin/missing banks, OSS fixtures, deposit-share priority); **2026-09-05** (Tier-1 + Tier-2 parser implementation in Paisa — schema 36–37).  
> **Scope:** Scheduled commercial banks (PSU + private), small finance banks, payments banks, and a short list of foreign retail banks that issue consumer alerts. Cooperative banks / RRBs noted but not fully inventoried.
>
> **Hard rules for this doc:** No real user SMS, masks, or personal data. All body examples are **synthetic / anonymized** (fictional last-4). Confidence levels reflect public documentation quality, not production validation. PennyWise used **only** for public SMS shapes / sender IDs — Paisa parsers are original Dart (no AGPL Kotlin port).

---

## 1. Executive summary

Indian banks must alert customers on electronic banking transactions (RBI customer-protection framework). Alerts arrive as TRAI DLT-registered SMS with 6-character headers (e.g. `HDFCBK`) often prefixed by operator+circle (`VM-HDFCBK`, `AX-SBIINB`). Message bodies use shared Indian-English phrasing (`Rs`/`INR`, `A/c XX1234`, `debited`/`credited`, `Avl Bal`, `spent on your … Credit Card ending`).

**Paisa today** has deep regex coverage for majors (HDFC, SBI, ICICI, Axis, Kotak, IDFC, Yes, Federal/Fi/Jupiter, HSBC, Slice) plus **Tier-1** (Canara, BOB, Union, BOI, Indian Bank, PNB/IndusInd deepen) and **Tier-2** (Bandhan, IDBI, AU, Equitas, IPPB, South Indian, Central, Karnataka). Still missing/thin: RBL, Ujjivan, UCO, IOB, Maharashtra, P&SB, City Union, Jana, and most other SFBs/PBs.

**Play Store coverage math (approx.):** PSBs still hold ~59% of system deposits; Tier-1+2 close the highest-impact PSU/mid-tier gaps. Remaining volume is long-tail regional / SFB / payments-bank templates needing volunteer fixtures.

**Production still needs volunteer/dump validation** — never treat this doc as a substitute for dump-backed tests.

---

## 2. Regulatory & DLT context

| Topic | What matters for parsers | Sources |
| --- | --- | --- |
| Mandatory e-banking alerts | Banks must register mobile numbers and send SMS alerts for electronic transactions | [RBI Customer Protection](https://www.rbi.org.in/commonman/english/scripts/Notification.aspx?Id=2336) |
| Bank universe | Official lists of SCBs / SFBs / PBs / foreign banks | [RBI – Banks in India](https://www.rbi.org.in/commonman/english/scripts/banksinindia.aspx) |
| DLT headers | 6-char alphabetic header (`HDFCBK`); display form often `XX-HEADER` | [TrueSender DLT prefix guide](https://www.truesenderapp.com/blog/what-are-sms-sender-id-prefixes-in-india-a-complete-guide) |
| Template registration | Variables as `{#var#}`; transactional vs service vs promo | [Infobip India DLT templates](https://www.infobip.com/docs/essentials/asia-registration/dlt-templates) |

**Sender ID shape (parser tip):** Match on the **6-char header substring**, not the full `VM-`/`AX-`/`JD-` prefix.

---

## 3. Paisa current coverage (from code — do not invent)

Ground truth (re-checked 2026-09-05): `lib/services/sms/sms_parser.dart`, `sms_scan_pipeline.dart`, `account_discovery.dart`, `AGENTS.md` §4.5.

| Tier | Entities | Evidence in code |
| --- | --- | --- |
| **Rich parse** | HDFC, SBI, ICICI, Axis, Kotak, IDFC FIRST, Yes (CC), Federal (+ Fi/Jupiter), HSBC, Slice | Dedicated regex families |
| **Tier-1** | Canara, BOB (+ BOBCARD), Union, BOI, Indian Bank, PNB deepen, IndusInd deepen | Schema 36 |
| **Tier-2** | Bandhan, IDBI, AU (+ CC), Equitas, IPPB, South Indian Bank, Central Bank, Karnataka Bank | Schema 37 — public SMS shapes from PennyWise tests/comments; original Dart |
| **Wallets** | Paytm, PhonePe, GPay, Amazon Pay, MobiKwik, Freecharge, Airtel Money, etc. | Cross-source dedupe |
| **Not first-class** | RBL, Ujjivan, UCO, IOB, Maharashtra, P&SB, City Union, Jana, most other SFB/PB | No / thin mapping |

**Trusted hints (Tier-1+2 excerpt):** `CANBNK`, `BOBSMS`/`BOBTXN`/`BOBCRD`, `INDUSB`, `UNIONB`, `BOIIND`, `INDBNK`, `BDNSMS`/`BNDNBK`, `IDBIBK`, `AUBANK`, `EQUTAS`/`EQUITA`, `IPBMSG`/`MYIPPB`, `SIBSMS`, `CENTBK`, `KBLBNK`/`KTKBANK`.

---

## 4. Key headers (DLT inventory excerpt)

From [community DLT gist (2022)](https://gist.github.com/abhishekjnvk/ad596df86a22291ccd76cf29af52b656) + OSS parsers — stale risk Med.

| Bank | Headers | Paisa? | SMS conf. |
| --- | --- | --- | --- |
| SBI | `SBIINB`, `CBSSBI`, `SBICRD`, … | Y-rich | High |
| HDFC | `HDFCBK`, `HDFCBN` | Y-rich | High |
| ICICI | `ICICIB`, `ICICIT`, `ICICIO` | Y-rich | High |
| Axis | `AXISBK` | Y-rich | High |
| Kotak | `KOTAKB` | Y-rich | High |
| PNB | `PNBSMS`, `PNBBNK` | Y-partial | Med–High |
| BOB | `BOBSMS`, `BOBTXN`, `BOBCRD` | Y-sender | Med–High |
| Canara | `CANBNK` | Y-sender | High (OSS) |
| Union | `UNIONB` | N | Med–High |
| BOI | `BOIIND`, `BOIBNK` | N | High |
| Indian Bank | `INDBNK` | N | Med–High |
| IndusInd | `INDUSB` | Y-partial | Med–High |
| Bandhan | `BDNSMS`, `BNDNBK` | Y-Tier2 | Med–High (OSS tests) |
| RBL | `RBLBNK` | N | Low — **no PennyWise parser/fixtures** |
| IDBI | `IDBIBK` | Y-Tier2 | Med (phrase samples in OSS comments) |
| AU SFB | `AUBANK`, `AUBSMS` | Y-Tier2 | Med–High (OSS tests + CC) |
| Equitas | `EQUTAS`, `EQBANK` | Y-Tier2 | Med–High (OSS tests) |
| Ujjivan | `UJJIVN` | N | Low — **no PennyWise parser** |
| IPPB | `MYIPPB`, `IPBMSG` | Y-Tier2 | Med (shapes from OSS + research) |
| Central | `CENTBK` | Y-Tier2 | Med (OSS NEFT fixture) |
| South Indian | `SIBSMS` | Y-Tier2 | High (OSS tests); **SIBSMS before SBI** |
| Karnataka | `KBLBNK`, `KTKBANK` | Y-Tier2 | Med (phrase samples) |
| Maharashtra | `MAHABK` | N | Low |
| UCO | `UCOBNK` | N | Low |

---

## 5. SMS taxonomy (brief)

- **Savings:** debited/credited, UPI/IMPS/NEFT/RTGS, ATM, interest, charges, Avl Bal  
- **CC:** spent on / spent using / BOBCARD / Avl Lmt; payment received ≠ savings income  
- **Loan/EMI:** NACH/ECS; due reminders often non-txn  
- **Noise:** OTP, promo, KYC, balance-only without debit verb  

---

## 6. Per-bank templates (sanitized) — 2026-09-05 expansion

### 6.1 Thin / deepen

#### Canara — High (OSS)
- Compact: `Dear Customer, Acct XXX•••• Dr. INR 260.00 on 06/07/26 to SAMPLE MART; UPI: 123456789012; Bal INR 12,345.67…-CanaraBank`
- Also `Dr. Rs.` / `Dr. ₹`; verbose `has been DEBITED` / RTGS credited with `Total Avail. Bal`
- Sources: [PennyWise CanaraBankParser](https://github.com/sarim2000/pennywiseai-tracker/blob/main/parser-core/src/main/kotlin/com/pennywiseai/parser/core/bank/CanaraBankParser.kt), [PR #621](https://github.com/sarim2000/pennywiseai-tracker/pull/621)

#### Bank of Baroda — Med–High
- `Rs.{amt} Dr. from A/c XX•••• … AvlBal:Rs{bal}`; UPI `Cr. to {vpa}`; IMPS; cash deposit
- BOBCARD: `INR {amt} is spent on your BOBCARD ending •••• at {merchant}`
- Official: [BOB SMS Alert Facility](https://bankofbaroda.bank.in/customer-support/sms-alert-facility)
- Source: [PennyWise BankOfBarodaParser](https://github.com/sarim2000/pennywiseai-tracker/blob/main/parser-core/src/main/kotlin/com/pennywiseai/parser/core/bank/BankOfBarodaParser.kt)

#### PNB — Med–High
- `a/c no XX•••• is debited for Rs {amt}`; `Aval Bal` / IMPS Ref / UPI Ref ID / thru card
- Official: [PNB SMS Banking](https://www.pnb.bank.in/SMS-banking.html)
- Source: [PennyWise PNBBankParser](https://github.com/sarim2000/pennywiseai-tracker/blob/main/parser-core/src/main/kotlin/com/pennywiseai/parser/core/bank/PNBBankParser.kt)

#### IndusInd — Med–High (CC)
- `INR {amt} spent on IndusInd Card XX•••• … at {MERCHANT}. Avl Lmt: INR {limit}`
- Distinguisher: **Avl Lmt** = card; **Avl Bal** = savings
- Official: [IndusAlerts](https://www.indusind.bank.in/in/en/personal/mobile-banking-services/indus-alerts.html)
- Source: [PennyWise #486](https://github.com/sarim2000/pennywiseai-tracker/issues/486)

### 6.2 Missing first-class

#### Union — Med–High
`A/c *•••• Debited for Rs:{amt} on {datetime} by Mob Bk ref no {ref} Avl Bal Rs:{bal}`  
([Union SMS Banking](https://www.unionbankofindia.bank.in/en/details/sms-banking); [UnionBankParser](https://github.com/sarim2000/pennywiseai-tracker/blob/main/parser-core/src/main/kotlin/com/pennywiseai/parser/core/bank/UnionBankParser.kt))

#### Bank of India — High
`Rs.{amt} debited A/cXX•••• and credited to {MERCHANT} via UPI Ref No {ref} … -BOI`  
`BOI - Rs {amt} Credited in your Ac XX•••• … By NEFTINWARD {utr}/{MERCHANT} .Avl Bal {bal}`

#### Indian Bank — Med–High
`debited Rs. {amt}` / `Sent Rs.{amt} … to {merchant}.RRN {n}`; header `INDBNK` ([bank note](https://indianbank.bank.in/en/indian-bank-contact-numbers-a-complete-guide-to-customer-care-services))

#### Bandhan — Med
`INR {amt} deposited to A/c … towards UPI/CR/{ref}/{NAME}/u … Clear Bal is INR {bal} . Bandhan Bank.`  
([Bandhan SMS Banking](https://bandhan.bank.in/personal/mobile-banking/bandhan-bank-sms-banking))

#### RBL — Low–Med
Header `RBLBNK`; CC alerts confirmed in agreement; **spend body samples needed**.

#### IDBI — Med
`IDBI Bank Acct XX•••• debited for Rs {amt}`; `debited with Rs {amt}`

#### AU SFB — Med–High (CC)
`INR 259.90 spent at TELEGRAM PREMIUM on AU Bank Credit Card x•••• … SMS PBLOCK … to 5676767`

#### Equitas — Med–High
`INR {amt} debited via UPI from Equitas A/c 12XX -Ref:{ref} on {dd-mm-yy} to {MERCHANT}. Avl Bal is INR {bal}`

#### Ujjivan — Low
Header `UJJIVN` only publicly.

#### IPPB — Med
Headers `MYIPPB` / `IPBMSG` (verify live); debit UPI / `received a payment … thru IPPB`  
([IPPB SMS Banking](https://ippbonline.bank.in/web/ippb/sms-banking2))

### 6.3 Credit card clusters

| Cluster | Example banks | Paisa |
| --- | --- | --- |
| spent on … Credit Card ending | SBI, Axis, HDFC, Kotak, IDFC, HSBC | Rich |
| IndusInd Card + Avl Lmt | IndusInd | Discovery only |
| BOBCARD | BOB | Partial |
| AU Bank Credit Card | AU | Missing |
| RBL / Bandhan / IDBI CC | — | Samples needed |

---

## 7. Play Store priority tiers

Deposit/customer context (approx Mar 2026, secondary): Canara ~10.7 Cr customers / ₹15.7 L Cr deposits; Union ~16.4 Cr / ₹13.1 L Cr; BOI ~11 Cr / ₹9.3 L Cr; Indian Bank ~9.5 Cr / ₹8.3 L Cr ([Mint](https://www.livemint.com/industry/banking/sbi-leads-in-deposits-and-customer-base-hdfc-bank-tops-average-deposits-per-customer-11786728135484.html)). PSBs ~59% system deposits ([BankPulse](https://bankpulse.ai/dashboards/scb-bank-group/)).

### Tier 1 (ship first)

1. **Canara** — map `CANBNK`; compact `Dr.` + UPI  
2. **Bank of Baroda** — map `BOBSMS`/`BOBCRD`; savings Dr/Cr + keep BOBCARD  
3. **Union** — `UNIONB`; `Debited for Rs:`  
4. **Bank of India** — `BOIIND`; UPI + NEFTINWARD  
5. **Indian Bank** — `INDBNK`; Sent/debited/credited  
6. **PNB deepen** — UPI/IMPS completeness  
7. **IndusInd deepen** — Card + Avl Lmt; savings verbs  

### Tier 2 — **shipped schema 37** (2026-09-05)

8. **Bandhan** — `BDNSMS`; UPI debit/deposit ([BandhanBankParser](https://github.com/sarim2000/pennywiseai-tracker/blob/main/parser-core/src/main/kotlin/com/pennywiseai/parser/core/bank/BandhanBankParser.kt) + `TestBandhanBankParser`) — High  
9. **IDBI** — `IDBIBK`; Acct debited for / credited with (phrase samples in [IDBIBankParser](https://github.com/sarim2000/pennywiseai-tracker/blob/main/parser-core/src/main/kotlin/com/pennywiseai/parser/core/bank/IDBIBankParser.kt)) — Med  
10. **AU SFB** — `AUBANK`; Debited/Dr/Cr + Credit Card ([TestAUBankParser](https://github.com/sarim2000/pennywiseai-tracker/blob/main/parser-core/src/test/kotlin/TestAUBankParser.kt)) — High  
11. **Equitas** — `EQUTAS`; UPI debit/credit ([TestEquitasBankParser](https://github.com/sarim2000/pennywiseai-tracker/blob/main/parser-core/src/test/kotlin/TestEquitasBankParser.kt)) — High  
12. **IPPB** — `IPBMSG`/`MYIPPB`; Debit Rs / received a payment thru IPPB ([IPPBParser](https://github.com/sarim2000/pennywiseai-tracker/blob/main/parser-core/src/main/kotlin/com/pennywiseai/parser/core/bank/IPPBParser.kt) shapes) — Med  
13. **South Indian Bank** — `SIBSMS` (before SBI substring); IMPS/UPI ([TestSouthIndianBankParser](https://github.com/sarim2000/pennywiseai-tracker/blob/main/parser-core/src/test/kotlin/TestSouthIndianBankParser.kt)) — High  
14. **Central Bank** — `CENTBK`; NEFT credited … `-CBoI` ([TestCentralBankOfIndiaParser](https://github.com/sarim2000/pennywiseai-tracker/blob/main/parser-core/src/test/kotlin/TestCentralBankOfIndiaParser.kt)) — Med  
15. **Karnataka Bank** — `KBLBNK`; DEBITED for / credited by (phrase samples in [KarnatakaBankParser](https://github.com/sarim2000/pennywiseai-tracker/blob/main/parser-core/src/main/kotlin/com/pennywiseai/parser/core/bank/KarnatakaBankParser.kt)) — Med  

**Skipped (no clear OSS fixtures):** RBL, Ujjivan.

### Tier 3 (remaining)

UCO, IOB, Maharashtra, P&SB, City Union, Jana, KVB, CSB, CUB, DCB, TMB; Airtel PB / Fino; Citi / StanChart / DBS / Amex  

**Recipe:** trusted hint + sender map → 2–4 body regexes → discovery → synthetic corpus → schema bump → dump QA.

---

## 8. Example templates (sanitized)

```
VK-CANBNK-S	Dear Customer, Acct XXX5510 Dr. INR 320.00 on 11/07/26 to PHONEPE MART; UPI: 111222333444; Bal INR 4,100.00.-CanaraBank
VM-UNIONB-S	A/c *7788 Debited for Rs:1500.00 on 12-07-2026 18:28:02 by Mob Bk ref no 123456789000 Avl Bal Rs:8200.00
JX-BOIIND-S	Rs.200.00 debited A/cXX5468 and credited to SAI MISAL via UPI Ref No 315439383341 on 23Aug25. -BOI
VM-INDUSB-S	INR 499.00 spent on IndusInd Card XX4821 on 14-06-2026 04:21:45 pm at INSTAMART. Avl Lmt: INR 45000.00.
VM-AUBANK	INR 259.90 spent at TELEGRAM PREMIUM on AU Bank Credit Card x1234 21-03-2026 05:49:40 PM.
XY-BDNSMS-S	INR 25,000.00 deposited to A/c XXXXXXXXXX1234 towards UPI/CR/C224513287910/JOHN DOE/u . Clear Bal is INR 30,123.00 . Bandhan Bank.
VM-EQUTAS-S	INR 450.00 debited via UPI from Equitas A/c 12XX -Ref:571987071234 on 19-12-25 to SWIGGY. Avl Bal is INR 12,345.67.
```

---

## 9. Gaps needing real user SMS

- RBL / Ujjivan / UCO / IOB **body samples** (no clear PennyWise fixtures)
- Bandhan / IDBI / AU **additional** CC spend variants beyond AU fixture
- IPPB: which of `MYIPPB` vs `IPBMSG` dominates live
- Regional-language (BOB LANG) Unicode bodies
- Paisa private dump confirmation of Tier-1/2 presence
- Wallet vs payments-bank double-count pairs  

Volunteer format: sender ID + body with masks as `••••1234` + savings/CC/loan + approx year. Never commit real dumps.

---

## 10. Sources

| Source | URL |
| --- | --- |
| RBI Banks in India | https://www.rbi.org.in/commonman/english/scripts/banksinindia.aspx |
| RBI Customer Protection | https://www.rbi.org.in/commonman/english/scripts/Notification.aspx?Id=2336 |
| RBI BSR-2 Jun 2026 | https://rbi.org.in/scripts/BS_PressReleaseDisplay.aspx?prid=63476 |
| DLT header gist | https://gist.github.com/abhishekjnvk/ad596df86a22291ccd76cf29af52b656 |
| Mint deposit/customer | https://www.livemint.com/industry/banking/sbi-leads-in-deposits-and-customer-base-hdfc-bank-tops-average-deposits-per-customer-11786728135484.html |
| PennyWise (primary OSS) | https://github.com/sarim2000/pennywiseai-tracker |
| Union / BOB / PNB / Indus / Bandhan / IPPB official SMS pages | (linked in §6) |
| Paisa code | `lib/services/sms/sms_parser.dart`, `account_discovery.dart`, `sms_scan_pipeline.dart` |

---

*Updated 2026-09-05: Tier-1 + Tier-2 parsers shipped in Paisa (schema 36–37). Research shapes from PennyWise public fixtures; Dart implementations are original.*
