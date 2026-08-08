import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/data/sms_scan_state.dart';
import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/providers/finance_store.dart';
import 'package:paisa_app/services/sms/bank_promo_filters.dart';
import 'package:paisa_app/services/sms/merchant_categorizer.dart';
import 'package:paisa_app/services/sms/sms_parse_isolate.dart';
import 'package:paisa_app/services/sms/sms_parser.dart';
import 'package:paisa_app/services/sms/sms_reader_service.dart';
import 'package:paisa_app/services/sms/sms_scan_pipeline.dart';

import 'helpers/dummy_data.dart';

/// Diverse scenario suite T71+ — maximum variety across banks, types, and edges.
void main() {
  group('T71-T85 Multi-bank debit formats', () {
    test('T71 IDFC debit', () {
      final p = SmsParser.parse(dummySms(
        id: 't71',
        sender: 'IDFCFB',
        body: 'Rs.2,100.00 debited from a/c **7788 on 08-Jul-26. Info: BIGBASKET',
      ));
      expect(p?.amount, 2100);
      expect(p?.bank, 'IDFC');
    });

    test('T72 Yes Bank INR debit', () {
      final p = SmsParser.parse(dummySms(
        id: 't72',
        sender: 'YESBANK',
        body: 'INR 899.00 debited on 08-07-26. Info: MYNTRA',
      ));
      expect(p?.amount, 899);
      expect(p?.bank, 'Yes Bank');
    });

    test('T73 Canara Bank debit', () {
      expect(SmsScanPipeline.isFinancialSender('CANARA'), isTrue);
      final p = SmsParser.parse(dummySms(
        id: 't73',
        sender: 'CANARA',
        body: 'Rs.450.00 debited from a/c **1234 on 08-Jul-26. Info: METRO',
      ));
      expect(p?.amount, 450);
      expect(p?.bank, 'Canara');
    });

    test('T74 IndusInd towards merchant', () {
      expect(SmsScanPipeline.isFinancialSender('INDUSIND'), isTrue);
    });

    test('T75 BHIM UPI sender', () {
      expect(SmsScanPipeline.isFinancialSender('BHIM'), isTrue);
    });

    test('T76 Bank of Baroda body hint', () {
      expect(
        SmsScanPipeline.hasFinancialBodyHint(
          'Rs.300 debited from Bank of Baroda account on 08-Jul',
        ),
        isTrue,
      );
    });

    test('T77 Western comma format 1,250,000', () {
      final p = SmsParser.parse(dummySms(
        id: 't77',
        sender: 'HDFCBK',
        body:
            'Rs.1,250,000.00 debited from a/c **4321 on 08-Jul-26. Info: PROPERTY',
      ));
      expect(p?.amount, 1250000);
    });

    test('T78 ₹ with Indian lakh combo', () {
      final p = SmsParser.parse(dummySms(
        id: 't78',
        sender: 'HDFCBK',
        body: '₹12,500.00 debited from a/c **4321 on 08-Jul-26. Info: RENT',
      ));
      expect(p?.amount, 12500);
    });

    test('T79 Decimal amount Rs.99.99', () {
      final p = SmsParser.parse(dummySms(
        id: 't79',
        sender: 'PAYTM',
        body: 'Rs.99.99 paid to Tea Stall via Paytm on 08-Jul',
      ));
      expect(p?.amount, closeTo(99.99, 0.001));
    });

    test('T80 Sent Rs credit path not triggered on debit', () {
      final p = SmsParser.parse(dummySms(
        id: 't80',
        sender: 'VM-HDFCBK',
        body: 'Sent Rs.50.00 from a/c **4321 to Ola on 08-Jul-26 UPI ref 99',
      ));
      expect(p?.isCredit, false);
    });

    test('T81 Generic VM sender with body bank hint', () {
      final p = SmsParser.parse(dummySms(
        id: 't81',
        sender: 'VM-ABC123',
        body:
            'Rs.1,200.00 debited from your ICICI Bank account on 08-Jul. Info: IRCTC',
      ));
      expect(p?.amount, 1200);
    });

    test('T82 Federal Bank sender', () {
      expect(SmsScanPipeline.isFinancialSender('FEDERAL'), isTrue);
    });

    test('T83 PNB sender fragment', () {
      expect(SmsScanPipeline.isFinancialSender('PNBSMS'), isTrue);
    });

    test('T84 Google Pay body hint', () {
      expect(
        SmsScanPipeline.hasFinancialBodyHint('Google Pay transaction of Rs.100'),
        isTrue,
      );
    });

    test('T85 NEFT keyword in body', () {
      expect(
        SmsScanPipeline.hasFinancialBodyHint('NEFT transaction ref 12345'),
        isTrue,
      );
    });
  });

  group('T86-T95 Credit & income variety', () {
    test('T86 Salary credit', () {
      final p = SmsParser.parse(dummySms(
        id: 't86',
        sender: 'HDFCBK',
        body: 'Rs. 75000.00 credited to your a/c **4321 on 01-Jul-26',
      ));
      expect(p?.isCredit, true);
      expect(p?.amount, 75000);
    });

    test('T87 credited with Rs format', () {
      final p = SmsParser.parse(dummySms(
        id: 't87',
        sender: 'SBIINB',
        body: 'Your account credited with Rs. 1500.00 on 08-Jul-26',
      ));
      expect(p?.isCredit, true);
    });

    test('T88 received Rs credit', () {
      final p = SmsParser.parse(dummySms(
        id: 't88',
        sender: 'AXISBK',
        body: 'You received Rs.2500 in your account on 08-Jul-26',
      ));
      expect(p?.isCredit, true);
      expect(p?.amount, 2500);
    });

    test('T89 Credit categorised as income', () {
      final cat = MerchantCategorizer.categorize(
        merchant: 'Employer Pvt Ltd',
        smsBody: 'salary credited to account',
        isCredit: true,
      );
      expect(cat, SpendCategory.income);
    });

    test('T90 Refund credit as income', () {
      final cat = MerchantCategorizer.categorize(
        merchant: 'Amazon',
        smsBody: 'refund credited',
        isCredit: true,
      );
      expect(cat, SpendCategory.income);
    });

    test('T91 Credit does not categorise as food', () {
      final cat = MerchantCategorizer.categorize(
        merchant: 'Swiggy',
        smsBody: 'credited by Swiggy refund',
        isCredit: true,
      );
      expect(cat, SpendCategory.income);
    });

    test('T92 Large credit ₹10,00,000 lakh format', () {
      final p = SmsParser.parse(dummySms(
        id: 't92',
        sender: 'HDFCBK',
        body: 'Rs.10,00,000.00 credited to your a/c **4321 on 08-Jul-26',
      ));
      expect(p?.amount, 1000000);
      expect(p?.isCredit, true);
    });

    test('T93 INR credit to account', () {
      final p = SmsParser.parse(dummySms(
        id: 't93',
        sender: 'ICICIT',
        body: 'INR 5000.00 credited to your a/c **1234 on 08-Jul-26',
      ));
      expect(p?.isCredit, true);
    });

    test('T94 Pipeline credit txn signal', () {
      final r = SmsScanPipeline.process(dummySms(
        id: 't94',
        sender: 'AXISBK',
        body: 'Rs. 68000.00 credited to your a/c **2015 on 01-Jul-26',
      ));
      expect(r.isParsed, isTrue);
      expect(r.transaction?.isCredit, true);
    });

    test('T95 Net positive when income exceeds spend in report', () {
      final store = FinanceStore();
      store.seedTransactions([
        dummyTxn(
          id: 'a',
          merchant: 'Salary',
          amount: 50000,
          isCredit: true,
          category: SpendCategory.income,
          timestamp: DateTime(2026, 6, 1),
        ),
        dummyTxn(
          id: 'b',
          merchant: 'Rent',
          amount: 15000,
          isCredit: false,
          category: SpendCategory.other,
          timestamp: DateTime(2026, 6, 5),
        ),
      ]);
      final report = store.buildReport(
        DateTime(2026, 6, 1),
        DateTime(2026, 6, 30, 23, 59, 59),
      );
      expect(report.net, greaterThan(0));
    });
  });

  group('T96-T105 Promo & rejection variety', () {
    test('T96 ICICI Coral promo blocked', () {
      expect(
        BankPromoFilters.matchesBankPromo(
          sender: 'ICICIT',
          body: 'ICICI Coral offer on credit card. Apply today.',
        ),
        isTrue,
      );
    });

    test('T97 Axis Flipkart card promo', () {
      expect(
        BankPromoFilters.matchesBankPromo(
          sender: 'AXISBK',
          body: 'Flipkart Axis offer! Earn 5X rewards on your card.',
        ),
        isTrue,
      );
    });

    test('T98 ICICI iMobile offer promo', () {
      expect(
        SmsParser.parse(dummySms(
          id: 't98',
          sender: 'ICICIT',
          body: 'ICICI Bank iMobile offer: get Amazon Pay ICICI card today.',
        )),
        isNull,
      );
    });

    test('T99 Cashback offer from Paytm', () {
      expect(
        SmsParser.parse(dummySms(
          id: 't99',
          sender: 'PAYTM',
          body: 'Paytm cashback offer! Get Rs.50 on next recharge.',
        )),
        isNull,
      );
    });

    test('T100 Flipkart delivery not financial', () {
      final r = SmsScanPipeline.process(dummySms(
        id: 't100',
        sender: 'FLPKRT',
        body: 'Your Flipkart order ORD123 has been shipped. Track on app.',
      ));
      expect(r.outcome, SmsPipelineOutcome.notFinancialSender);
    });

    test('T101 Airtel promo without txn', () {
      expect(
        SmsParser.parse(dummySms(
          id: 't101',
          sender: 'AIRTEL',
          body: 'Airtel thanks you! Recharge now and get 2GB extra data offer.',
        )),
        isNull,
      );
    });

    test('T102 Pipeline promo outcome explicit', () {
      final r = SmsScanPipeline.process(dummySms(
        id: 't102',
        sender: 'HDFCBK',
        body:
            'Pre-approved loan of Rs.3,00,000 on your HDFC account. Apply now. T&C apply.',
      ));
      expect(r.outcome, SmsPipelineOutcome.promo);
    });

    test('T103 Verification code OTP', () {
      final r = SmsScanPipeline.process(dummySms(
        id: 't103',
        sender: 'HDFCBK',
        body:
            'Your verification code for HDFC NetBanking is 847291. Do not share.',
      ));
      expect(r.outcome, SmsPipelineOutcome.otpOnly);
    });

    test('T104 Personal WhatsApp style chat', () {
      final r = SmsScanPipeline.process(dummySms(
        id: 't104',
        sender: '+919876543210',
        body: 'Bro send me the photos from yesterday party please thanks',
      ));
      expect(r.outcome, SmsPipelineOutcome.notFinancialSender);
    });

    test('T105 Marketing without bank sender', () {
      expect(
        SmsScanPipeline.passesFinancialGate(
          'PROMO',
          'Sale! 50% off on all items this weekend only!',
        ),
        isFalse,
      );
    });
  });

  group('T106-T115 Categorization variety', () {
    test('T106 Blinkit → food', () {
      expect(
        MerchantCategorizer.categorize(
          merchant: 'Blinkit',
          smsBody: '',
          isCredit: false,
        ),
        SpendCategory.food,
      );
    });

    test('T107 Zepto → food', () {
      expect(
        MerchantCategorizer.categorize(
          merchant: 'Zepto',
          smsBody: '',
          isCredit: false,
        ),
        SpendCategory.food,
      );
    });

    test('T108 MakeMyTrip → travel', () {
      expect(
        MerchantCategorizer.categorize(
          merchant: 'MakeMyTrip',
          smsBody: '',
          isCredit: false,
        ),
        SpendCategory.travel,
      );
    });

    test('T109 BookMyShow → entertainment', () {
      expect(
        MerchantCategorizer.categorize(
          merchant: 'BookMyShow',
          smsBody: '',
          isCredit: false,
        ),
        SpendCategory.entertainment,
      );
    });

    test('T110 Practo → health', () {
      expect(
        MerchantCategorizer.categorize(
          merchant: 'Practo',
          smsBody: '',
          isCredit: false,
        ),
        SpendCategory.health,
      );
    });

    test('T111 Nykaa → shopping', () {
      expect(
        MerchantCategorizer.categorize(
          merchant: 'Nykaa',
          smsBody: '',
          isCredit: false,
        ),
        SpendCategory.shopping,
      );
    });

    test('T112 FASTag → travel', () {
      expect(
        MerchantCategorizer.categorize(
          merchant: 'FASTag',
          smsBody: 'fastag toll debit',
          isCredit: false,
        ),
        SpendCategory.travel,
      );
    });

    test('T113 NEFT transfer debit', () {
      expect(
        MerchantCategorizer.categorize(
          merchant: 'Transfer',
          smsBody: 'neft dr to account',
          isCredit: false,
        ),
        SpendCategory.transfer,
      );
    });

    test('T114 Spotify → entertainment', () {
      expect(
        MerchantCategorizer.categorize(
          merchant: 'Spotify',
          smsBody: '',
          isCredit: false,
        ),
        SpendCategory.entertainment,
      );
    });

    test('T115 PharmEasy → health', () {
      expect(
        MerchantCategorizer.categorize(
          merchant: 'PharmEasy',
          smsBody: '',
          isCredit: false,
        ),
        SpendCategory.health,
      );
    });
  });

  group('T116-T125 Reports & analytics variety', () {
    late FinanceStore store;

    setUp(() {
      store = FinanceStore();
      store.seedTransactions(dummyTransactionHistory());
    });

    test('T116 prior-month-only report', () {
      final (start, end) = dummyMonthBounds(monthsAgo: 1);
      final report = store.buildReport(start, end);
      expect(report.transactionCount, 3);
      expect(report.spent, 649 + 299);
    });

    test('T117 two-months-ago report includes ATM', () {
      final (start, end) = dummyMonthBounds(monthsAgo: 2);
      final report = store.buildReport(start, end);
      expect(report.categorySpending.containsKey(SpendCategory.atm), isTrue);
    });

    test('T118 prior three months report (excl. current)', () {
      final (start, _) = dummyMonthBounds(monthsAgo: 3);
      final (_, end) = dummyMonthBounds(monthsAgo: 1);
      final report = store.buildReport(start, end);
      expect(report.transactionCount, 8);
      expect(report.income, greaterThan(0));
    });

    test('T119 Savings rate capped at 100%', () {
      final store = FinanceStore();
      store.seedTransactions([
        dummyTxn(
          id: 'i',
          merchant: 'Salary',
          amount: 10000,
          isCredit: true,
          category: SpendCategory.income,
          timestamp: dummyNowMonth(day: 1),
        ),
        dummyTxn(
          id: 'd',
          merchant: 'Tea',
          amount: 50,
          isCredit: false,
          category: SpendCategory.food,
          timestamp: dummyNowMonth(day: 2),
        ),
      ]);
      expect(store.savingsRate, lessThanOrEqualTo(1.0));
    });

    test('T120 Daily average for current month', () {
      final (start, end) = dummyMonthBounds();
      final report = store.buildReport(start, end);
      expect(report.dailyAverage, greaterThan(0));
    });

    test('T121 Highest day spend positive', () {
      final (start, end) = dummyMonthBounds();
      final report = store.buildReport(start, end);
      expect(report.highestDaySpend, greaterThan(0));
    });

    test('T122 Income sources sorted descending', () {
      final report = store.buildReport(
        DateTime(2000, 1, 1),
        DateTime(2100, 12, 31, 23, 59, 59),
      );
      if (report.incomeSources.length >= 2) {
        expect(
          report.incomeSources[0].$2,
          greaterThanOrEqualTo(report.incomeSources[1].$2),
        );
      }
    });

    test('T123 Category spending sorted high to low', () {
      final (start, end) = dummyMonthBounds();
      final report = store.buildReport(start, end);
      final values = report.categorySpending.values.toList();
      for (var i = 0; i < values.length - 1; i++) {
        expect(values[i], greaterThanOrEqualTo(values[i + 1]));
      }
    });

    test('T124 earliest-month bonus credit in income sources', () {
      final (start, end) = dummyMonthBounds(monthsAgo: 3);
      final report = store.buildReport(start, end);
      expect(report.income, 15000);
    });

    test('T125 Empty store report', () {
      final empty = FinanceStore();
      empty.seedTransactions([]);
      final report = empty.buildReport(
        DateTime(2026, 7, 1),
        DateTime(2026, 7, 31),
      );
      expect(report.isEmpty, isTrue);
      expect(report.topCategory, isNull);
    });
  });

  group('T126-T135 Isolate batch & scan options', () {
    test('T126 Isolate parses batch of 5 SMS', () async {
      final hits = await parseCandidatesInIsolate([
        {
          'id': '1',
          'sender': 'HDFCBK',
          'body': 'Rs.100.00 debited from a/c **4321 on 08-Jul. Info: SWIGGY',
          'timestampMs': DateTime(2026, 7, 8).millisecondsSinceEpoch,
        },
        {
          'id': '2',
          'sender': 'SBIINB',
          'body': 'Rs.200.00 debited from A/c XX1234 on 08Jul26. Info: AMAZON',
          'timestampMs': DateTime(2026, 7, 8).millisecondsSinceEpoch,
        },
        {
          'id': '3',
          'sender': 'AXISBK',
          'body': 'Rs. 5000 credited to your a/c **2015 on 08-Jul-26',
          'timestampMs': DateTime(2026, 7, 8).millisecondsSinceEpoch,
        },
        {
          'id': '4',
          'sender': 'FRIEND',
          'body': 'Hey are we meeting for lunch tomorrow at noon?',
          'timestampMs': DateTime(2026, 7, 8).millisecondsSinceEpoch,
        },
        {
          'id': '5',
          'sender': 'HDFCBK',
          'body': 'Pre-approved loan Rs.5,00,000. Apply now on HDFC Bank.',
          'timestampMs': DateTime(2026, 7, 8).millisecondsSinceEpoch,
        },
      ]);
      expect(hits.length, 3);
    });

    test('T127 SmsScanOptions default 24 month window', () {
      final since = SmsScanOptions.defaultSinceMs(months: 24);
      expect(since, lessThan(DateTime.now().millisecondsSinceEpoch));
    });

    test('T128 Incremental scan options from completed state', () {
      final reader = SmsReaderService();
      final opts = reader.optionsFromState(
        const SmsScanState(
          fullScanComplete: true,
          lastScanAt: null,
        ),
      );
      expect(opts.incremental, isTrue);
    });

    test('T129 Resume scan options from interrupted state', () {
      final reader = SmsReaderService();
      final opts = reader.optionsFromState(
        const SmsScanState(
          fullScanComplete: false,
          resumeOffset: 1500,
        ),
      );
      expect(opts.resumeOffset, 1500);
      expect(opts.incremental, isFalse);
    });

    test('T130 Masked account format', () {
      final p = SmsParser.parse(dummySms(
        id: 't130',
        sender: 'HDFCBK',
        body: 'Sent Rs.10.00 from a/c **9876 to Test on 08-Jul UPI',
      ));
      expect(p?.maskedAccount, '••••9876');
    });

    test('T131 Merchant cleaned from UPI to prefix', () {
      final p = SmsParser.parse(dummySms(
        id: 't131',
        sender: 'HDFCBK',
        body: 'Sent Rs.50.00 from a/c **4321 to Zomato on 08-Jul-26 UPI ref',
      ));
      expect(p?.merchant.toLowerCase(), contains('zomato'));
    });

    test('T132 Timestamp preserved from message', () {
      final ts = DateTime(2025, 12, 25, 10, 30);
      final p = SmsParser.parse(dummySms(
        id: 't132',
        sender: 'HDFCBK',
        body: 'Rs.100.00 debited from a/c **4321 on 25-Dec-25. Info: GIFT',
        timestamp: ts,
      ));
      expect(p?.timestamp, ts);
    });

    test('T133 Detect bank from body when sender generic', () {
      final p = SmsParser.parse(dummySms(
        id: 't133',
        sender: 'VM-XXXXX',
        body:
            'Axis Bank: INR 400.00 debited on 08-07-26. Info: METRO',
      ));
      expect(p?.bank, 'Axis');
    });

    test('T134 Pipeline parseFailed for balance-only bank SMS', () {
      final r = SmsScanPipeline.process(dummySms(
        id: 't134',
        sender: 'HDFCBK',
        body:
            'Dear Customer, your HDFC Bank account balance is healthy. Visit branch for details.',
      ));
      expect(r.outcome, SmsPipelineOutcome.noTransactionSignal);
    });

    test('T135 Parse failed for ambiguous bank SMS', () {
      final r = SmsScanPipeline.process(dummySms(
        id: 't135',
        sender: 'HDFCBK',
        body:
            'HDFC Bank: Your account has been updated successfully. Call us for help.',
      ));
      expect(r.outcome, isNot(SmsPipelineOutcome.parsed));
    });
  });
}
