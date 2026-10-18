import 'dart:ui';

enum TxType {
  income,
  expense;

  bool get isIncome => this == TxType.income;
  String get label => isIncome ? 'Pemasukan' : 'Pengeluaran';

  static TxType parse(String value) => value == 'income' ? TxType.income : TxType.expense;
}

enum WishlistStatus {
  active,
  achieved,
  cancelled;

  static WishlistStatus parse(String value) =>
      WishlistStatus.values.firstWhere((s) => s.name == value, orElse: () => WishlistStatus.active);
}

Color _parseColor(String? hex) {
  if (hex == null || hex.length != 7) return const Color(0xFF9E9E9E);
  return Color(int.parse(hex.substring(1), radix: 16) | 0xFF000000);
}

DateTime _date(String value) => DateTime.parse(value);
int _int(dynamic v) => (v as num?)?.toInt() ?? 0;

class AppUser {
  const AppUser({required this.id, required this.email, this.fullName, this.avatarUrl, this.pendingEmail});

  final String id;
  final String email;
  final String? fullName;
  final String? avatarUrl;

  /// Email baru yang belum dikonfirmasi.
  final String? pendingEmail;

  String get initial => displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

  String get displayName =>
      (fullName != null && fullName!.trim().isNotEmpty) ? fullName!.trim() : email.split('@').first;

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'] as String,
    email: (json['email'] as String?) ?? '',
    fullName: json['full_name'] as String?,
    avatarUrl: json['avatar_url'] as String?,
    pendingEmail: json['pending_email'] as String?,
  );
}

class Category {
  const Category({required this.id, required this.name, required this.icon, required this.color, this.type});

  final String id;
  final String name;
  final String icon;
  final Color color;
  final TxType? type;

  factory Category.fromJson(Map<String, dynamic> json, {TxType? type}) => Category(
    id: json['id'] as String,
    name: json['name'] as String,
    icon: (json['icon'] as String?) ?? 'category',
    color: _parseColor(json['color'] as String?),
    type: json['type'] != null ? TxType.parse(json['type'] as String) : type,
  );
}

/// Ringkasan objek lain (dompet, kategori) yang ikut di response.
class Ref {
  const Ref({required this.id, required this.name, required this.icon, required this.color});

  final String id;
  final String name;
  final String icon;
  final Color color;

  static Ref? maybe(dynamic json) {
    if (json is! Map<String, dynamic>) return null;
    return Ref(
      id: json['id'] as String,
      name: json['name'] as String,
      icon: (json['icon'] as String?) ?? 'category',
      color: _parseColor(json['color'] as String?),
    );
  }
}

class Transaction {
  const Transaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.date,
    required this.category,
    this.note,
    this.walletId,
    this.wallet,
    this.billId,
  });

  final String id;
  final TxType type;
  final int amount;
  final DateTime date;
  final Category category;
  final String? note;
  final String? walletId;
  final Ref? wallet;

  /// Terisi kalau transaksi ini hasil "bayar tagihan rutin".
  final String? billId;

  factory Transaction.fromJson(Map<String, dynamic> json, {DateTime? date}) {
    final type = TxType.parse(json['type'] as String);
    return Transaction(
      id: json['id'] as String,
      type: type,
      amount: _int(json['amount']),
      date: json['transaction_date'] != null ? _date(json['transaction_date'] as String) : date!,
      category: Category.fromJson(json['category'] as Map<String, dynamic>, type: type),
      note: json['note'] as String?,
      walletId: json['wallet_id'] as String?,
      wallet: Ref.maybe(json['wallet']),
      billId: json['bill_id'] as String?,
    );
  }
}

class TxPage {
  const TxPage({required this.items, required this.total});

  final List<Transaction> items;
  final int total;
}

class SavingPlan {
  const SavingPlan({
    required this.daysLeft,
    required this.isOverdue,
    required this.perDay,
    required this.perWeek,
    required this.perMonth,
  });

  final int daysLeft;
  final bool isOverdue;
  final int perDay;
  final int perWeek;
  final int perMonth;

  factory SavingPlan.fromJson(Map<String, dynamic> json) => SavingPlan(
    daysLeft: _int(json['days_left']),
    isOverdue: json['is_overdue'] as bool? ?? false,
    perDay: _int(json['per_day']),
    perWeek: _int(json['per_week']),
    perMonth: _int(json['per_month']),
  );
}

class WishlistSaving {
  const WishlistSaving({
    required this.id,
    required this.amount,
    required this.date,
    this.note,
    this.walletId,
    this.wallet,
  });

  final String id;
  final int amount;
  final DateTime date;
  final String? note;
  final String? walletId;
  final Ref? wallet;

