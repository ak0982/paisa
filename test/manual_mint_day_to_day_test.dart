import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/data/transaction_database.dart';
import 'package:paisa_app/models/category_info.dart';
import 'package:paisa_app/models/manual_transaction.dart';
import 'package:paisa_app/models/transaction.dart' as models;
import 'package:paisa_app/providers/finance_store.dart';
import 'package:paisa_app/services/sms/account_discovery.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Day-to-day Indian cash situations for Add / Mint move.
///
/// Each [_MintCase] expands to its own `test(...)` so the runner reports
/// distinct scenario names (chai, maid salary, temple donation, …).
void main() {
  late Directory tmp;
  var seq = 0;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('paisa_mint_day');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  TransactionDatabase freshDb() => TransactionDatabase.forTesting(
        '${tmp.path}/paisa_${seq++}.db',
      );

  FinanceStore freshStore(TransactionDatabase db) => FinanceStore(database: db);

  /// Fixed "now" so backdated noon stamps stay deterministic.
  final now = DateTime(2026, 8, 27, 15, 30);

  Future<models.Transaction> mint(
    FinanceStore store, {
    required double amount,
    required SpendCategory category,
    required String message,
    required bool isCredit,
    DateTime? date,
  }) {
    return store.addManualTransaction(
      amount: amount,
      date: date ?? DateTime(2026, 8, 20),
      category: category,
      message: message,
      isCredit: isCredit,
      now: now,
    );
  }

  group('India day-to-day cash mints', () {
    for (final c in _dayToDayCases) {
      test(c.name, () async {
        final db = freshDb();
        final store = freshStore(db);
        await store.init();

        final tx = await mint(
          store,
          amount: c.amount,
          category: c.category,
          message: c.message,
          isCredit: c.isCredit,
          date: c.date,
        );

        expect(tx.id.startsWith('manual_'), isTrue);
        expect(tx.source, kManualSource);
        expect(tx.smsId, isNull);
        expect(tx.bank, 'Cash');
        expect(tx.maskedAccount, isEmpty);
        expect(tx.amount, closeTo(c.amount, 0.001));
        expect(tx.category, c.category);
        expect(tx.isCredit, c.isCredit);
        expect(tx.merchant, c.message);
        expect(tx.isManual, isTrue);
        expect(tx.accountKind, AccountKind.savings);
        expect(store.bankAccounts(), isEmpty);

        final day = store.transactionsForDay(c.date ?? DateTime(2026, 8, 20));
        expect(day.any((t) => t.id == tx.id), isTrue);
      });
    }
  });

  group('category mix — every SpendCategory via lifestyle mints', () {
    final byCategory = <SpendCategory, _MintCase>{};
    for (final c in _dayToDayCases) {
      byCategory.putIfAbsent(c.category, () => c);
    }

    test('day-to-day corpus covers all SpendCategory values', () {
      expect(byCategory.keys.toSet(), SpendCategory.values.toSet());
    });

    for (final category in SpendCategory.values) {
      test('at least one mint lands in $category', () async {
        final c = byCategory[category]!;
        final store = freshStore(freshDb());
        await store.init();
        final tx = await mint(
          store,
          amount: c.amount,
          category: c.category,
          message: c.message,
          isCredit: c.isCredit,
        );
        expect(tx.category, category);
        expect(defaultManualIsCredit(category), category == SpendCategory.income);
      });
    }
  });

  group('same-day multi-mint lifestyle stack', () {
    test('chai + auto + vada pav same morning order by add time (today)',
        () async {
      final clock = DateTime(2026, 8, 27, 9, 0);
      final store = freshStore(freshDb());
      await store.init();

      final chai = await store.addManualTransaction(
        amount: 20,
        date: clock,
        category: SpendCategory.food,
        message: 'Cutting chai',
        isCredit: false,
        now: clock,
      );
      final auto = await store.addManualTransaction(
        amount: 80,
        date: clock,
        category: SpendCategory.travel,
        message: 'Auto to office',
        isCredit: false,
        now: clock.add(const Duration(minutes: 12)),
      );
      final snack = await store.addManualTransaction(
        amount: 40,
        date: clock,
        category: SpendCategory.food,
        message: 'Vada pav stall',
        isCredit: false,
        now: clock.add(const Duration(minutes: 25)),
      );

      final day = store.transactionsForDay(clock);
      expect(day.map((t) => t.id).toList(), [chai.id, auto.id, snack.id]);
      expect(store.daySpend(clock), closeTo(140, 0.001));
    });

    test('wedding gift In + sweets Out same day net', () async {
      final day = DateTime(2026, 8, 15);
      final store = freshStore(freshDb());
      await store.init();

      await mint(
        store,
        amount: 2100,
        category: SpendCategory.income,
        message: 'Wedding gift cash',
        isCredit: true,
        date: day,
      );
      await mint(
        store,
        amount: 350,
        category: SpendCategory.food,
        message: 'Mithai box',
        isCredit: false,
        date: day,
      );

      expect(store.dayIncome(day), 2100);
      expect(store.daySpend(day), 350);
      expect(store.dayNet(day), 1750);
    });
  });
}

