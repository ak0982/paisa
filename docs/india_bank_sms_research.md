# India bank SMS research — parser coverage guide for Paisa

> **Purpose:** Evidence-based inventory of RBI-regulated banks that commonly send debit/credit SMS in India, SMS taxonomy, public template shapes, and a gap analysis vs Paisa's current parser. Use this to prioritize expanding `sms_parser.dart` / `account_discovery.dart` / sender hints.
>
> **Research date:** 2026-07-23  
> **Scope:** Scheduled commercial banks (PSU + private), small finance banks, payments banks, and a short list of foreign retail banks that issue consumer alerts. Cooperative banks / RRBs noted but not fully inventoried.
>
> **Hard rules for this doc:** No real user SMS, masks, or personal data. All body examples are **synthetic / anonymized** (fictional last-4). Confidence levels reflect public documentation quality, not production validation.

---

## 1. Executive summary

Indian banks must alert customers on electronic banking transactions (RBI customer-protection framework). Alerts arrive as TRAI DLT-registered SMS with 6-character headers (e.g. `HDFCBK`) often prefixed by operator+circle (`VM-HDFCBK`, `AX-SBIINB`). Message bodies use shared Indian-English phrasing (`Rs`/`INR`, `A/c XX1234`, `debited`/`credited`, `Avl Bal`, `spent on your … Credit Card ending`).

**Paisa today** has deep regex coverage for a handful of majors (HDFC, SBI, ICICI, Axis, Kotak, IDFC, Yes, Federal/Fi/Jupiter, partial PNB/IndusInd) plus wallets, and **sender-only** recognition for Canara and Bank of Baroda. Large PSUs (Union, Indian Bank, BOI, Canara deep parse), mid-tier privates (RBL, Bandhan, South Indian, KVB, Karnataka), SFBs (AU, Equitas, Ujjivan), and payments banks (IPPB, Airtel PB, Fino) are largely missing as first-class banks.

**This inventory catalogues 55 entities** (12 PSU + 21 private + 11 SFB + 5 active payments banks + Paytm PB cancelled + 5 foreign retail focus). Public template evidence is **High** for only ~10 majors; most others are **Medium/Low** (sender IDs known, body shapes inferred from common patterns / OSS parsers). **Production still needs validation against real inboxes** — never treat this doc as a substitute for dump-backed tests.

---

## 2. Regulatory & DLT context