  bool get isDeposit => amount > 0;

  factory WishlistSaving.fromJson(Map<String, dynamic> json) => WishlistSaving(
    id: json['id'] as String,
    amount: _int(json['amount']),
    date: _date(json['saving_date'] as String),
    note: json['note'] as String?,
    walletId: json['wallet_id'] as String?,
    wallet: Ref.maybe(json['wallet']),
  );
}

class Wishlist {
  const Wishlist({
    required this.id,
    required this.name,
    required this.targetAmount,
    required this.targetDate,
    required this.status,
    required this.savedAmount,
    required this.remainingAmount,
    required this.progressPercent,
    required this.plan,
    this.note,
    this.savings = const [],
  });

  final String id;
  final String name;
  final int targetAmount;
  final DateTime targetDate;
  final WishlistStatus status;
  final int savedAmount;
  final int remainingAmount;
  final double progressPercent;
  final SavingPlan plan;
  final String? note;
  final List<WishlistSaving> savings;

  double get progress => (progressPercent / 100).clamp(0, 1);
  bool get isAchieved => status == WishlistStatus.achieved;

  factory Wishlist.fromJson(Map<String, dynamic> json) => Wishlist(
    id: json['id'] as String,
    name: json['name'] as String,
    targetAmount: _int(json['target_amount']),
    targetDate: _date(json['target_date'] as String),
    status: WishlistStatus.parse(json['status'] as String),
    savedAmount: _int(json['saved_amount']),
    remainingAmount: _int(json['remaining_amount']),
    progressPercent: (json['progress_percent'] as num?)?.toDouble() ?? 0,
    plan: SavingPlan.fromJson(json['saving_plan'] as Map<String, dynamic>),
    note: json['note'] as String?,
    savings: (json['savings'] as List<dynamic>? ?? [])
        .map((e) => WishlistSaving.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class ReportSummary {
  const ReportSummary({
    required this.income,
    required this.expense,
    required this.balance,
    required this.count,
    this.saved = 0,
    this.cashflow = 0,
  });

  final int income;
  final int expense;

  /// Bersih disetor ke tabungan wishlist.
  final int saved;

  /// Sisa uang: pemasukan - pengeluaran - ditabung.
  final int balance;

  /// Pemasukan - pengeluaran.
  final int cashflow;
  final int count;

  factory ReportSummary.fromJson(Map<String, dynamic> json) => ReportSummary(
    income: _int(json['total_income']),
    expense: _int(json['total_expense']),
    saved: _int(json['total_saved']),
    balance: _int(json['balance']),
    cashflow: _int(json['cashflow']),
    count: _int(json['transaction_count']),
  );
}

class CategoryTotal {
  const CategoryTotal({
    required this.categoryId,
    required this.name,
    required this.icon,
    required this.color,
    required this.total,
    required this.count,
    required this.percentage,
  });

  final String categoryId;
  final String name;
  final String icon;
  final Color color;
  final int total;
  final int count;
  final double percentage;

  factory CategoryTotal.fromJson(Map<String, dynamic> json) => CategoryTotal(
    categoryId: json['category_id'] as String,
    name: json['category_name'] as String,
    icon: (json['icon'] as String?) ?? 'category',
    color: _parseColor(json['color'] as String?),
    total: _int(json['total']),
    count: _int(json['transaction_count']),
    percentage: (json['percentage'] as num?)?.toDouble() ?? 0,
  );

  static List<CategoryTotal> listFrom(dynamic json) =>
      (json as List<dynamic>).map((e) => CategoryTotal.fromJson(e as Map<String, dynamic>)).toList();
}

class DailyTotal {
  const DailyTotal({required this.day, required this.income, required this.expense});

  final DateTime day;
  final int income;
  final int expense;

  factory DailyTotal.fromJson(Map<String, dynamic> json) => DailyTotal(
    day: _date(json['day'] as String),
    income: _int(json['income']),
    expense: _int(json['expense']),
  );
}

class MonthlyTotal {
  const MonthlyTotal({
    required this.month,
    required this.income,
    required this.expense,
    required this.balance,
  });

  final DateTime month;
  final int income;
  final int expense;
  final int balance;

  factory MonthlyTotal.fromJson(Map<String, dynamic> json) => MonthlyTotal(
    month: _date('${json['month']}-01'),
    income: _int(json['income']),
    expense: _int(json['expense']),
    balance: _int(json['balance']),
  );
}

class MonthlyReport {
  const MonthlyReport({
    required this.summary,
    required this.dailyTotals,
    required this.expenseByCategory,
    required this.incomeByCategory,
  });

  final ReportSummary summary;
  final List<DailyTotal> dailyTotals;
  final List<CategoryTotal> expenseByCategory;
  final List<CategoryTotal> incomeByCategory;

  factory MonthlyReport.fromJson(Map<String, dynamic> json) => MonthlyReport(
    summary: ReportSummary.fromJson(json['summary'] as Map<String, dynamic>),
    dailyTotals: (json['daily_totals'] as List<dynamic>)
        .map((e) => DailyTotal.fromJson(e as Map<String, dynamic>))
        .toList(),
    expenseByCategory: CategoryTotal.listFrom(json['expense_by_category']),
    incomeByCategory: CategoryTotal.listFrom(json['income_by_category']),
  );
}

class DailyReport {
  const DailyReport({
    required this.summary,
    required this.expenseByCategory,
    required this.incomeByCategory,
    required this.transactions,
  });

  final ReportSummary summary;
  final List<CategoryTotal> expenseByCategory;
  final List<CategoryTotal> incomeByCategory;
  final List<Transaction> transactions;

  factory DailyReport.fromJson(Map<String, dynamic> json) {
    final date = _date(json['date'] as String);
    return DailyReport(
      summary: ReportSummary.fromJson(json['summary'] as Map<String, dynamic>),
      expenseByCategory: CategoryTotal.listFrom(json['expense_by_category']),
      incomeByCategory: CategoryTotal.listFrom(json['income_by_category']),
      transactions: (json['transactions'] as List<dynamic>)
          .map((e) => Transaction.fromJson(e as Map<String, dynamic>, date: date))
          .toList(),
    );
  }
}

// =============================================================
// Dompet & transfer
// =============================================================

enum WalletType {
  cash('Tunai', 'payments'),
  bank('Bank', 'account_balance'),
  ewallet('E-wallet', 'phone_iphone'),
  other('Lainnya', 'account_balance_wallet');

  const WalletType(this.label, this.defaultIcon);

  final String label;
  final String defaultIcon;

  static WalletType parse(String? v) =>
      WalletType.values.firstWhere((t) => t.name == v, orElse: () => WalletType.other);
}

class Wallet {
  const Wallet({
    required this.id,
    required this.name,
    required this.type,
    required this.icon,
    required this.color,
    required this.initialBalance,
    required this.balance,
    required this.isDefault,
    required this.archived,
  });

  final String id;
  final String name;
  final WalletType type;
  final String icon;
  final Color color;
  final int initialBalance;
  final int balance;
  final bool isDefault;
  final bool archived;

  factory Wallet.fromJson(Map<String, dynamic> json) => Wallet(
    id: json['id'] as String,
    name: json['name'] as String,
    type: WalletType.parse(json['type'] as String?),
    icon: (json['icon'] as String?) ?? 'account_balance_wallet',
    color: _parseColor(json['color'] as String?),
    initialBalance: _int(json['initial_balance']),
    balance: _int(json['balance']),
    isDefault: json['is_default'] as bool? ?? false,
    archived: json['archived'] as bool? ?? false,
  );
}

class WalletsData {
  const WalletsData({required this.totalBalance, required this.wallets});

  final int totalBalance;
  final List<Wallet> wallets;

  List<Wallet> get active => wallets.where((w) => !w.archived).toList();

  Wallet? get defaultWallet {
    for (final w in active) {
      if (w.isDefault) return w;
    }
    return active.isEmpty ? null : active.first;
  }

  factory WalletsData.fromJson(Map<String, dynamic> json) => WalletsData(
    totalBalance: _int(json['total_balance']),
    wallets: (json['wallets'] as List<dynamic>)
        .map((e) => Wallet.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class Transfer {
  const Transfer({
    required this.id,
    required this.from,
    required this.to,
    required this.amount,
    required this.date,
    this.note,
  });

  final String id;
  final Ref from;
  final Ref to;
  final int amount;
  final DateTime date;
  final String? note;

  factory Transfer.fromJson(Map<String, dynamic> json) => Transfer(
    id: json['id'] as String,
    from: Ref.maybe(json['from_wallet'])!,
    to: Ref.maybe(json['to_wallet'])!,
    amount: _int(json['amount']),
    date: _date(json['transfer_date'] as String),
    note: json['note'] as String?,
  );
}

// =============================================================
// Anggaran
// =============================================================

enum BudgetStatus {
  safe,
  warning,
  over;

  static BudgetStatus parse(String? v) =>
      BudgetStatus.values.firstWhere((s) => s.name == v, orElse: () => BudgetStatus.safe);
}

class Budget {
  const Budget({
    required this.id,
    required this.categoryId,
    required this.amount,
    required this.spent,
    required this.remaining,
    required this.percent,
    required this.status,
    required this.category,
  });

  final String id;
  final String categoryId;
  final int amount;
  final int spent;
  final int remaining;
  final double percent;
  final BudgetStatus status;
  final Ref category;

  factory Budget.fromJson(Map<String, dynamic> json) => Budget(
    id: json['id'] as String,
    categoryId: json['category_id'] as String,
    amount: _int(json['amount']),
    spent: _int(json['spent']),
    remaining: _int(json['remaining']),
    percent: (json['percent'] as num?)?.toDouble() ?? 0,
    status: BudgetStatus.parse(json['status'] as String?),
    category: Ref.maybe(json['category'])!,
  );
}

class BudgetReport {
  const BudgetReport({required this.totalBudget, required this.totalSpent, required this.items});

  final int totalBudget;
  final int totalSpent;
  final List<Budget> items;

  factory BudgetReport.fromJson(Map<String, dynamic> json) => BudgetReport(
    totalBudget: _int(json['total_budget']),
    totalSpent: _int(json['total_spent']),
    items: (json['items'] as List<dynamic>).map((e) => Budget.fromJson(e as Map<String, dynamic>)).toList(),
  );
}

// =============================================================
// Tagihan rutin
// =============================================================

enum BillStatus {
  overdue('Lewat jatuh tempo'),
  dueSoon('Segera'),
  upcoming('Nanti'),
  paid('Lunas'),
  inactive('Nonaktif');

  const BillStatus(this.label);

  final String label;

  static BillStatus parse(String? v) => switch (v) {
    'overdue' => BillStatus.overdue,
    'due_soon' => BillStatus.dueSoon,
    'paid' => BillStatus.paid,
    'inactive' => BillStatus.inactive,
    _ => BillStatus.upcoming,
  };
}

class Bill {
  const Bill({
    required this.id,
    required this.name,
    required this.type,
    required this.categoryId,
    required this.amount,
    required this.dueDay,
    required this.remindDays,
    required this.isActive,
    required this.category,
    required this.dueDate,
    required this.daysUntilDue,
    required this.status,
    this.walletId,
    this.wallet,
    this.note,
    this.paidAmount,
    this.paidDate,
  });

  final String id;
  final String name;
  final TxType type;
  final String categoryId;
  final int amount;
  final int dueDay;
  final int remindDays;
  final bool isActive;
  final Ref category;
  final DateTime dueDate;
  final int daysUntilDue;
  final BillStatus status;
  final String? walletId;
  final Ref? wallet;
  final String? note;
  final int? paidAmount;
  final DateTime? paidDate;

  bool get isPaid => status == BillStatus.paid;
  bool get needsAttention => status == BillStatus.overdue || status == BillStatus.dueSoon;

  factory Bill.fromJson(Map<String, dynamic> json) {
    final payment = json['payment'] as Map<String, dynamic>?;
    return Bill(
      id: json['id'] as String,
      name: json['name'] as String,
      type: TxType.parse(json['type'] as String),
      categoryId: json['category_id'] as String,
      amount: _int(json['amount']),
      dueDay: _int(json['due_day']),
      remindDays: _int(json['remind_days']),
      isActive: json['is_active'] as bool? ?? true,
      category: Ref.maybe(json['category'])!,
      dueDate: _date(json['due_date'] as String),
      daysUntilDue: _int(json['days_until_due']),
      status: BillStatus.parse(json['status'] as String?),
      walletId: json['wallet_id'] as String?,
      wallet: Ref.maybe(json['wallet']),
      note: json['note'] as String?,
      paidAmount: payment == null ? null : _int(payment['amount']),
      paidDate: payment == null ? null : _date(payment['date'] as String),
    );
  }
}

class BillsReport {
  const BillsReport({required this.totalDue, required this.items});

  final int totalDue;
  final List<Bill> items;

  factory BillsReport.fromJson(Map<String, dynamic> json) => BillsReport(
    totalDue: _int(json['total_due']),
    items: (json['items'] as List<dynamic>).map((e) => Bill.fromJson(e as Map<String, dynamic>)).toList(),
  );
}

// =============================================================
// Insight
// =============================================================

enum InsightTone { positive, negative, warning, neutral }

class Insight {
  const Insight({
    required this.id,
    required this.tone,
    required this.icon,
    required this.title,
    required this.message,
  });

  final String id;
  final InsightTone tone;
  final String icon;
  final String title;
  final String message;

  factory Insight.fromJson(Map<String, dynamic> json) => Insight(
    id: json['id'] as String,
    tone: InsightTone.values.firstWhere((t) => t.name == json['tone'], orElse: () => InsightTone.neutral),
    icon: (json['icon'] as String?) ?? 'lightbulb',
    title: json['title'] as String,
    message: json['message'] as String,
  );
}