class _MintCase {
  _MintCase({
    required this.name,
    required this.amount,
    required this.category,
    required this.message,
    required this.isCredit,
    this.date,
  });

  final String name;
  final double amount;
  final SpendCategory category;
  final String message;
  final bool isCredit;
  final DateTime? date;
}

/// ~140 distinct India-flavored cash situations.
final _dayToDayCases = <_MintCase>[
  // —— Food ——
  _MintCase(
    name: 'cutting chai ₹20',
    amount: 20,
    category: SpendCategory.food,
    message: 'Cutting chai',
    isCredit: false,
  ),
  _MintCase(
    name: 'filter coffee ₹35',
    amount: 35,
    category: SpendCategory.food,
    message: 'Filter coffee',
    isCredit: false,
  ),
  _MintCase(
    name: 'vada pav stall ₹40',
    amount: 40,
    category: SpendCategory.food,
    message: 'Vada pav stall',
    isCredit: false,
  ),
  _MintCase(
    name: 'pani puri plate ₹60',
    amount: 60,
    category: SpendCategory.food,
    message: 'Pani puri',
    isCredit: false,
  ),
  _MintCase(
    name: 'samosa + chai ₹45',
    amount: 45,
    category: SpendCategory.food,
    message: 'Samosa chai',
    isCredit: false,
  ),
  _MintCase(
    name: 'dosa breakfast ₹120',
    amount: 120,
    category: SpendCategory.food,
    message: 'Dosa breakfast',
    isCredit: false,
  ),
  _MintCase(
    name: 'office canteen thali ₹90',
    amount: 90,
    category: SpendCategory.food,
    message: 'Canteen thali',
    isCredit: false,
  ),
  _MintCase(
    name: 'biryani parcel ₹280',
    amount: 280,
    category: SpendCategory.food,
    message: 'Biryani parcel',
    isCredit: false,
  ),
  _MintCase(
    name: 'late night Maggi ₹50',
    amount: 50,
    category: SpendCategory.food,
    message: 'Late Maggi',
    isCredit: false,
  ),
  _MintCase(
    name: 'sugarcane juice ₹40',
    amount: 40,
    category: SpendCategory.food,
    message: 'Ganne ka juice',
    isCredit: false,
  ),
  _MintCase(
    name: 'chaat corner ₹80',
    amount: 80,
    category: SpendCategory.food,
    message: 'Chaat corner',
    isCredit: false,
  ),
  _MintCase(
    name: 'kebab roll ₹150',
    amount: 150,
    category: SpendCategory.food,
    message: 'Kebab roll',
    isCredit: false,
  ),
  _MintCase(
    name: 'mithai for guests ₹450',
    amount: 450,
    category: SpendCategory.food,
    message: 'Mithai box',
    isCredit: false,
  ),
  _MintCase(
    name: 'tiffin dabba cash ₹2000',
    amount: 2000,
    category: SpendCategory.food,
    message: 'Tiffin monthly',
    isCredit: false,
  ),
  _MintCase(
    name: 'Irani bakery bun maska ₹70',
    amount: 70,
    category: SpendCategory.food,
    message: 'Bun maska',
    isCredit: false,
  ),
  _MintCase(
    name: 'South Indian mess ₹180',
    amount: 180,
    category: SpendCategory.food,
    message: 'Mess lunch',
    isCredit: false,
  ),
  _MintCase(
    name: 'paan after dinner ₹20',
    amount: 20,
    category: SpendCategory.food,
    message: 'Paan',
    isCredit: false,
  ),
  _MintCase(
    name: 'ice gola summer ₹30',
    amount: 30,
    category: SpendCategory.food,
    message: 'Ice gola',
    isCredit: false,
  ),
  _MintCase(
    name: 'Sunday breakfast restaurant ₹650',
    amount: 650,
    category: SpendCategory.food,
    message: 'Sunday breakfast',
    isCredit: false,
  ),
  _MintCase(
    name: 'split dinner cash share ₹420',
    amount: 420,
    category: SpendCategory.food,
    message: 'Split dinner share',
    isCredit: false,
  ),

  // —— Travel ——
  _MintCase(
    name: 'auto rickshaw ₹80',
    amount: 80,
    category: SpendCategory.travel,
    message: 'Auto rickshaw',
    isCredit: false,
  ),
  _MintCase(
    name: 'shared auto ₹25',
    amount: 25,
    category: SpendCategory.travel,
    message: 'Shared auto',
    isCredit: false,
  ),
  _MintCase(
    name: 'petrol cash fill ₹500',
    amount: 500,
    category: SpendCategory.travel,
    message: 'Petrol cash',
    isCredit: false,
  ),
  _MintCase(
    name: 'parking mall ₹40',
    amount: 40,
    category: SpendCategory.travel,
    message: 'Mall parking',
    isCredit: false,
  ),
  _MintCase(
    name: 'toll plaza cash ₹95',
    amount: 95,
    category: SpendCategory.travel,
    message: 'Toll cash',
    isCredit: false,
  ),
  _MintCase(
    name: 'metro token cash ₹50',
    amount: 50,
    category: SpendCategory.travel,
    message: 'Metro token',
    isCredit: false,
  ),
  _MintCase(
    name: 'local train ticket ₹15',
    amount: 15,
    category: SpendCategory.travel,
    message: 'Local train',
    isCredit: false,
  ),
  _MintCase(
    name: 'cab tip cash ₹50',
    amount: 50,
    category: SpendCategory.travel,
    message: 'Cab tip',
    isCredit: false,
  ),
  _MintCase(
    name: 'bike puncture repair ₹80',
    amount: 80,
    category: SpendCategory.travel,
    message: 'Puncture repair',
    isCredit: false,
  ),
  _MintCase(
    name: 'bus ticket interstate ₹320',
    amount: 320,
    category: SpendCategory.travel,
    message: 'Bus ticket',
    isCredit: false,
  ),
  _MintCase(
    name: 'airport porter tip ₹100',
    amount: 100,
    category: SpendCategory.travel,
    message: 'Porter tip',
    isCredit: false,
  ),
  _MintCase(
    name: 'e-rickshaw last mile ₹30',
    amount: 30,
    category: SpendCategory.travel,
    message: 'E-rickshaw',
    isCredit: false,
  ),
  _MintCase(
    name: 'CNG fill cash ₹400',
    amount: 400,
    category: SpendCategory.travel,
    message: 'CNG cash',
    isCredit: false,
  ),
  _MintCase(
    name: 'valet parking ₹100',
    amount: 100,
    category: SpendCategory.travel,
    message: 'Valet parking',
    isCredit: false,
  ),

  // —— Shopping ——
  _MintCase(
    name: 'kirana ration bag ₹850',
    amount: 850,
    category: SpendCategory.shopping,
    message: 'Kirana ration',
    isCredit: false,
  ),
  _MintCase(
    name: 'vegetable vendor ₹180',
    amount: 180,
    category: SpendCategory.shopping,
    message: 'Sabziwala',
    isCredit: false,
  ),
  _MintCase(
    name: 'fruitwala ₹120',
    amount: 120,
    category: SpendCategory.shopping,
    message: 'Fruitwala',
    isCredit: false,
  ),
  _MintCase(
    name: 'flower vendor ₹50',
    amount: 50,
    category: SpendCategory.shopping,
    message: 'Phoolwala',
    isCredit: false,
  ),
  _MintCase(
    name: 'Diwali festival shopping ₹3500',
    amount: 3500,
    category: SpendCategory.shopping,
    message: 'Diwali shopping',
    isCredit: false,
  ),
  _MintCase(
    name: 'Holi colors + pichkari ₹250',
    amount: 250,
    category: SpendCategory.shopping,
    message: 'Holi colors',
    isCredit: false,
  ),
  _MintCase(
    name: 'clothes bazaar kurta ₹799',
    amount: 799,
    category: SpendCategory.shopping,
    message: 'Kurta bazaar',
    isCredit: false,
  ),
  _MintCase(
    name: 'stationery shop ₹95',
    amount: 95,
    category: SpendCategory.shopping,
    message: 'Stationery',
    isCredit: false,
  ),
  _MintCase(
    name: 'mobile recharge voucher cash ₹199',
    amount: 199,
    category: SpendCategory.shopping,
    message: 'Recharge voucher',
    isCredit: false,
  ),
  _MintCase(
    name: 'hardware store screws ₹60',
    amount: 60,
    category: SpendCategory.shopping,
    message: 'Hardware store',
    isCredit: false,
  ),
  _MintCase(
    name: 'book stall used ₹150',
    amount: 150,
    category: SpendCategory.shopping,
    message: 'Used books',
    isCredit: false,
  ),
  _MintCase(
    name: 'jewellery polishing cash ₹300',
    amount: 300,
    category: SpendCategory.shopping,
    message: 'Jewellery polish',
    isCredit: false,
  ),

  // —— Bills / household ——
  _MintCase(
    name: 'maid salary cash ₹6000',
    amount: 6000,
    category: SpendCategory.bills,
    message: 'Maid salary',
    isCredit: false,
  ),
  _MintCase(
    name: 'cook salary cash ₹4500',
    amount: 4500,
    category: SpendCategory.bills,
    message: 'Cook salary',
    isCredit: false,
  ),
  _MintCase(
    name: 'milkman weekly ₹420',
    amount: 420,
    category: SpendCategory.bills,
    message: 'Milkman',
    isCredit: false,
  ),
  _MintCase(
    name: 'newspaper wallah ₹150',
    amount: 150,
    category: SpendCategory.bills,
    message: 'Newspaper',
    isCredit: false,
  ),
  _MintCase(
    name: 'electricity cash counter ₹1850',
    amount: 1850,
    category: SpendCategory.bills,
    message: 'Electricity cash',
    isCredit: false,
  ),
  _MintCase(
    name: 'water tanker cash ₹800',
    amount: 800,
    category: SpendCategory.bills,
    message: 'Water tanker',
    isCredit: false,
  ),
  _MintCase(
    name: 'wifi cash top-up ₹699',
    amount: 699,
    category: SpendCategory.bills,
    message: 'Wifi cash',
    isCredit: false,
  ),
  _MintCase(
    name: 'rent portion cash ₹5000',
    amount: 5000,
    category: SpendCategory.bills,
    message: 'Rent portion cash',
    isCredit: false,
  ),
  _MintCase(
    name: 'society maintenance cash ₹1200',
    amount: 1200,
    category: SpendCategory.bills,
    message: 'Society maintenance',
    isCredit: false,
  ),
  _MintCase(
    name: 'gas cylinder booking cash ₹1100',
    amount: 1100,
    category: SpendCategory.bills,
    message: 'Gas cylinder',
    isCredit: false,
  ),
  _MintCase(
    name: 'school fees cash ₹8500',
    amount: 8500,
    category: SpendCategory.bills,
    message: 'School fees cash',
    isCredit: false,
  ),
  _MintCase(
    name: 'tuition teacher cash ₹2000',
    amount: 2000,
    category: SpendCategory.bills,
    message: 'Tuition fees',
    isCredit: false,
  ),

  // —— Entertainment ——
  _MintCase(
    name: 'movie ticket cash ₹250',
    amount: 250,
    category: SpendCategory.entertainment,
    message: 'Movie ticket',
    isCredit: false,
  ),
  _MintCase(
    name: 'cricket ground snacks ₹180',
    amount: 180,
    category: SpendCategory.entertainment,
    message: 'Stadium snacks',
    isCredit: false,
  ),
  _MintCase(
    name: 'board game cafe ₹400',
    amount: 400,
    category: SpendCategory.entertainment,
    message: 'Board game cafe',
    isCredit: false,
  ),
  _MintCase(
    name: 'arcade tokens ₹200',
    amount: 200,
    category: SpendCategory.entertainment,
    message: 'Arcade tokens',
    isCredit: false,
  ),
  _MintCase(
    name: 'concert merch cash ₹500',
    amount: 500,
    category: SpendCategory.entertainment,
    message: 'Concert merch',
    isCredit: false,
  ),
  _MintCase(
    name: 'temple fair rides ₹100',
    amount: 100,
    category: SpendCategory.entertainment,
    message: 'Mela rides',
    isCredit: false,
  ),
  _MintCase(
    name: 'picnic park entry ₹50',
    amount: 50,
    category: SpendCategory.entertainment,
    message: 'Park entry',
    isCredit: false,
  ),

  // —— Health ——
  _MintCase(
    name: 'pharmacy medicine ₹340',
    amount: 340,
    category: SpendCategory.health,
    message: 'Pharmacy medicine',
    isCredit: false,
  ),
  _MintCase(
    name: 'GP consultation cash ₹500',
    amount: 500,
    category: SpendCategory.health,
    message: 'Doctor consult',
    isCredit: false,
  ),
  _MintCase(
    name: 'dentist cleaning cash ₹1500',
    amount: 1500,
    category: SpendCategory.health,
    message: 'Dentist',
    isCredit: false,
  ),
  _MintCase(
    name: 'spectacles repair ₹250',
    amount: 250,
    category: SpendCategory.health,
    message: 'Specs repair',
    isCredit: false,
  ),
  _MintCase(
    name: 'lab test cash ₹800',
    amount: 800,
    category: SpendCategory.health,
    message: 'Lab test',
    isCredit: false,
  ),
  _MintCase(
    name: 'physiotherapy session ₹700',
    amount: 700,
    category: SpendCategory.health,
    message: 'Physio session',
    isCredit: false,
  ),
  _MintCase(
    name: 'ayurvedic clinic ₹450',
    amount: 450,
    category: SpendCategory.health,
    message: 'Ayurvedic clinic',
    isCredit: false,
  ),

  // —— EMI / ATM / Transfer ——
  _MintCase(
    name: 'cash EMI installment ₹3500',
    amount: 3500,
    category: SpendCategory.emi,
    message: 'Cash EMI',
    isCredit: false,
  ),
  _MintCase(
    name: 'gold loan EMI cash ₹2200',
    amount: 2200,
    category: SpendCategory.emi,
    message: 'Gold loan EMI',
    isCredit: false,
  ),
  _MintCase(
    name: 'ATM cash withdrawn tracked ₹2000',
    amount: 2000,
    category: SpendCategory.atm,
    message: 'ATM cash out',
    isCredit: false,
  ),
  _MintCase(
    name: 'ATM small withdrawal ₹500',
    amount: 500,
    category: SpendCategory.atm,
    message: 'ATM ₹500',
    isCredit: false,
  ),
  _MintCase(
    name: 'repay friend cash ₹1000',
    amount: 1000,
    category: SpendCategory.transfer,
    message: 'Repay friend',
    isCredit: false,
  ),
  _MintCase(
    name: 'send parents cash via courier ₹5000',
    amount: 5000,
    category: SpendCategory.transfer,
    message: 'Cash to parents',
    isCredit: false,
  ),
  _MintCase(
    name: 'lend roommate cash ₹800',
    amount: 800,
    category: SpendCategory.transfer,
    message: 'Lend roommate',
    isCredit: false,
  ),

  // —— Income (In) ——
  _MintCase(
    name: 'wedding gift cash received ₹5100',
    amount: 5100,
    category: SpendCategory.income,
    message: 'Wedding gift cash',
    isCredit: true,
  ),
  _MintCase(
    name: 'birthday cash gift ₹2001',
    amount: 2001,
    category: SpendCategory.income,
    message: 'Birthday cash',
    isCredit: true,
  ),
  _MintCase(
    name: 'Diwali bonus cash ₹10000',
    amount: 10000,
    category: SpendCategory.income,
    message: 'Diwali bonus cash',
    isCredit: true,
  ),
  _MintCase(
    name: 'freelance cash payout ₹7500',
    amount: 7500,
    category: SpendCategory.income,
    message: 'Freelance cash',
    isCredit: true,
  ),
  _MintCase(
    name: 'sold old phone cash ₹4500',
    amount: 4500,
    category: SpendCategory.income,
    message: 'Sold old phone',
    isCredit: true,
  ),
  _MintCase(
    name: 'returned security deposit cash ₹20000',
    amount: 20000,
    category: SpendCategory.income,
    message: 'Deposit returned',
    isCredit: true,
  ),
  _MintCase(
    name: 'sold scrap kabadiwala ₹350',
    amount: 350,
    category: SpendCategory.income,
    message: 'Kabadiwala scrap',
    isCredit: true,
  ),
  _MintCase(
    name: 'tuition teaching cash ₹3000',
    amount: 3000,
    category: SpendCategory.income,
    message: 'Tuition earnings',
    isCredit: true,
  ),
  _MintCase(
    name: 'roommate rent share received ₹8000',
    amount: 8000,
    category: SpendCategory.income,
    message: 'Roommate rent share',
    isCredit: true,
  ),
  _MintCase(
    name: 'festival seva dakshina received ₹501',
    amount: 501,
    category: SpendCategory.income,
    message: 'Seva dakshina',
    isCredit: true,
  ),

  // —— Other ——
  _MintCase(
    name: 'tip to delivery rider ₹30',
    amount: 30,
    category: SpendCategory.other,
    message: 'Delivery tip',
    isCredit: false,
  ),
  _MintCase(
    name: 'barber haircut ₹150',
    amount: 150,
    category: SpendCategory.other,
    message: 'Barber',
    isCredit: false,
  ),
  _MintCase(
    name: 'laundry / ironing ₹80',
    amount: 80,
    category: SpendCategory.other,
    message: 'Laundry iron',
    isCredit: false,
  ),
  _MintCase(
    name: 'temple donation ₹101',
    amount: 101,
    category: SpendCategory.other,
    message: 'Temple donation',
    isCredit: false,
  ),
  _MintCase(
    name: 'gurudwara golak ₹51',
    amount: 51,
    category: SpendCategory.other,
    message: 'Gurudwara golak',
    isCredit: false,
  ),
  _MintCase(
    name: 'mosque donation ₹201',
    amount: 201,
    category: SpendCategory.other,
    message: 'Mosque donation',
    isCredit: false,
  ),
  _MintCase(
    name: 'church offering ₹100',
    amount: 100,
    category: SpendCategory.other,
    message: 'Church offering',
    isCredit: false,
  ),
  _MintCase(
    name: 'shoe polish street ₹20',
    amount: 20,
    category: SpendCategory.other,
    message: 'Shoe polish',
    isCredit: false,
  ),
  _MintCase(
    name: 'photocopy shop ₹35',
    amount: 35,
    category: SpendCategory.other,
    message: 'Xerox shop',
    isCredit: false,
  ),
  _MintCase(
    name: 'notary stamp cash ₹100',
    amount: 100,
    category: SpendCategory.other,
    message: 'Notary stamp',
    isCredit: false,
  ),
  _MintCase(
    name: 'courier COD tip ₹20',
    amount: 20,
    category: SpendCategory.other,
    message: 'Courier tip',
    isCredit: false,
  ),
  _MintCase(
    name: 'watch battery replace ₹150',
    amount: 150,
    category: SpendCategory.other,
    message: 'Watch battery',
    isCredit: false,
  ),
  _MintCase(
    name: 'key duplicate ₹50',
    amount: 50,
    category: SpendCategory.other,
    message: 'Key duplicate',
    isCredit: false,
  ),
  _MintCase(
    name: 'parking attendant tip ₹10',
    amount: 10,
    category: SpendCategory.other,
    message: 'Attendant tip',
    isCredit: false,
  ),
  _MintCase(
    name: 'security guard tip Diwali ₹500',
    amount: 500,
    category: SpendCategory.other,
    message: 'Guard Diwali tip',
    isCredit: false,
  ),
  _MintCase(
    name: 'building liftman tip ₹200',
    amount: 200,
    category: SpendCategory.other,
    message: 'Liftman tip',
    isCredit: false,
  ),

  // —— Hindi / emoji merchants ——
  _MintCase(
    name: 'Hindi merchant चाय की दुकान ₹25',
    amount: 25,
    category: SpendCategory.food,
    message: 'चाय की दुकान',
    isCredit: false,
  ),
  _MintCase(
    name: 'Hindi सब्ज़ी वाला ₹90',
    amount: 90,
    category: SpendCategory.shopping,
    message: 'सब्ज़ी वाला',
    isCredit: false,
  ),
  _MintCase(
    name: 'emoji merchant 🛕 donation ₹151',
    amount: 151,
    category: SpendCategory.other,
    message: '🛕 Temple',
    isCredit: false,
  ),
  _MintCase(
    name: 'emoji ☕ chai ₹18',
    amount: 18,
    category: SpendCategory.food,
    message: '☕ Chai',
    isCredit: false,
  ),
  _MintCase(
    name: 'mixed Hindi+English ऑटो ₹70',
    amount: 70,
    category: SpendCategory.travel,
    message: 'ऑटो to station',
    isCredit: false,
  ),

  // —— Backdated lifestyle ——
  _MintCase(
    name: 'backdated last-week petrol',
    amount: 600,
    category: SpendCategory.travel,
    message: 'Petrol last week',
    isCredit: false,
    date: DateTime(2026, 8, 20),
  ),
  _MintCase(
    name: 'backdated month-boundary maid July',
    amount: 6000,
    category: SpendCategory.bills,
    message: 'July maid salary',
    isCredit: false,
    date: DateTime(2026, 7, 31),
  ),
  _MintCase(
    name: 'backdated leap day 2024 medicine',
    amount: 220,
    category: SpendCategory.health,
    message: 'Leap day pharmacy',
    isCredit: false,
    date: DateTime(2024, 2, 29),
  ),
  _MintCase(
    name: 'yesterday street food',
    amount: 95,
    category: SpendCategory.food,
    message: 'Yesterday chaat',
    isCredit: false,
    date: DateTime(2026, 8, 26),
  ),
  _MintCase(
    name: 'year-ago festival shopping',
    amount: 2800,
    category: SpendCategory.shopping,
    message: 'Last Diwali shopping',
    isCredit: false,
    date: DateTime(2025, 10, 28),
  ),
];