| Topic | What matters for parsers | Sources |
| --- | --- | --- |
| Mandatory e-banking alerts | Banks must register mobile numbers and send SMS alerts for electronic transactions; 24×7 dispute channels; timestamped delivery. | [RBI Customer Protection – Limiting Liability…](https://www.rbi.org.in/commonman/english/scripts/Notification.aspx?Id=2336) (DBR.No.Leg.BC.78/09.07.005/2017-18 and related) |
| SMS charges | Alerts charged on actual usage basis (historical circular). | [RBI – Charges for SMS Alerts](https://www.rbi.org.in/commonman/english/scripts/Notification.aspx?Id=1292) |
| Bank universe | Official lists of SCBs / SFBs / PBs / foreign banks. | [RBI – Banks in India](https://www.rbi.org.in/commonman/english/scripts/banksinindia.aspx) |
| DLT headers | 6-char alphabetic header (`HDFCBK`); display form often `XX-HEADER` where `XX` = operator+circle. | [TrueSender DLT prefix guide](https://www.truesenderapp.com/blog/what-are-sms-sender-id-prefixes-in-india-a-complete-guide); TRAI DLT framework |
| Template registration | Variables as `{#var#}`; transactional vs service vs promo categories. | [Infobip India DLT templates](https://www.infobip.com/docs/essentials/asia-registration/dlt-templates) |
| Future alert mix | Industry commentary (2026) that low-value alerts may shift toward push/in-app — **SMS volume may drop for small UPI**; do not assume every txn still produces SMS forever. | Secondary reporting only — verify against final RBI directions before product bets |

**Sender ID shape (parser tip):** Match on the **6-char header substring**, not the full `VM-`/`AX-`/`JD-` prefix (operator/circle varies by recipient SIM). Paisa already does this (`contains('HDFCBK')`, etc.).

---

## 3. Paisa current coverage (from code — do not invent)

Ground truth: `lib/services/sms/sms_parser.dart`, `sms_scan_pipeline.dart`, `account_discovery.dart`, `sms_keyword_lists.dart`, `AGENTS.md` §4.5.

| Tier | Entities | Evidence in code |
| --- | --- | --- |
| **Rich parse** | HDFC, SBI (savings + UPI + CC + NACH/BBPS), ICICI (savings + CC + settlement), Axis (CC + generic debit), Kotak (UPI/NEFT/NACH/savings), IDFC FIRST (CC + savings phrasing), Yes Bank (CC), Federal (+ Fi `FEDFIB` / Jupiter `MYJPTR`) | Dedicated regex families in `sms_parser.dart`; discovery patterns for savings/CC/loan |
| **Partial parse** | PNB (loan deposit / long masks / balance-style discovery), IndusInd (CC ending patterns / sender) | Some body regexes + discovery; not full debit/credit suite |
| **Sender / thin only** | Canara, Bank of Baroda (BOBCARD payment phrasing exists for CC payment received) | `_detectBankFromSender` / pipeline `_senderHints`; AGENTS.md explicitly: “mostly sender-detection only” |
| **Wallets / UPI apps** | Paytm, PhonePe, GPay, Amazon Pay, MobiKwik, Freecharge, Airtel Money, Ola Money, Jio Money, PayZapp | Sender + body wallet lists; cross-source dedupe with bank SMS |
| **Other** | LenDenClub (P2P) | Sender hint |
| **Not first-class** | Union, Indian Bank, BOI, Central, Maharashtra, IOB, UCO, P&SB, Bandhan, RBL, South Indian, KVB, Karnataka, CSB, CUB, DCB, TMB, J&K, Nainital, Dhanlaxmi, IDBI, all SFBs, IPPB / Airtel PB / Fino / Jio PB / NSDL PB, most foreign retail | No bank name mapping / dedicated templates |

Trusted sender hint fragments (subset): `HDFCBK`, `KOTAKB`, `CBSSBI`, `PNBSMS`, `SBICRD`, `SBIN`, `YESBNK`, `IDFCFB`, `ICICIT`, `ICICIO`, `AXISBK`, wallet headers, etc. Pipeline also accepts broader tokens (`HDFC`, `SBI`, `CANARA`, `BARODA`, …).

---

## 4. RBI-approved bank inventory

Primary official source: [RBI Banks in India](https://www.rbi.org.in/commonman/english/scripts/banksinindia.aspx) (fetched 2026-07-23). Cross-checked with [Wikipedia – List of banks in India](https://en.wikipedia.org/wiki/List_of_banks_in_India) for counts. Sender headers from community DLT dump ([gist abhishekjnvk, Dec 2022](https://gist.github.com/abhishekjnvk/ad596df86a22291ccd76cf29af52b656)) — **stale risk: Medium**; treat as starting points.

**Legend — Paisa?**  
- **Y-rich** = dedicated parse patterns  
- **Y-partial** = some patterns / discovery  
- **Y-sender** = recognized as financial sender / bank name only  
- **N** = not mapped as a bank in parser detection

**Legend — SMS conf.** = confidence that public evidence of *transaction alert body shape* exists (independent of Paisa).

### 4.1 Public sector banks (12)

| Bank | Type | Common SMS header(s) | Paisa? | SMS conf. | Notes |
| --- | --- | --- | --- | --- | --- |
| State Bank of India | PSU | `SBIINB`, `CBSSBI`, `SBIUPI`, `SBIOTP`, `SBICRD` (card) | Y-rich | High | Largest retail SMS volume; UPI + YONO + SBI Card separate headers |
| Punjab National Bank | PSU | `PNBSMS` | Y-partial | Med | Long account masks in discovery |
| Bank of Baroda | PSU | `BOBSMS`, related `BOB*` | Y-sender | Med | BOBCARD payment phrasing partially covered |
| Canara Bank | PSU | `CANBNK` | Y-sender | Med | High-value gap for deep parse |
| Union Bank of India | PSU | `UNIONB` | N | Med | SMS banking product page exists; body samples scarce publicly |
| Bank of India | PSU | `BOIIND` | N | Low–Med | |
| Indian Bank | PSU | `INDBNK` | N | Low–Med | |
| Central Bank of India | PSU | (various; verify live) | N | Low | |
| Indian Overseas Bank | PSU | (various) | N | Low | |
| UCO Bank | PSU | `UCOBNK` | N | Low | |
| Bank of Maharashtra | PSU | `MAHABK` | N | Low | |
| Punjab & Sind Bank | PSU | (various) | N | Low | |

### 4.2 Private sector banks (21)

| Bank | Type | Common SMS header(s) | Paisa? | SMS conf. | Notes |
| --- | --- | --- | --- | --- | --- |
| HDFC Bank | Private | `HDFCBK`, `HDFCBN` (bank advisory) | Y-rich | High | Official: trust `HDFCBK` / `HDFCBN` |
| ICICI Bank | Private | `ICICIB`, `ICICIT`, `ICICIO` | Y-rich | High | Multiple product headers |
| Axis Bank | Private | `AXISBK` | Y-rich | High | |
| Kotak Mahindra Bank | Private | `KOTAKB` | Y-rich | High | Distinct “Sent Rs… from Kotak Bank AC” shapes |
| IDFC FIRST Bank | Private | `IDFCFB` | Y-rich | High | CC “spent on your IDFC FIRST…” |
| Yes Bank | Private | `YESBNK` | Y-rich | High | “YES BANK Card X####” |
| IndusInd Bank | Private | `INDUSB` | Y-partial | Med | |
| Federal Bank | Private | `FEDBNK`; neo `FEDFIB`, `MYJPTR` | Y-rich | High | Fi / Jupiter ride Federal savings |
| Bandhan Bank | Private | `BDNSMS`, `BNDNBK`, numeric `154321` (legacy dump) | N | Low–Med | Growing retail; high expansion value |
| RBL Bank | Private | `RBLBNK` | N | Med | Active CC issuer |
| IDBI Bank | Private | `IDBIBK` | N | Med | Re-categorized private |
| South Indian Bank | Private | `SIBSMS` | N | Low–Med | |
| Karnataka Bank | Private | (DLT alpha variants) | N | Low | |
| Karur Vysya Bank | Private | (variants) | N | Low | |
| City Union Bank | Private | `CUBANK` | N | Low | |
| CSB Bank | Private | `CSBBNK` | N | Low | |
| DCB Bank | Private | `DCBBNK` | N | Low | |
| Tamilnad Mercantile Bank | Private | `TMBANK` | N | Low | |
| Jammu & Kashmir Bank | Private | (variants) | N | Low | |
| Dhanlaxmi Bank | Private | (variants) | N | Low | |
| Nainital Bank | Private | (variants) | N | Low | |

### 4.3 Small finance banks (11 on RBI summary list)

RBI summary table (Banks in India page): Au, Capital, Equitas, ESAF, Suryoday, Ujjivan, Utkarsh, slice, Jana, Shivalik, Unity. Address section also lists these; Wikipedia cites 12 SFBs (includes Fino transition path — treat carefully).

| Bank | Type | Common SMS header(s) | Paisa? | SMS conf. |
| --- | --- | --- | --- | --- |
| AU Small Finance Bank | SFB | `AUBANK`, `AUBSMS`, `AUBMSG` | N | Med |
| Equitas Small Finance Bank | SFB | `EQBANK`, `EQUTAS`, … | N | Med |
| Ujjivan Small Finance Bank | SFB | `UJJIVN` | N | Med |
| ESAF Small Finance Bank | SFB | `ESAF*` family | N | Low–Med |
| Suryoday Small Finance Bank | SFB | (variants) | N | Low |
| Utkarsh Small Finance Bank | SFB | (variants) | N | Low |
| Jana Small Finance Bank | SFB | (variants) | N | Low |
| Capital Small Finance Bank | SFB | (variants) | N | Low |
| Shivalik Small Finance Bank | SFB | (variants) | N | Low |
| Unity Small Finance Bank | SFB | (variants) | N | Low |
| slice Small Finance Bank | SFB | (variants; also BNPL/card SMS historically) | N | Low–Med |

**Note:** Fino has **in-principle** RBI approval (Dec 2025) to convert from Payments Bank → SFB; until licensing completes it remains a PB in operational SMS terms. Source: [Fino disclosure / RBI press](https://www.fino.bank.in/files/fino/media/post_attachments/sites/default/files/uploads/pages/announcements-intimation/cover_5_12_2025.pdf).

### 4.4 Payments banks

| Bank | Type | Common SMS header(s) | Paisa? | SMS conf. | Notes |
| --- | --- | --- | --- | --- | --- |
| India Post Payments Bank | PB | `MYIPPB` (and related IPPB variants — verify live) | N | Med | High rural/DBT SMS volume |
| Airtel Payments Bank | PB | `AIRBNK`; also near `AIRTEL` / wallet family | N / wallet-ish | Med | Overlaps Airtel Money wallet detection |
| Fino Payments Bank | PB | `FINOBK` | N | Med | Transitioning to SFB |
| Jio Payments Bank | PB | (Jio family — verify) | N / Jio Money wallet | Low–Med | Listed in RBI address block; summary tables vary |
| NSDL Payments Bank | PB | `NSDLPB` | N | Low | |
| Paytm Payments Bank | PB (licence cancelled) | `PAYTMB` historically | Wallet **Paytm** still Y | Med | RBI list marks licence cancelled; Paytm **app/wallet** SMS may continue under non-bank entities — keep wallet parsers, do not treat PPBL as active bank |

### 4.5 Foreign / WOS retail focus (SMS-relevant subset)

Full foreign list is long (~44); most corporate/wholesale. Consumer SMS relevance:

| Bank | Type | Header examples | Paisa? | SMS conf. |
| --- | --- | --- | --- | --- |
| DBS Bank India | Foreign WOS | `DBSBNK` | N | Med |
| SBM Bank (India) | Foreign WOS | (variants; Niyo historically on SBM rails) | N | Med |
| Citibank N.A. / Citi | Foreign | `CITIBK` | N | Med |
| HSBC | Foreign | `HSBCIN` | N | Med |
| Standard Chartered | Foreign | `SCBANK` | N | Med |
| American Express Banking Corp. | Foreign | Amex card alerts | N | Med |
| Deutsche Bank | Foreign | (variants) | N | Low |

### 4.6 Out of deep scope (for later)

- **28 RRBs** (RBI list) — send SMS but low priority unless user demand.  
- **State / urban cooperative banks** — many DLT headers; templates highly local.  
- **2 Local Area Banks** (Coastal, Krishna Bhima Samruddhi) — negligible for Paisa v1 expansion.

**Catalogue count for this doc:** **55** named entities in §4.1–4.5 (including cancelled Paytm PB as a footnote row).

---

## 5. SMS taxonomy (what banks send)

### 5.1 Savings / current — money movement

| Category | Typical phrasing cues | Parser action |
| --- | --- | --- |
| Debit (generic) | `debited from` / `debited to your Account` / `Acct XX#### debited` | Expense / transfer |
| Credit (generic) | `credited to` / `Credit Alert!` / `has been credited with` | Income / transfer |
| UPI | `UPI`, `trf to`, `Sent Rs… to vpa@upi`, `Dear UPI user` | Expense; merchant from VPA/name |
| NEFT / IMPS / RTGS | `via NEFT` / `IMPS` / `RTGS` | Direction from credited/debited |
| ATM | `ATM WDL` / `withdrawn` / `ATM cash` | Expense |
| Cash / branch deposit | `deposited in` / `cash deposit` | Income |
| Interest | `interest credited` / `int. credited` | Income (often small) |
| Salary | `SALARY` / employer NEFT credit | Income |
| Cheque | `cheque` / `chg` / `cleared` / `returned` | Expense or noise depending on settle vs bounce |
| Failed / reverse | `failed` / `reversed` / `refund` / `reversal` | Often credit; careful with double-count |
| Charges / fees | `charges` / `fee` / `GST` / `SMS charges` | Expense |
| Balance enquiry reply | `Avl Bal` / `Available Balance` **without** debit/credit verb | **Reject** as txn (discovery-only OK) |

**Common Indian SMS tokens:** `Rs.` / `Rs` / `INR` / `₹`; `A/c` / `Acct` / `AC` / `Account`; masks `XX1234`, `**1234`, `XXXXXX1234`, long PNB-style masks; suffix `Avl Bal` / `Available Balance` / `Total Bal`.

### 5.2 Credit card

| Category | Cues | Notes |
| --- | --- | --- |
| Spend | `spent on your … Credit Card ending` / `spent using … Card XX` | Primary CC expense shape |
| Online / ecom | merchant + `Info:` / `@UPI_` | |
| EMI conversion | `converted to EMI` / `SmartEMI` | Often **promo-adjacent** — Paisa promo filter may reject; validate carefully |
| Payment received | `Payment of Rs… received` / `credited towards your … Credit Card` / BBPS | **Not** savings income; CCBP funding side is savings debit |
| Statement / due | `payment due` / `minimum amount due` / `statement` | Noise for txn parse; useful for reminders later |
| Limit | `credit limit` / `available limit` | Noise or enrichment |
| Cash withdrawal | `cash withdrawal` on card | Expense + fee |
| International | `USD` / `foreign` / currency conversion note | Still parse amount in INR if present |

### 5.3 Loans / EMI / NACH

| Category | Cues |
| --- | --- |
| NACH / ECS debit | `NACH` / `ECS` / `ACH` / `auto debit` / `is debited to your Account … towards` |
| EMI reminder | `EMI of Rs… due` | Often non-completed — reject unless confirmed debit |
| Loan credit / disbursal | `disbursed` / `credited to Loan` | Rare in retail SMS |
| Bounce / insufficient | `insufficient funds` / `ECS return` / return charges | Fee expense |

Paisa already treats NACH carefully so a single EMI debit does **not** flip a savings mask to loan (balanced voting).

### 5.4 Wallets / UPI apps (not banks)

Appear in the same inbox and must be gated:

| App | Role | Paisa |
| --- | --- | --- |
| PhonePe, GPay, Paytm | PSP / wallet debit SMS duplicating bank UPI | Supported; cross-source dedupe prefers bank |
| Amazon Pay, MobiKwik, Freecharge | Wallet | Supported |
| BHIM | UPI | Sender hint |

### 5.5 Non-transaction noise (reject)

| Category | Cues | Paisa handling |
| --- | --- | --- |
| OTP | `OTP` / `One Time Password` / `do not share` without completed txn | `isOtpOnly` |
| Promo / offers | `pre-approved`, `apply now`, `eligible for`, `congratulations` | `bank_promo_filters.dart` |
| KYC / re-KYC | `update KYC` / `CKYC` | Reject (no txn signal) |
| Card block / netbanking scare phishing | Fake urgency + link; often **not** from real DLT header | Personal-number reject (ISSUE-3); still harden header allowlists |
| Marketing EMI | `SmartEMI`, obfuscated `L0AN` | Promo filters |

---

## 6. Per-bank / template notes (public evidence)

Confidence: **High** = multiple independent public samples or bank-confirmed headers + Paisa synthetic corpus alignment. **Med** = header known + OSS/FAQ/secondary samples. **Low** = header only or inferred phrasing.

### 6.1 Template clusters (shared wording)

| Cluster | Banks often similar | Shape sketch |
| --- | --- | --- |
| **“Spent on your X Credit Card ending”** | SBI Card, Axis, HDFC, Kotak, IDFC, ICICI variants | `Rs/INR {amt} spent on your {BANK} Credit Card ending XX{mask} at {merchant}` |
| **“Acct XX debited for Rs”** | ICICI-style | `ICICI Bank Acct XX{mask} debited for Rs {amt} on {date}; {payee} credited. Avl Bal…` |
| **“Sent Rs from {Bank} A/C”** | HDFC, Kotak UPI | `Sent Rs.{amt} From/from {Bank} A/C *{mask} To {payee}` |
| **“Dear … Rs debited from A/c XX”** | SBI savings | `Rs.{amt} debited from A/c XX{mask} on {date}. Info: {narration}. Avl Bal…` |
| **Aggregator / ValueFirst / Infobip** | Many mid-tier via same CPaaS | Same DLT variable style; bodies still bank-branded — match bank name + verbs, not aggregator |

### 6.2 Majors (depth)

#### SBI — High
- **Headers:** `SBIINB`, `CBSSBI`, `SBIUPI`, `SBICRD`, …  
- **Savings debit (synthetic):** `Dear SBI User, Rs.2,499.00 debited from A/c XX8890 on 06Jul26. Info: AMAZON.IN Avl Bal Rs.10,000.00`  
- **UPI:** `Dear UPI user A/C X0429 debited by 3250.00 on date … trf to MERCHANT`  
- **CC:** `Rs.605.29 spent on your SBI Credit Card ending 3452 at MERCHANT`  
- **Sources:** Paisa synthetic corpus; OSS parsers; SBI Card site stresses enabling SMS alerts ([sbicard.com](https://www.sbicard.com/)).

#### HDFC — High
- **Headers:** `HDFCBK` / `HDFCBN` (bank anti-fraud advisory).  
- **Shapes:** `Rs.{amt} debited from HDFC Bank A/c **{mask}`; `Sent Rs.{amt} From HDFC Bank A/C *{mask} To {payee}`; `Credit Alert! Rs.{amt} credited to HDFC Bank A/c XX{mask}`; NEFT `deposited in HDFC Bank A/c XX{mask}`.  
- **Sources:** Official header naming in bank safety posts; Paisa patterns + synthetic corpus.

#### ICICI — High
- **Headers:** `ICICIB`, `ICICIT`, `ICICIO`.  
- **Shapes:** `ICICI Bank Acct XX{mask} debited for Rs {amt}… Avl Bal`; CC `INR {amt} spent using ICICI Bank Card XX{mask} on … on MERCHANT`; payment received on CC; UPI on CC `Credit Card XX{mask} debited for INR…`.  
- **Sources:** Paisa patterns; [ICICI SMS banking](https://www.icici.bank.in/personal-banking/ways-to-bank/mobile-banking/sms-banking) (pull commands, not push templates).

#### Axis — High
- **Headers:** `AXISBK`.  
- **Shapes:** `INR {amt} spent on your Axis Bank Credit Card ending XX{mask} at {merchant}`; savings `INR {amt} debited on {date} Info: {narration}`.  
- **Sources:** Paisa synthetic + regex.

#### Kotak — High
- **Headers:** `KOTAKB`.  
- **Shapes:** `Sent Rs.{amt} from Kotak Bank AC X{mask} to {vpa}`; `Rs. {amt} credited to your Kotak Bank a/c XX{mask} via NEFT`; NACH `INR {amt} is debited to your Account XXXXXX{mask} towards {beneficiary}`.  
- **Sources:** Paisa patterns.

#### IDFC FIRST — High
- **Headers:** `IDFCFB`.  
- **Shapes:** `INR {amt} spent on your IDFC FIRST Bank Credit Card ending XX{mask} at {merchant}`.  
- **Sources:** Paisa patterns.

#### Yes Bank — High (CC) / Med (savings)
- **Headers:** `YESBNK`.  
- **Shapes:** `INR {amt} spent on YES BANK Card X{mask} @{merchant}`.  
- **Sources:** Paisa CC regex; savings less documented in-repo.

#### Federal / Fi / Jupiter — High
- **Headers:** `FEDBNK`, `FEDFIB`, `MYJPTR`.  
- **Note:** Resolve neo senders → bank display `Federal`. Balance / account SMS may lack classic debit verbs — discovery patterns matter.  
- **Sources:** Paisa schema history (savings coverage bump).

#### PNB — Med
- **Headers:** `PNBSMS`.  
- **Shapes:** Long masks; `Ac XXXXXXXX{mask} Credited with Rs…`; loan `Thanks for depositing Rs. … against your Loan Ac XX{mask}`.  
- **Sources:** Paisa partial patterns.

#### IndusInd — Med
- **Headers:** `INDUSB`.  
- **Shapes:** CC ending patterns shared with majors; savings less covered in Paisa.  
- **Sources:** Discovery regex list; OSS credit-card test mentions.

### 6.3 High-value missing / thin banks

#### Canara — Med (header) / Low (body in Paisa)
- **Header:** `CANBNK`.  
- **Expected shape (inferred, Low–Med):** `Rs/INR … debited/credited … A/c XX… Avl Bal` — **needs real samples**.  
- **Paisa:** sender only.

#### Bank of Baroda — Med
- **Header:** `BOBSMS`.  
- **Partial:** CC payment received regex mentions Bank of Baroda.  
- **Need:** savings UPI/IMPS templates.

#### Union Bank — Med (product) / Low (template)
- SMS banking FAQ: push alerts on debit/credit above customer threshold ([unionbankofindia.bank.in SMS Banking](https://www.unionbankofindia.bank.in/en/details/sms-banking)).  
- **Header:** `UNIONB`. Exact body: **not publicly standardized** — collect from volunteers / anonymized dumps.

#### Indian Bank, Bank of India, Central, Maharashtra, IOB, UCO, P&SB — Low
- Headers exist in DLT dumps (`INDBNK`, `BOIIND`, `MAHABK`, `UCOBNK`, …).  
- Body evidence: sparse. Assume generic PSU cluster until proven otherwise.

#### Bandhan, RBL, South Indian, KVB, Karnataka, IDBI — Low–Med
- Retail + cards growing. RBL especially for CC.  
- Headers: `RBLBNK`, `SIBSMS`, `IDBIBK`, …

#### AU / Equitas / Ujjivan SFB — Med (headers)
- Headers: `AUBANK`, `EQBANK`, `UJJIVN`.  
- Bodies: not in Paisa; expect standard debit/credit + Avl Bal. Validate before shipping regex.

#### IPPB / Airtel PB / Fino — Med
- High inclusion / DBT / cash-point credits.  
- Distinct product vocabulary (`IPPB`, AePS, etc.) — plan dedicated tests.

#### Foreign retail (Citi, HSBC, StanChart, DBS, Amex) — Med
- Often English “INR … debited from A/c…” (see OSS example in [transaction-sms-parser README](https://github.com/saurabhgupta050890/transaction-sms-parser)).  
- Lower mass-market volume than PSUs but affluent users.

### 6.4 Open-source cross-checks (ideas only — no dependency)

| Project | Banks claimed | Use for Paisa |
| --- | --- | --- |
| [saurabhgupta050890/transaction-sms-parser](https://github.com/saurabhgupta050890/transaction-sms-parser) | Axis, ICICI, Kotak, HDFC, StanChart, IDFC, Federal, SBM/Niyo, wallets, several CCs | Compare regex ideas; do not copy blindly |
| [Pavel401/transaction_sms_parser](https://github.com/Pavel401/transaction_sms_parser) (Dart) | 30+ banks claim | Keyword lists already inspired `sms_keyword_lists.dart` |

---

## 7. Gap analysis vs Paisa

### 7.1 Supported well (keep investing in template drift tests)

HDFC, SBI, ICICI, Axis, Kotak, IDFC FIRST, Yes (CC), Federal (+ Fi/Jupiter), major wallets (PhonePe/GPay/Paytm).

### 7.2 Recognized thinly

| Bank | Gap |
| --- | --- |
| Canara | Sender yes; almost no body regex / discovery |
| Bank of Baroda | Sender yes; CC payment fragment only |
| PNB | Partial savings/loan; incomplete UPI/IMPS suite |
| IndusInd | CC-oriented; thin savings |

### 7.3 High-value missing entirely (no bank mapping)

Rough priority by likely SMS volume / card presence among Indian Android users:

1. Union Bank of India  
2. Canara (upgrade from thin → rich)  
3. Bank of Baroda (upgrade)  
4. Bank of India  
5. Indian Bank  
6. Bandhan Bank  
7. RBL Bank (esp. cards)  
8. IDBI Bank  
9. AU Small Finance Bank  
10. India Post Payments Bank  
11. South Indian Bank  
12. Karnataka Bank / Karur Vysya (tie — regional south)  
13. Equitas SFB  
14. Ujjivan SFB  
15. Airtel Payments Bank / Fino (payments-bank cluster)

Honorable mentions: Central Bank, Bank of Maharashtra, IOB, DBS India, HSBC/StanChart/Citi for niche users.

### 7.4 Recommended next parser expansion order (top 15)

| # | Target | Why | First engineering slice |
| --- | --- | --- | --- |
| 1 | **Canara** | Already in sender hints; large PSU | Map `CANBNK` → Canara; add debit/credit + Avl Bal regex; discovery |
| 2 | **Bank of Baroda** | Already thin; BOBCARD | Savings UPI/IMPS + CC spend “ending” |
| 3 | **Union Bank** | Huge merged PSU | Header `UNIONB` + generic PSU templates |
| 4 | **Bank of India** | Large PSU | `BOIIND` + generic |
| 5 | **Indian Bank** | Large PSU | `INDBNK` + generic |
| 6 | **PNB deepen** | Partial already | UPI + IMPS debit/credit completeness |
| 7 | **IndusInd deepen** | Partial already | Savings + CC payment received |
| 8 | **Bandhan** | Fast-growing private | New sender + templates |
| 9 | **RBL** | CC-heavy | CC spend + savings |
| 10 | **IDBI** | Wide branch network | Generic private templates |
| 11 | **AU SFB** | Largest SFB | `AUBANK` family |
| 12 | **IPPB** | Mass DBT / rural | Credit-heavy templates |
| 13 | **Equitas + Ujjivan** | SFB pair | Shared SFB phrasing tests |
| 14 | **South Indian / KVB / Karnataka** | South cluster | Regional private batch |
| 15 | **Airtel PB / Fino** | Payments banks | Avoid double-count with wallets |

For each slice: extend `_detectBankFromSender` + pipeline hints → 2–4 body regexes → discovery → synthetic corpus lines → schema bump → dump-backed test if available.

---

## 8. Appendix — anonymized example templates

Fictional last-4 only. Suitable for `test/fixtures/synthetic_sms_corpus.txt` style tests.

### A. Savings / current

```
# HDFC UPI debit
VM-HDFCBK	Sent Rs.486.00 from a/c **4321 to Swiggy on 07-Jul-26 UPI ref 5521.

# SBI savings debit
SBIINB	Dear SBI User, Rs.2,499.00 debited from A/c XX8890 on 06Jul26. Info: AMAZON.IN Avl Bal Rs.10,000.00

# ICICI IMPS debit
ICICIT	ICICI Bank Acct XX4321 debited for Rs 850.00 on 03-Jul-26; MERCHANT XYZ credited. Avl Bal Rs.5,000.00

# Kotak NEFT credit
VM-KOTAKB	Rs.500.00 credited to your Kotak Bank a/c XX3649 via NEFT from EMPLOYER PVT LTD on 01-Jul-26.

# Generic PSU-style (Union — hypothetical until validated)
VM-UNIONB	INR 1,500.00 debited from A/c XX7788 on 12-07-26 towards UPI/merchant@okaxis. Avl Bal INR 8,200.00

# Canara-style (hypothetical)
AX-CANBNK	Rs.320.00 debited from Canara Bank A/c XX5510 on 11-07-26. Info: PHONEPE. Avl Bal Rs.4,100.00
```

### B. Credit card

```
# Axis CC spend
AX-AXISBK	INR 1,200.00 spent on your Axis Bank Credit Card ending XX8341 at IRCTC on 05-Jul-26.

# SBI CC spend
JD-SBICRD	Rs.605.29 spent on your SBI Credit Card ending 3452 at BIGBAZAAR on 04-Jul-26. Avl limit Rs.50,000.00

# IDFC CC spend
VM-IDFCFB	INR 80.00 spent on your IDFC FIRST Bank Credit Card ending XX7424 at HungerBox on 03-Jul-26.

# ICICI CC payment received
ICICIO	Payment of Rs 14,747.00 received on your ICICI Bank Credit Card XX2009 on 02-Jul-26.
```

### C. Noise (must not parse as txn)

```
VM-HDFCBK	Your OTP for login is 482913. Do not share with anyone. Valid for 10 minutes.
VM-HDFCBK	Pre-approved personal loan of Rs.5,00,000 waiting for you. Apply now on HDFC NetBanking.
+919876543210	Congrats, Y0UR Received Rs.542000 L0AN is Approve. Withdraw direct T0 Y0UR A/c.
```

---

## 9. Caveats (read before implementing)

1. **Templates change** without notice (DLT re-registration, aggregator switch, A/B copy). Regexes need continuous corpus refresh.  
2. **Public samples are incomplete** — especially mid-tier PSU/SFB bodies. Confidence Low ≠ “bank does not send SMS”.  
3. **Headers rotate** (`VM-` vs `AX-` vs `JD-`); always match the 6-char PE header. Numeric sender IDs still appear for some entities in older DLT dumps — prefer alphabetic transactional headers.  
4. **Paytm Payments Bank licence cancelled** (RBI list + 2026 news). Keep **Paytm wallet/PSP** parsing separate from “bank = PPBL”.  
5. **Duplicate SMS** (bank + PhonePe/GPay) remain common — preserve cross-source dedupe.  
6. **Push may replace some low-value SMS** over time — SMS coverage will never be 100% of spend.  
7. **Never commit real SMS dumps** or real masks; validate with `~/Downloads/my_sms.txt` locally / synthetic fixtures in CI.  
8. **This research is not production validation.** Ship parsers only after synthetic tests + (where available) private-dump diagnostics.

---

## 10. Source index

| Source | URL / location |
| --- | --- |
| RBI Banks in India | https://www.rbi.org.in/commonman/english/scripts/banksinindia.aspx |
| RBI Customer Protection (SMS alerts) | https://www.rbi.org.in/commonman/english/scripts/Notification.aspx?Id=2336 |
| RBI SMS alert charges | https://www.rbi.org.in/commonman/english/scripts/Notification.aspx?Id=1292 |
| Wikipedia bank lists (secondary) | https://en.wikipedia.org/wiki/List_of_banks_in_India |
| DLT sender prefix explainer | https://www.truesenderapp.com/blog/what-are-sms-sender-id-prefixes-in-india-a-complete-guide |
| Infobip DLT templates | https://www.infobip.com/docs/essentials/asia-registration/dlt-templates |
| Community SMS header gist (2022) | https://gist.github.com/abhishekjnvk/ad596df86a22291ccd76cf29af52b656 |
| HDFC official header advisory | Bank social/safety posts citing `HDFCBK` / `HDFCBN` |
| Union Bank SMS Banking | https://www.unionbankofindia.bank.in/en/details/sms-banking |
| ICICI SMS Banking | https://www.icici.bank.in/personal-banking/ways-to-bank/mobile-banking/sms-banking |
| OSS parsers | https://github.com/saurabhgupta050890/transaction-sms-parser , https://github.com/Pavel401/transaction_sms_parser |
| Paisa code | `lib/services/sms/sms_parser.dart`, `account_discovery.dart`, `sms_scan_pipeline.dart`, `AGENTS.md` |
| Paisa synthetic corpus | `test/fixtures/synthetic_sms_corpus.txt` |

---

*End of research note. Update this file when adding a bank to Paisa or when RBI lists / DLT headers change materially.*
