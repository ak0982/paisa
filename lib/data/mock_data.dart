import '../models/bank_account.dart';
import '../models/budget.dart';
import '../models/category_info.dart';
import '../models/transaction.dart';
import '../theme/paisa_colors.dart';

class MockData {
  static const userName = 'Aarav';
  static const userFullName = 'Aarav Sharma';
  static const userEmail = 'aarav.sharma@gmail.com';
  static const userInitials = 'AS';

  static const monthlySpent = 42800.0;
  static const monthlyIncome = 68000.0;
  static const monthlySaved = 25200.0;
  static const savingsRate = 0.37;
  static const totalBudget = 25000.0;
  static const budgetSpent = 21808.0;

  static final transactions = <Transaction>[
    Transaction(
      id: '1',
      merchant: 'Swiggy',
      bank: 'HDFC',
      maskedAccount: '••••4321',
      category: SpendCategory.food,
      amount: 486,
      isCredit: false,
      timestamp: DateTime(2026, 7, 7, 12, 30),
    ),
    Transaction(
      id: '2',
      merchant: 'Amazon.in',
      bank: 'ICICI',
      maskedAccount: '••••8890',
      category: SpendCategory.shopping,
      amount: 2499,
      isCredit: false,
      timestamp: DateTime(2026, 7, 7, 10, 15),
    ),
    Transaction(
      id: '3',
      merchant: 'Ola',
      bank: 'Axis',
      maskedAccount: '••••2015',
      category: SpendCategory.travel,
      amount: 312,
      isCredit: false,
      timestamp: DateTime(2026, 7, 7, 8, 45),
    ),
    Transaction(
      id: '4',
      merchant: 'Jio Recharge',
      bank: 'HDFC',
      maskedAccount: '••••4321',
      category: SpendCategory.bills,
      amount: 299,
      isCredit: false,
      timestamp: DateTime(2026, 7, 6, 18, 0),
    ),
    Transaction(
      id: '5',
      merchant: 'Zomato',
      bank: 'Kotak',
      maskedAccount: '••••7756',
      category: SpendCategory.food,
      amount: 645,
      isCredit: false,
      timestamp: DateTime(2026, 7, 6, 21, 30),
    ),
    Transaction(
      id: '6',
      merchant: 'Netflix',
      bank: 'ICICI',
      maskedAccount: '••••8890',
      category: SpendCategory.entertainment,
      amount: 649,
      isCredit: false,
      timestamp: DateTime(2026, 7, 5, 9, 0),
    ),
    Transaction(
      id: '7',
      merchant: 'Salary — Acme Corp',
      bank: 'Axis',
      maskedAccount: '••••2015',
      category: SpendCategory.income,
      amount: 68000,
      isCredit: true,
      timestamp: DateTime(2026, 7, 1, 9, 0),
    ),
    Transaction(
      id: '8',
      merchant: 'HDFC Home Loan EMI',
      bank: 'HDFC',
      maskedAccount: '••••4321',
      category: SpendCategory.emi,
      amount: 8500,
      isCredit: false,
      timestamp: DateTime(2026, 7, 3, 8, 0),
    ),
    Transaction(
      id: '9',
      merchant: 'Reliance Digital',
      bank: 'SBI',
      maskedAccount: '••••3301',
      category: SpendCategory.shopping,
      amount: 1686,
      isCredit: false,
      timestamp: DateTime(2026, 7, 4, 14, 0),
    ),
    Transaction(
      id: '10',
      merchant: 'IRCTC',
      bank: 'HDFC',
      maskedAccount: '••••4321',
      category: SpendCategory.travel,
      amount: 2490,
      isCredit: false,
      timestamp: DateTime(2026, 7, 2, 11, 0),
    ),
    Transaction(
      id: '11',
      merchant: 'BigBasket',
      bank: 'ICICI',
      maskedAccount: '••••8890',
      category: SpendCategory.food,
      amount: 1842,
      isCredit: false,
      timestamp: DateTime(2026, 7, 2, 19, 0),
    ),
    Transaction(
      id: '12',
      merchant: 'MakeMyTrip',
      bank: 'Axis',
      maskedAccount: '••••2015',
      category: SpendCategory.travel,
      amount: 4200,
      isCredit: false,
      timestamp: DateTime(2026, 6, 28, 16, 0),
    ),
    Transaction(
      id: '13',
      merchant: 'Dunzo',
      bank: 'Kotak',
      maskedAccount: '••••7756',
      category: SpendCategory.food,
      amount: 227,
      isCredit: false,
      timestamp: DateTime(2026, 6, 27, 22, 0),
    ),
  ];

  static final budgets = <Budget>[
    const Budget(category: SpendCategory.food, spent: 2800, limit: 4000),
    const Budget(category: SpendCategory.travel, spent: 3290, limit: 3500),
    const Budget(category: SpendCategory.shopping, spent: 4100, limit: 4000),
    const Budget(category: SpendCategory.emi, spent: 8500, limit: 8500),
    const Budget(category: SpendCategory.bills, spent: 1180, limit: 2000),
    const Budget(category: SpendCategory.health, spent: 640, limit: 1500),
    const Budget(
      category: SpendCategory.entertainment,
      spent: 1298,
      limit: 1500,
    ),
  ];

  static final bankAccounts = <BankAccount>[
    const BankAccount(
      bank: 'HDFC',
      name: 'HDFC Savings',
      mask: '••••4321',
      badge: 'H',
      color: PaisaColors.bankHdfc,
      evidenceKey: 'HDFC|••••4321',
    ),
    const BankAccount(
      bank: 'ICICI',
      name: 'ICICI Credit Card',
      mask: '••••8890',
      badge: 'I',
      color: PaisaColors.bankIcici,
      evidenceKey: 'ICICI|••••8890',
    ),
    const BankAccount(
      bank: 'Axis',
      name: 'Axis Salary',
      mask: '••••2015',
      badge: 'A',
      color: PaisaColors.bankAxis,
      evidenceKey: 'Axis|••••2015',
    ),
    const BankAccount(
      bank: 'SBI',
      name: 'SBI Savings',
      mask: '••••3301',
      badge: 'S',
      color: PaisaColors.bankSbi,
      evidenceKey: 'SBI|••••3301',
    ),
    const BankAccount(
      bank: 'Kotak',
      name: 'Kotak 811',
      mask: '••••7756',
      badge: 'K',
      color: PaisaColors.bankKotak,
      evidenceKey: 'Kotak|••••7756',
    ),
  ];

  static const categorySpending = <SpendCategory, double>{
    SpendCategory.emi: 8500,
    SpendCategory.shopping: 4100,
    SpendCategory.travel: 3290,
    SpendCategory.food: 3200,
    SpendCategory.entertainment: 1298,
    SpendCategory.bills: 1180,
    SpendCategory.health: 640,
  };

  static const topMerchants = [
    ('HDFC Home Loan EMI', '1 transaction', 8500.0),
    ('MakeMyTrip', '2 transactions', 4200.0),
    ('Amazon.in', '3 transactions', 4185.0),
    ('IRCTC', '1 transaction', 2490.0),
    ('Swiggy', '8 transactions', 1842.0),
  ];

  static const dailyAverage = 1380.0;
  static const highestDay = 9240.0;
  static const moreThanJune = 4200.0;
  static const foodDelta = 1200.0;
}
