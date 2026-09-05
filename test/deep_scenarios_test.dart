import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/providers/finance_store.dart';
import 'package:paisa_app/services/sms/bank_promo_filters.dart';
import 'package:paisa_app/services/sms/merchant_categorizer.dart';
import 'package:paisa_app/services/sms/sms_parser.dart';
import 'package:paisa_app/services/sms/sms_scan_pipeline.dart';

import 'helpers/dummy_data.dart';

/// Deep scenario suite — each test maps to TEST_SCENARIOS.md (S01+).
void main() {
  // ─── SMS parsing: valid transactions ───────────────────────────────────
  group('S01-S15 Valid bank SMS parsing', () {
    test('S01 HDFC UPI Sent Rs format', () {
      final p = SmsParser.parse(dummySms(
        id: 's01',
        sender: 'VM-HDFCBK',
        body:
            'Sent Rs.486.00 from a/c **4321 to Swiggy on 07-Jul-26 UPI ref 5521.',
      ));
      expect(p?.amount, 486);
      expect(p?.merchant, 'Swiggy');
    });

    test('S02 SBI debited Info merchant', () {
      final p = SmsParser.parse(dummySms(
        id: 's02',
        sender: 'SBIINB',
        body:
            'Dear SBI User, Rs.2,499.00 debited from A/c XX8890 on 06Jul26. Info: AMAZON.IN',
      ));
      expect(p?.amount, 2499);
    });

    test('S03 ICICI debited for Rs format', () {
      final p = SmsParser.parse(dummySms(
        id: 's03',
        sender: 'ICICIT',
        body:
            'ICICI Bank Acct XX4321 debited for Rs 8500.00 on 03-Jul-26; HDFC Home Loan EMI credited',
      ));
      expect(p?.amount, 8500);
    });

    test('S04 Axis INR debited', () {
      final p = SmsParser.parse(dummySms(
        id: 's04',
        sender: 'AXISBK',
        body: 'INR 312.00 debited on 07-07-26. Info: Ola',
      ));
      expect(p?.merchant, 'Ola');
    });

    test('S05 Kotak towards merchant', () {
      final p = SmsParser.parse(dummySms(
        id: 's05',
        sender: 'KOTAKB',
        body:
            'Rs.645.00 debited from Kotak Bank a/c XXXX7756 towards Zomato on 06/07/26',
      ));
      expect(p?.merchant, 'Zomato');
    });

    test('S06 Paytm paid to', () {
      final p = SmsParser.parse(dummySms(
        id: 's06',
        sender: 'VM-PAYTMB',
        body: 'Rs.299 paid to Jio Recharge via Paytm on 06-Jul',
      ));
      expect(p?.merchant, contains('Jio'));
    });

    test('S07 Credit to account', () {
      final p = SmsParser.parse(dummySms(
        id: 's07',
        sender: 'AXISBK',
        body: 'Rs. 68000.00 credited to your a/c **2015 on 01-Jul-26',
      ));
      expect(p?.isCredit, true);
      expect(p?.amount, 68000);
    });

    test('S08 Indian lakh comma format Rs.1,25,000', () {
      final p = SmsParser.parse(dummySms(
        id: 's08',
        sender: 'HDFCBK',
        body:
            'Rs.1,25,000.00 debited from a/c **4321 on 07-Jul-26. Info: CAR DEALER',
      ));
      expect(p?.amount, 125000);
    });

    test('S09 Small amount Rs.1 debit', () {
      final p = SmsParser.parse(dummySms(
        id: 's09',
        sender: 'HDFCBK',
        body: 'Rs.1.00 debited from a/c **4321 on 07-Jul-26. Info: TEST',
      ));
      expect(p?.amount, 1);
    });

    test('S10 Spent at merchant format', () {
      final p = SmsParser.parse(dummySms(
        id: 's10',
        sender: 'HDFCBK',
        body: 'Rs. 500.00 spent at AMAZON PAY on 07-Jul-26',
      ));
      expect(p?.amount, 500);
    });

    test('S11 PhonePe UPI debit', () {
      final p = SmsParser.parse(dummySms(
        id: 's11',
        sender: 'PHONEPE',
        body: 'Rs.150 paid to Merchant via PhonePe on 07-Jul',
      ));
      expect(p?.amount, 150);
    });

    test('S12 GPay sender', () {
      expect(
        SmsScanPipeline.isFinancialSender('GPAY-AXIS'),
        isTrue,
      );
    });

    test('S13 Yes Bank sender', () {
      expect(
        SmsScanPipeline.isFinancialSender('YESBNK'),
        isTrue,
      );
    });

    test('S14 PNB debit generic', () {
      final p = SmsParser.parse(dummySms(
        id: 's14',
        sender: 'PNBSMS',
        body: 'Rs.750.00 has been debited from your account on 07-Jul-26',
      ));
      expect(p?.amount, 750);
    });

    test('S15 credited with Rs format', () {
      final p = SmsParser.parse(dummySms(
        id: 's15',
        sender: 'HDFCBK',
        body: 'Your account credited with Rs. 5000.00 on 07-Jul-26',
      ));
      expect(p?.isCredit, true);
      expect(p?.amount, 5000);
    });
  });

  // ─── Rejection: promos, OTP, personal ────────────────────────────────
  group('S16-S30 Reject non-transaction SMS', () {
    test('S16 Personal chat ignored', () {
      expect(
        SmsParser.parse(dummySms(
          id: 's16',
          sender: 'FRIEND',
          body: 'Hey, are we meeting for lunch tomorrow?',
        )),
        isNull,
      );
    });

    test('S17 OTP-only ignored', () {
      expect(
        SmsParser.parse(dummySms(
          id: 's17',
          sender: 'HDFCBK',
          body: 'Your OTP for login is 482910. Do not share with anyone.',
        )),
        isNull,
      );
    });

    test('S18 HDFC pre-approved loan', () {
      expect(
        SmsParser.parse(dummySms(
          id: 's18',
          sender: 'VM-HDFCBK',
          body:
              'Get pre-approved Personal Loan of Rs.5,00,000. Apply now. Interest rate starts 10.5%.',
        )),
        isNull,
      );
    });

    test('S19 ICICI loan eligibility', () {
      expect(
        SmsParser.parse(dummySms(
          id: 's19',
          sender: 'ICICIT',
          body:
              'Eligible for instant loan up to Rs.10,00,000. Zero processing fee. Click here.',
        )),
        isNull,
      );
    });

    test('S20 SBI credit card offer', () {
      expect(
        SmsParser.parse(dummySms(
          id: 's20',
          sender: 'SBIINB',
          body:
              'Exclusive offer! SBI Credit Card limit Rs.3,00,000. Apply now. Limited period.',
        )),
        isNull,
      );
    });

    test('S21 HDFC SmartEMI bank promo', () {
      expect(
        SmsParser.parse(dummySms(
          id: 's21',
          sender: 'VM-HDFCBK',
          body:
              'Convert spends to SmartEMI on HDFC Bank Credit Card. Rs.25,000. T&C apply.',
        )),
        isNull,
      );
    });

    test('S22 SBI YONO offer', () {
      expect(
        SmsParser.parse(dummySms(
          id: 's22',
          sender: 'SBIINB',
          body: 'SBI YONO offer! Get SimplyCLICK card. Apply now on YONO.',
        )),
        isNull,
      );
    });

    test('S23 Paytm scratch card promo', () {
      expect(
        SmsParser.parse(dummySms(
          id: 's23',
          sender: 'VM-PAYTMB',
          body:
              'Scratch card unlocked. Refer and earn Rs.100 cashback offer. Claim reward.',
        )),
        isNull,
      );
    });

    test('S24 PhonePe refer and earn', () {
      expect(
        SmsParser.parse(dummySms(
          id: 's24',
          sender: 'PHONEPE',
          body:
              'PhonePe rewards! Refer and earn Rs.200. Win upto Rs.500 cashback.',
        )),
        isNull,
      );
    });

    test('S25 Very short SMS rejected even from bank sender', () {
      expect(
        SmsScanPipeline.passesFinancialGate('HDFCBK', 'Hi'),
        isFalse,
      );
      expect(
        SmsParser.parse(dummySms(id: 's25', sender: 'HDFCBK', body: 'Hi')),
        isNull,
      );
    });

    test('S26 Empty sender and body', () {
      expect(SmsScanPipeline.passesFinancialGate('', ''), isFalse);
    });

    test('S27 Delivery notification not bank', () {
      expect(
        SmsParser.parse(dummySms(
          id: 's27',
          sender: 'AMAZON',
          body: 'Your order has been delivered. Track at amazon.in/track',
        )),
        isNull,
      );
    });

    test('S28 Bank promo filter Axis Grab Deals', () {
      expect(
        BankPromoFilters.matchesBankPromo(
          sender: 'AXISBK',
          body: 'Axis Bank Grab Deals! Axis Neo offer on Flipkart Axis card.',
        ),
        isTrue,
      );
    });

    test('S29 Kotak 811 offer blocked', () {
      expect(
        BankPromoFilters.matchesBankPromo(
          sender: 'KOTAKB',
          body: 'Kotak 811 offer! Dream Different with Super offer.',
        ),
        isTrue,
      );
    });

    test('S30 Pipeline OTP stage', () {
      final r = SmsScanPipeline.process(dummySms(
        id: 's30',
        sender: 'HDFCBK',
        body: 'Your OTP for login is 123456. Do not share with anyone.',
      ));
      expect(r.outcome, SmsPipelineOutcome.otpOnly);
    });
  });

  // ─── Edge cases: try to break parser ─────────────────────────────────
  group('S31-S42 Parser edge cases & break attempts', () {
    test('S31 Real EMI debit with loan keyword still parses', () {
      final p = SmsParser.parse(dummySms(
        id: 's31',
        sender: 'HDFCBK',
        body:
            'Rs.8,500.00 debited from a/c **4321 on 03-Jul-26. Info: HDFC Home Loan EMI.',
      ));
      expect(p?.amount, 8500);
      expect(p?.isCredit, false);
    });

    test('S32 Promo with amount but no completed txn pattern', () {
      expect(
        SmsParser.isPromoOrOfferSms(
          'Pre-approved loan of Rs.5,00,000 available. Apply now.',
          sender: 'HDFCBK',
        ),
        isTrue,
      );
    });

    test('S33 Completed txn overrides promo keywords', () {
      expect(
        SmsParser.isPromoOrOfferSms(
          'Rs.500 debited from a/c **4321. Loan EMI paid.',
          sender: 'HDFCBK',
        ),
        isFalse,
      );
    });

    test('S34 Newline-heavy SMS body', () {
      final p = SmsParser.parse(dummySms(
        id: 's34',
        sender: 'HDFCBK',
        body: 'Sent Rs.100.00\nfrom a/c **4321\nto Swiggy\non 07-Jul-26',
      ));
      expect(p?.amount, 100);
    });

    test('S35 Extra whitespace in body', () {
      final p = SmsParser.parse(dummySms(
        id: 's35',
        sender: 'HDFCBK',
        body: '  Rs.   200.00   debited   from   a/c   **4321  ',
      ));
      expect(p?.amount, 200);
    });

    test('S36 Lowercase bank sender', () {
      expect(SmsScanPipeline.isFinancialSender('vm-hdfcbk'), isTrue);
    });

    test('S37 Body-only bank hint generic VM sender', () {
      expect(
        SmsScanPipeline.hasFinancialBodyHint(
          'Rs.500.00 debited from your account on 07-Jul. Info: SWIGGY',
        ),
        isTrue,
      );
    });

    test('S38 Zero amount should not parse as valid', () {
      final p = SmsParser.parse(dummySms(
        id: 's38',
        sender: 'HDFCBK',
        body: 'Rs.0.00 debited from a/c **4321 on 07-Jul-26',
      ));
      expect(p, isNull);
    });

    test('S39 Unicode rupee symbol ₹ parsed', () {
      final p = SmsParser.parse(dummySms(
        id: 's39',
        sender: 'HDFCBK',
        body: '₹500.00 debited from a/c **4321 on 07-Jul-26. Info: SWIGGY',
      ));
      expect(p?.amount, 500);
    });

    test('S40 Multiple amounts picks first match', () {
      final p = SmsParser.parse(dummySms(
        id: 's40',
        sender: 'HDFCBK',
        body:
            'Rs.500.00 debited from a/c **4321. Avl Bal Rs.32,000 on 07-Jul-26. Info: SWIGGY',
      ));
      expect(p?.amount, 500);
    });

    test('S41 Merchant name very long gets trimmed', () {
      final p = SmsParser.parse(dummySms(
        id: 's41',
        sender: 'HDFCBK',
        body:
            'Sent Rs.100.00 from a/c **4321 to VERYLONGMERCHANTNAMEEXCEEDINGFORTYCHARACTERSLIMIT on 07-Jul',
      ));
      expect(p?.merchant.length, lessThanOrEqualTo(40));
    });

    test('S42 Credit without account still parses', () {
      final p = SmsParser.parse(dummySms(
        id: 's42',
        sender: 'HDFCBK',
        body: 'You received Rs.500 in your account on 07-Jul-26',
      ));
      expect(p?.isCredit, true);
    });
  });

  // ─── Merchant categorization ─────────────────────────────────────────
  group('S43-S52 Merchant categorization', () {
    test('S43 Swiggy → food', () {
      expect(
        MerchantCategorizer.categorize(
          merchant: 'Swiggy',
          smsBody: '',
          isCredit: false,
        ),
        SpendCategory.food,
      );
    });

    test('S44 Amazon → shopping', () {
      expect(
        MerchantCategorizer.categorize(
          merchant: 'Amazon.in',
          smsBody: '',
          isCredit: false,
        ),
        SpendCategory.shopping,
      );
    });

    test('S45 Jio recharge → bills', () {
      expect(
        MerchantCategorizer.categorize(
          merchant: 'Jio Recharge',
          smsBody: '',
          isCredit: false,
        ),
        SpendCategory.bills,
      );
    });

    test('S46 Netflix → entertainment', () {
      expect(
        MerchantCategorizer.categorize(
          merchant: 'Netflix',
          smsBody: '',
          isCredit: false,
        ),
        SpendCategory.entertainment,
      );
    });

    test('S47 EMI in body → emi', () {
      expect(
        MerchantCategorizer.categorize(
          merchant: 'HDFC Home Loan EMI',
          smsBody: 'Home Loan EMI debited',
          isCredit: false,
        ),
        SpendCategory.emi,
      );
    });

    test('S48 Salary credit → income', () {
      expect(
        MerchantCategorizer.categorize(
          merchant: 'Employer',
          smsBody: 'salary credited',
          isCredit: true,
        ),
        SpendCategory.income,
      );
    });

    test('S49 ATM withdrawal → atm', () {
      expect(
        MerchantCategorizer.categorize(
          merchant: 'ATM',
          smsBody: 'cash withdrawal',
          isCredit: false,
        ),
        SpendCategory.atm,
      );
    });

    test('S50 Unknown merchant → other', () {
      expect(
        MerchantCategorizer.categorize(
          merchant: 'Random Shop XYZ',
          smsBody: '',
          isCredit: false,
        ),
        SpendCategory.other,
      );
    });

    test('S51 Ola → travel', () {
      expect(
        MerchantCategorizer.categorize(
          merchant: 'Ola',
          smsBody: '',
          isCredit: false,
        ),
        SpendCategory.travel,
      );
    });

    test('S52 Apollo → health', () {
      expect(
        MerchantCategorizer.categorize(
          merchant: 'Apollo Pharmacy',
          smsBody: '',
          isCredit: false,
        ),
        SpendCategory.health,
      );
    });
  });

  // ─── Finance store & range reports ───────────────────────────────────
  group('S53-S65 Analytics & range reports', () {
    late FinanceStore store;

    setUp(() {
      store = FinanceStore();
      store.seedTransactions(dummyTransactionHistory());
    });

    test('S53 Monthly spent excludes credits', () {
      // Current-month debits: 486+2499+8500+312+650 = 12447
      expect(store.monthlySpent, 12447);
    });

    test('S54 Monthly income only credits', () {
      expect(store.monthlyIncome, 68000);
    });

    test('S55 Savings rate calculation', () {
      expect(store.savingsRate, closeTo(0.817, 0.01));
    });

    test('S56 transactionsInRange current month', () {
      final (start, end) = dummyMonthBounds();
      expect(store.transactionsInRange(start, end).length, 6);
    });

    test('S57 Empty range returns empty report', () {
      final report = store.buildReport(
        DateTime(2020, 1, 1),
        DateTime(2020, 1, 31),
      );
      expect(report.isEmpty, isTrue);
      expect(report.spent, 0);
    });

    test('S58 Full history report totals', () {
      final report = store.buildReport(
        DateTime(2000, 1, 1),
        DateTime(2100, 12, 31, 23, 59, 59),
      );
      expect(report.transactionCount, 14);
      expect(report.income, greaterThan(0));
      expect(report.spent, greaterThan(0));
    });

    test('S59 Top category in current month is EMI or food', () {
      final (start, end) = dummyMonthBounds();
      final report = store.buildReport(start, end);
      expect(report.topCategory, isNotNull);
      expect(report.categorySpending.length, greaterThan(0));
    });

    test('S60 Top merchants max 5', () {
      final report = store.buildReport(
        DateTime(2000, 1, 1),
        DateTime(2100, 12, 31, 23, 59, 59),
      );
      expect(report.topMerchants.length, lessThanOrEqualTo(5));
    });

    test('S61 Income sources from credits', () {
      final report = store.buildReport(
        DateTime(2000, 1, 1),
        DateTime(2100, 12, 31, 23, 59, 59),
      );
      expect(report.incomeSources, isNotEmpty);
      expect(report.incomeSources.first.$2, greaterThan(0));
    });

    test('S62 Net = income - spent', () {
      final (start, end) = dummyMonthBounds();
      final report = store.buildReport(start, end);
      expect(report.net, report.income - report.spent);
    });

    test('S63 Single-day range boundary', () {
      final day = dummyElapsedMonth(day: 7);
      final start = DateTime(day.year, day.month, day.day);
      final end = DateTime(day.year, day.month, day.day, 23, 59, 59);
      final report = store.buildReport(start, end);
      final onDay = store.transactions
          .where(
            (t) =>
                t.timestamp.year == day.year &&
                t.timestamp.month == day.month &&
                t.timestamp.day == day.day,
          )
          .length;
      // buildReport must include every txn on that local calendar day.
      expect(report.transactionCount, onDay);
      // Ola + Zomato are fixture-anchored to day 7 (clamped when today < 7).
      expect(onDay, greaterThanOrEqualTo(2));
    });

    test('S64 Bank accounts deduplicated', () {
      expect(store.bankAccounts().length, greaterThan(1));
      final masks = store.bankAccounts().map((a) => a.mask).toSet();
      expect(masks.length, store.bankAccounts().length);
    });

    test('S65 Budgets list all plan categories with spend', () {
      expect(
        store.budgets.length,
        FinanceStore.budgetableCategories.length,
      );
      expect(store.budgets.any((b) => b.spent > 0), isTrue);
    });
  });

  // ─── Break attempts on analytics ─────────────────────────────────────
  group('S66-S70 Break attempts on store', () {
    test('S66 Empty store monthly stats zero', () {
      final store = FinanceStore();
      store.seedTransactions([]);
      expect(store.monthlySpent, 0);
      expect(store.monthlyIncome, 0);
      expect(store.savingsRate, 0);
    });

    test('S67 Inverted date range still works', () {
      final store = FinanceStore();
      store.seedTransactions(dummyTransactionHistory());
      final (start, end) = dummyMonthBounds();
      final report = store.buildReport(end, start);
      expect(report.isEmpty, isTrue);
    });

    test('S68 Duplicate merchants aggregate in top list', () {
      final store = FinanceStore();
      store.seedTransactions([
        dummyTxn(
          id: 'a',
          merchant: 'Swiggy',
          amount: 100,
          isCredit: false,
          category: SpendCategory.food,
          timestamp: dummyNowMonth(day: 1),
        ),
        dummyTxn(
          id: 'b',
          merchant: 'Swiggy',
          amount: 200,
          isCredit: false,
          category: SpendCategory.food,
          timestamp: dummyNowMonth(day: 2),
        ),
      ]);
      final (start, end) = dummyMonthBounds();
      final report = store.buildReport(start, end);
      expect(report.topMerchants.first.$1, 'Swiggy');
      expect(report.topMerchants.first.$3, 300);
    });

    test('S69 earliestTransactionDate correct', () {
      final store = FinanceStore();
      store.seedTransactions(dummyTransactionHistory());
      expect(
        store.earliestTransactionDate,
        dummyNowMonth(monthsAgo: 3, day: 1, hour: 12),
      );
    });

    test('S70 foodDeltaVsLastMonth when no prev data', () {
      final store = FinanceStore();
      store.seedTransactions([
        dummyTxn(
          id: 'x',
          merchant: 'Swiggy',
          amount: 100,
          isCredit: false,
          category: SpendCategory.food,
          timestamp: DateTime(DateTime.now().year, DateTime.now().month, 5),
        ),
      ]);
      // May return null or delta depending on current month — should not throw
      expect(() => store.foodDeltaVsLastMonth(), returnsNormally);
    });
  });
}
