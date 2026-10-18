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
  const AppUser({
    required this.id,
    required this.email,
    this.fullName,
    this.avatarUrl,
    this.pendingEmail,
  });

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
  const Category({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    this.type,
  });

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

class Transaction {
  const Transaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.date,
    required this.category,
    this.note,
  });

  final String id;
  final TxType type;
  final int amount;
  final DateTime date;
  final Category category;
  final String? note;

  factory Transaction.fromJson(Map<String, dynamic> json, {DateTime? date}) {
    final type = TxType.parse(json['type'] as String);
    return Transaction(
      id: json['id'] as String,
      type: type,
      amount: _int(json['amount']),
      date: json['transaction_date'] != null ? _date(json['transaction_date'] as String) : date!,
      category: Category.fromJson(json['category'] as Map<String, dynamic>, type: type),
      note: json['note'] as String?,
    );
  }
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
  const WishlistSaving({required this.id, required this.amount, required this.date, this.note});

  final String id;
  final int amount;
  final DateTime date;
  final String? note;

  bool get isDeposit => amount > 0;

  factory WishlistSaving.fromJson(Map<String, dynamic> json) => WishlistSaving(
        id: json['id'] as String,
        amount: _int(json['amount']),
        date: _date(json['saving_date'] as String),
        note: json['note'] as String?,
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
  });

  final int income;
  final int expense;
  final int balance;
  final int count;

  factory ReportSummary.fromJson(Map<String, dynamic> json) => ReportSummary(
        income: _int(json['total_income']),
        expense: _int(json['total_expense']),
        balance: _int(json['balance']),
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
