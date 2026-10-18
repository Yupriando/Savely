import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/data/models.dart';
import 'package:frontend/features/bills/bills_screen.dart';
import 'package:frontend/features/budgets/budgets_screen.dart';
import 'package:intl/date_symbol_data_local.dart';

const _cat = {'id': 'c1', 'name': 'IPL', 'icon': 'apartment', 'color': '#0EA5E9'};

Map<String, dynamic> _bill({String status = 'due_soon', int days = 2, Map<String, dynamic>? payment}) => {
  'id': 'b1',
  'name': 'IPL Apartemen',
  'type': 'expense',
  'category_id': 'c1',
  'wallet_id': null,
  'amount': 750000,
  'due_day': 10,
  'remind_days': 3,
  'note': null,
  'is_active': true,
  'category': _cat,
  'wallet': null,
  'due_date': '2026-10-10',
  'days_until_due': days,
  'status': status,
  'payment': payment,
};

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  test('Bill.fromJson + label jatuh tempo', () {
    final soon = Bill.fromJson(_bill());
    expect(soon.status, BillStatus.dueSoon);
    expect(soon.needsAttention, isTrue);
    expect(billDueLabel(soon), 'Jatuh tempo 2 hari lagi');

    expect(billDueLabel(Bill.fromJson(_bill(days: 0))), 'Jatuh tempo hari ini');
    expect(billDueLabel(Bill.fromJson(_bill(status: 'overdue', days: -3))), 'Lewat 3 hari');

    final paid = Bill.fromJson(
      _bill(status: 'paid', payment: {'transaction_id': 't1', 'amount': 700000, 'date': '2026-10-08'}),
    );
    expect(paid.isPaid, isTrue);
    expect(paid.paidAmount, 700000);
    expect(billDueLabel(paid), startsWith('Dibayar 8 Okt'));
  });

  test('WalletsData memilih dompet utama & mengabaikan yang diarsipkan', () {
    final data = WalletsData.fromJson({
      'total_balance': 5000000,
      'wallets': [
        {
          'id': 'w1',
          'name': 'Tunai',
          'type': 'cash',
          'icon': 'payments',
          'color': '#10B981',
          'initial_balance': 0,
          'balance': 1000000,
          'is_default': false,
          'archived': false,
        },
        {
          'id': 'w2',
          'name': 'BCA',
          'type': 'bank',
          'icon': 'account_balance',
          'color': '#2563EB',
          'initial_balance': 0,
          'balance': 4000000,
          'is_default': true,
          'archived': false,
        },
        {
          'id': 'w3',
          'name': 'Lama',
          'type': 'other',
          'icon': 'account_balance_wallet',
          'color': '#9E9E9E',
          'initial_balance': 0,
          'balance': 0,
          'is_default': false,
          'archived': true,
        },
      ],
    });
    expect(data.active.map((w) => w.name), ['Tunai', 'BCA']);
    expect(data.defaultWallet?.name, 'BCA');
    expect(data.wallets[1].type, WalletType.bank);
  });

  test('ReportSummary membaca total ditabung', () {
    final s = ReportSummary.fromJson({
      'total_income': 5000000,
      'total_expense': 400000,
      'total_saved': 400000,
      'balance': 4200000,
      'cashflow': 4600000,
      'transaction_count': 3,
    });
    expect(s.saved, 400000);
    expect(s.balance, 4200000);
    expect(s.cashflow, 4600000);
  });

  testWidgets('BudgetTile tampil tanpa overflow & warnanya sesuai status', (tester) async {
    tester.view.physicalSize = const Size(360, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final over = Budget.fromJson({
      'id': 'bg1',
      'category_id': 'c1',
      'amount': 1500000,
      'spent': 1800000,
      'remaining': -300000,
      'percent': 120,
      'status': 'over',
      'category': {'id': 'c1', 'name': 'Makanan & Minuman', 'icon': 'restaurant', 'color': '#FF7043'},
    });
    expect(budgetColor(over.status), budgetColor(BudgetStatus.over));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BudgetTile(budget: over)),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    expect(find.text('Makanan & Minuman'), findsOneWidget);
    expect(find.text('120%'), findsOneWidget);
  });
}
